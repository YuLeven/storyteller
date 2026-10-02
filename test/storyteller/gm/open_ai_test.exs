defmodule Storyteller.GM.OpenAITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Storyteller.Auth.{Credentials, TokenStore}
  alias Storyteller.GM.OpenAI

  setup do
    directory = Path.join(System.tmp_dir!(), "storyteller-openai-test-#{Ecto.UUID.generate()}")
    path = Path.join(directory, "credentials.json")
    on_exit(fn -> File.rm_rf(directory) end)

    store = start_supervised!({TokenStore, path: path, name: nil})

    credentials = %Credentials{
      client_id: "fixture-issued-client",
      subject: "fixture-account-subject",
      email: "fixture@example.invalid",
      host_id: TokenStore.host_id(store),
      id_token: "fixture-id-token",
      access_token: "fixture-access-token",
      refresh_token: "fixture-refresh-token",
      expires_at: System.system_time(:second) + 3_600,
      scopes: ["offline_access", "chatgpt.tokens.use.direct"]
    }

    assert :ok = TokenStore.put_credentials(credentials, store)
    %{store: store, credentials: credentials}
  end

  test "chooses a listed account model and sends only preview-supported fields", context do
    test_pid = self()
    completed = completion_event("{\"narration\":\"The rain begins.\"}")
    http = provider_http(test_pid, completed)

    request = %{
      instructions: "Return one JSON object.",
      input: [%{role: "user", content: [%{type: "input_text", text: "Resolve this action."}]}],
      local_context_metrics: %{context_json_bytes: 1234, private_marker: "local-only"}
    }

    assert {:ok, %{text: "{\"narration\":\"The rain begins.\"}"}} =
             OpenAI.stream_response(request, store: context.store, http: http)

    assert_receive {:models_request, options}
    headers = Keyword.fetch!(options, :headers)

    assert Enum.find(headers, fn {name, _} -> name == "authorization" end) ==
             {"authorization", "Bearer fixture-access-token"}

    assert_receive {:responses_request, options}
    body = Keyword.fetch!(options, :json)
    assert body["model"] == "fixture-model"
    assert body["instructions"] == request.instructions
    assert body["input"] == request.input
    assert body["store"] == false
    assert body["stream"] == true
    assert Map.keys(body) |> Enum.sort() == ["input", "instructions", "model", "store", "stream"]
    refute Map.has_key?(body, "previous_response_id")
    refute Jason.encode!(body) =~ "local_context_metrics"
    refute Jason.encode!(body) =~ "local-only"
    assert Keyword.fetch!(options, :into) == :self
  end

  test "sends an explicitly selected model without fetching the account catalog", context do
    test_pid = self()
    http = provider_http(test_pid, completion_event("The selected model answered."))

    assert {:ok, %{text: "The selected model answered."}} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "fixture-model"
               },
               store: context.store,
               http: http
             )

    assert_receive {:responses_request, options}
    assert Keyword.fetch!(options, :json)["model"] == "fixture-model"
    refute_receive {:models_request, _}
    refute_receive {:responses_request, _}
  end

  test "returns model unavailable when a saved model is rejected by Responses", context do
    test_pid = self()

    http = fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          send(test_pid, {:models_request, options})
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          send(test_pid, {:responses_request, options})
          %{status: 400, body: Jason.encode!(%{"error" => %{"code" => "model_not_found"}})}

        true ->
          {:error, :unexpected_request}
      end
    end

    assert {:error, :model_unavailable} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "retired-model"
               },
               store: context.store,
               http: http
             )

    assert_receive {:responses_request, options}
    assert Keyword.fetch!(options, :json)["model"] == "retired-model"
    refute_receive {:models_request, _}
    refute_receive {:responses_request, _}
  end

  test "returns only safe numeric token usage from the completed response", context do
    text = "The rain begins."

    stream =
      completion_event(text, %{
        "input_tokens" => 246,
        "output_tokens" => 31,
        "total_tokens" => 277,
        "input_tokens_details" => %{"cached_tokens" => 100},
        "private_provider_field" => "must not be exposed"
      })

    assert {:ok,
            %{
              text: ^text,
              usage: %{input_tokens: 246, output_tokens: 31}
            }} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: provider_http(self(), stream)
             )
  end

  test "omits missing and malformed token usage without exposing provider payloads", context do
    secret = "PRIVATE_USAGE_PAYLOAD_DO_NOT_LEAK"

    cases = [
      {nil, %{text: "Safe output"}},
      {%{"input_tokens" => secret, "output_tokens" => -1}, %{text: "Safe output"}},
      {%{"input_tokens" => 12.5, "output_tokens" => "invalid-#{secret}"}, %{text: "Safe output"}},
      {%{"input_tokens" => -1, "output_tokens" => 7},
       %{text: "Safe output", usage: %{output_tokens: 7}}}
    ]

    Enum.each(cases, fn {usage, expected} ->
      log =
        capture_log(fn ->
          assert {:ok, ^expected} =
                   OpenAI.stream_response(
                     %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
                     store: context.store,
                     http: provider_http(self(), completion_event("Safe output", usage))
                   )
        end)

      refute log =~ secret
    end)
  end

  test "lists only models visible to the selected account", context do
    http = fn :get, "https://api.openai.com/v1/models", _options ->
      %{status: 200, body: Jason.encode!(model_catalog())}
    end

    assert {:ok, [%{slug: "fixture-model", display_name: "Fixture Model"}]} =
             OpenAI.models(store: context.store, http: http)
  end

  test "does not accept partial text when the SSE stream ends without response.completed",
       context do
    partial =
      "event: response.output_text.delta\ndata: " <>
        Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "partial output"}) <>
        "\n\n"

    http = provider_http(self(), partial)

    assert {:error, :stream_incomplete} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "calls local first-output callback once before completion and emits numeric latency",
       context do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}
    task_ready = make_ref()

    first_delta =
      event_frame("response.output_text.delta", %{
        "type" => "response.output_text.delta",
        "delta" => "The "
      })

    second_delta =
      event_frame("response.output_text.delta", %{
        "type" => "response.output_text.delta",
        "delta" => "answer"
      })

    completed =
      event_frame("response.completed", %{
        "type" => "response.completed",
        "response" => %{"status" => "completed", "output" => []}
      })

    body =
      Stream.resource(
        fn -> :first_delta end,
        fn
          :first_delta ->
            {[first_delta], :wait_for_test}

          :wait_for_test ->
            send(test_pid, :waiting_before_completion)

            receive do
              :continue_stream -> {[second_delta, completed], :done}
            after
              5_000 -> raise "test did not release the fake response stream"
            end

          :done ->
            {:halt, :done}
        end,
        fn _state -> :ok end
      )

    http = fn :post, "https://api.openai.com/v1/responses", options ->
      send(test_pid, {:responses_request, options})
      %{status: 200, body: body}
    end

    telemetry_event = [:storyteller, :gm, :provider, :first_text_delta, :stop]

    task =
      Task.async(fn ->
        receive do
          ^task_ready ->
            OpenAI.stream_response(
              %{
                instructions: "Return text.",
                input: [%{role: "user", content: "Hello"}],
                model: "fixture-model",
                on_first_output: fn -> send(test_pid, :first_output) end,
                on_stream_activity: fn -> send(test_pid, :stream_activity) end
              },
              store: context.store,
              http: http
            )
        end
      end)

    assert :ok =
             :telemetry.attach(
               handler_id,
               telemetry_event,
               fn event, measurements, metadata, _config ->
                 if self() == task.pid do
                   send(test_pid, {:first_text_delta_metric, event, measurements, metadata})
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    send(task.pid, task_ready)
    assert_receive :stream_activity, 1_000
    assert_receive :first_output, 1_000
    assert_receive {:first_text_delta_metric, ^telemetry_event, %{duration: duration}, %{}}, 1_000
    assert is_integer(duration) and duration >= 0
    assert_receive :waiting_before_completion, 1_000
    assert Task.yield(task, 0) == nil
    refute_receive :first_output

    send(task.pid, :continue_stream)
    assert_receive :stream_activity, 1_000
    assert {:ok, %{text: "The answer"}} = Task.await(task, 1_000)
    refute_receive :first_output
    refute_receive {:first_text_delta_metric, ^telemetry_event, _, _}

    assert_receive {:responses_request, options}
    assert Keyword.fetch!(options, :receive_timeout) == 90_000
    request_body = Keyword.fetch!(options, :json)

    assert Map.keys(request_body) |> Enum.sort() == [
             "input",
             "instructions",
             "model",
             "store",
             "stream"
           ]

    refute Jason.encode!(request_body) =~ "on_first_output"
    refute Jason.encode!(request_body) =~ "on_stream_activity"
  end

  test "signals first output once for failed and incomplete streams but not empty streams",
       context do
    parent = self()
    telemetry_event = [:storyteller, :gm, :provider, :first_text_delta, :stop]
    handler_id = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler_id,
               telemetry_event,
               fn event, measurements, metadata, _config ->
                 if self() == parent do
                   send(parent, {:first_text_delta_metric, event, measurements, metadata})
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    first_delta =
      event_frame("response.output_text.delta", %{
        "type" => "response.output_text.delta",
        "delta" => "partial"
      })

    cases = [
      {first_delta <>
         event_frame("response.failed", %{
           "type" => "response.failed",
           "response" => %{"error" => %{"code" => "server_error"}}
         }), :provider_error, true},
      {first_delta <>
         event_frame("response.incomplete", %{
           "type" => "response.incomplete",
           "response" => %{"incomplete_details" => %{"reason" => "max_output_tokens"}}
         }), :stream_incomplete, true},
      {event_frame("response.incomplete", %{
         "type" => "response.incomplete",
         "response" => %{"incomplete_details" => %{"reason" => "max_output_tokens"}}
       }), :stream_incomplete, false}
    ]

    Enum.each(cases, fn {stream, expected_error, has_output?} ->
      callback_tag = make_ref()

      assert {:error, ^expected_error} =
               OpenAI.stream_response(
                 %{
                   instructions: "Return text.",
                   input: [%{role: "user", content: "Hello"}],
                   model: "fixture-model",
                   on_first_output: fn -> send(parent, {:first_output, callback_tag}) end
                 },
                 store: context.store,
                 http: provider_http(self(), stream)
               )

      if has_output? do
        assert_receive {:first_output, ^callback_tag}
        refute_receive {:first_output, ^callback_tag}
        assert_receive {:first_text_delta_metric, ^telemetry_event, %{duration: duration}, %{}}
        assert is_integer(duration) and duration >= 0
      else
        refute_receive {:first_output, ^callback_tag}
        refute_receive {:first_text_delta_metric, ^telemetry_event, _, _}
      end
    end)
  end

  test "uses streamed output text when the terminal response omits its output array", context do
    stream =
      "event: response.output_text.delta\ndata: " <>
        Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "The answer"}) <>
        "\n\nevent: response.completed\ndata: " <>
        Jason.encode!(%{
          "type" => "response.completed",
          "response" => %{
            "status" => "completed",
            "output" => [],
            "usage" => %{"input_tokens" => 8, "output_tokens" => 2}
          }
        }) <>
        "\n\n"

    http = provider_http(self(), stream)

    assert {:ok, %{text: "The answer", usage: %{input_tokens: 8, output_tokens: 2}}} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "maps account plan sharing errors from response.failed", context do
    failure =
      "event: response.failed\ndata: " <>
        Jason.encode!(%{
          "type" => "response.failed",
          "response" => %{
            "error" => %{"code" => "subscription_sharing_usage_limit_exceeded"}
          }
        }) <>
        "\n\n"

    http = provider_http(self(), failure)

    assert {:error, :usage_limit} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "maps documented authorization failures from response.failed to actionable recovery categories",
       context do
    Enum.each(
      [
        {"subscription_sharing_invalid_user", :reauth_required},
        {"chatpass_v2_scope_not_authorized", :authorization_configuration},
        {"chatpass_v2_invalid_authorization_context", :authorization_configuration}
      ],
      fn {error_code, expected_error} ->
        failure =
          "event: response.failed\ndata: " <>
            Jason.encode!(%{
              "type" => "response.failed",
              "response" => %{"error" => %{"code" => error_code}}
            }) <>
            "\n\n"

        assert {:error, ^expected_error} =
                 OpenAI.stream_response(
                   %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
                   store: context.store,
                   http: provider_http(self(), failure)
                 )

        assert_receive {:models_request, _}
        assert_receive {:responses_request, _}
      end
    )
  end

  test "maps plan-sharing errors from asynchronous HTTP error bodies", context do
    error_cases = [
      {429, "subscription_sharing_usage_limit_exceeded", :usage_limit},
      {503, "subscription_sharing_usage_unavailable", :usage_unavailable},
      {503, "subscription_sharing_user_unavailable", :usage_unavailable},
      {403, "subscription_sharing_user_not_eligible", :account_ineligible},
      {403, "policy_violation", :provider_error},
      {403, "subscription_sharing_route_not_supported", :unsupported_capability},
      {400, "subscription_sharing_unsupported_capability", :unsupported_capability}
    ]

    Enum.each(error_cases, fn {status, code, expected} ->
      body = Jason.encode!(%{"error" => %{"code" => code, "param" => "model"}})
      http = provider_http_error(self(), status, async_body(split_stream(body)))

      assert {:error, ^expected} =
               OpenAI.stream_response(
                 %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
                 store: context.store,
                 http: http
               )

      assert_receive {:models_request, _}
      assert_receive {:responses_request, _}
    end)
  end

  test "logs safe HTTP diagnostics without logging campaign input", context do
    request_id = "req_fixture_123"

    http = fn method, url, _options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          %{
            status: 429,
            headers: %{"x-request-id" => [request_id]},
            body:
              Jason.encode!(%{
                "error" => %{
                  "code" => "subscription_sharing_usage_limit_exceeded",
                  "param" => "model"
                }
              })
          }

        true ->
          {:error, :unexpected_request}
      end
    end

    log =
      capture_log(fn ->
        assert {:error, :usage_limit} =
                 OpenAI.stream_response(
                   %{
                     instructions: "Private campaign context that must not be logged.",
                     input: [%{role: "user", content: "Private player action."}]
                   },
                   store: context.store,
                   http: http
                 )
      end)

    assert log =~ "phase=responses status=429 shape=error"
    assert log =~ "code=subscription_sharing_usage_limit_exceeded param=model"
    assert log =~ "request_id=req_fixture_123"
    refute log =~ "Private campaign context"
    refute log =~ "Private player action"
    refute log =~ "fixture-access-token"
  end

  test "logs safe response-stream error details", context do
    request_id = "req_stream_456"

    failure =
      "event: response.failed\ndata: " <>
        Jason.encode!(%{
          "type" => "response.failed",
          "response" => %{
            "error" => %{"code" => "subscription_sharing_usage_limit_exceeded"}
          }
        }) <>
        "\n\n"

    test_pid = self()

    http = fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          send(test_pid, {:responses_request, options})
          %{status: 200, headers: %{"x-request-id" => [request_id]}, body: split_stream(failure)}

        true ->
          {:error, :unexpected_request}
      end
    end

    log =
      capture_log(fn ->
        assert {:error, :usage_limit} =
                 OpenAI.stream_response(
                   %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
                   store: context.store,
                   http: http
                 )
      end)

    assert_receive {:responses_request, _options}
    assert log =~ "phase=response_stream status=200 shape=stream_error"
    assert log =~ "code=subscription_sharing_usage_limit_exceeded"
    assert log =~ "request_id=req_stream_456"
  end

  test "keeps generic 403 errors distinct from an ineligible account", context do
    body = Jason.encode!(%{"detail" => "This request is not permitted in this region."})
    http = provider_http_error(self(), 403, async_body(split_stream(body)))

    assert {:error, :provider_error} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "maps response.incomplete separately from a broken stream", context do
    incomplete =
      "event: response.incomplete\ndata: " <>
        Jason.encode!(%{
          "type" => "response.incomplete",
          "response" => %{"incomplete_details" => %{"reason" => "max_output_tokens"}}
        }) <>
        "\n\n"

    http = provider_http(self(), incomplete)

    assert {:error, :stream_incomplete} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "maps an expired bearer token to reauthentication", context do
    test_pid = self()

    http = fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          send(test_pid, {:models_request, options})
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          %{status: 401, body: Jason.encode!(%{"error" => %{"code" => "invalid_token"}})}

        true ->
          {:error, :unexpected_request}
      end
    end

    assert {:error, :reauth_required} =
             OpenAI.stream_response(
               %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
               store: context.store,
               http: http
             )
  end

  test "rejects explicit system-role input items", context do
    test_pid = self()
    http = provider_http(test_pid, completion_event("unused"))

    assert {:error, :unsupported_capability} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "system", content: "not supported"}]
               },
               store: context.store,
               http: http
             )

    assert_receive {:models_request, _}
    refute_receive {:responses_request, _}
  end

  defp provider_http(test_pid, stream_body) do
    fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          send(test_pid, {:models_request, options})
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          send(test_pid, {:responses_request, options})
          %{status: 200, body: split_stream(stream_body)}

        true ->
          {:error, :unexpected_request}
      end
    end
  end

  defp provider_http_error(test_pid, status, body) do
    fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          send(test_pid, {:models_request, options})
          %{status: 200, body: Jason.encode!(model_catalog())}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          send(test_pid, {:responses_request, options})
          %{status: status, body: body}

        true ->
          {:error, :unexpected_request}
      end
    end
  end

  defp async_body(chunks) do
    ref = make_ref()

    stream_fun = fn
      ^ref, {^ref, {:data, chunk}} -> {:ok, [data: chunk]}
      ^ref, {^ref, :done} -> {:ok, [:done]}
    end

    Enum.each(chunks, &send(self(), {ref, {:data, &1}}))
    send(self(), {ref, :done})

    %Req.Response.Async{
      pid: self(),
      ref: ref,
      stream_fun: stream_fun,
      cancel_fun: fn _ref -> :ok end
    }
  end

  defp model_catalog do
    %{
      "models" => [
        %{"slug" => "fixture-model", "display_name" => "Fixture Model", "visibility" => "list"},
        %{"slug" => "hidden-model", "display_name" => "Hidden", "visibility" => "hidden"}
      ]
    }
  end

  defp event_frame(event, payload) do
    "event: #{event}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  defp completion_event(text, usage \\ nil) do
    response = %{
      "output" => [
        %{
          "type" => "message",
          "content" => [%{"type" => "output_text", "text" => text}]
        }
      ]
    }

    response = if is_map(usage), do: Map.put(response, "usage", usage), else: response

    "event: response.output_text.delta\ndata: " <>
      Jason.encode!(%{"type" => "response.output_text.delta", "delta" => text}) <>
      "\n\nevent: response.completed\ndata: " <>
      Jason.encode!(%{
        "type" => "response.completed",
        "response" => response
      }) <>
      "\n\n"
  end

  defp split_stream(stream) do
    midpoint = div(byte_size(stream), 2)
    <<first::binary-size(midpoint), second::binary>> = stream
    [first, second]
  end
end
