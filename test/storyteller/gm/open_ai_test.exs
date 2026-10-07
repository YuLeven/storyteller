defmodule Storyteller.GM.OpenAITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Storyteller.Auth.{Credentials, TokenStore}
  alias Storyteller.GM.{CampaignLookup, ModelCatalogCache, OpenAI, TurnTelemetry}

  setup do
    directory = Path.join(System.tmp_dir!(), "storyteller-openai-test-#{Ecto.UUID.generate()}")
    path = Path.join(directory, "credentials.json")
    on_exit(fn -> File.rm_rf(directory) end)

    store = start_supervised!({TokenStore, path: path, name: nil})

    credentials = %Credentials{
      client_id: "fixture-issued-client",
      subject: "fixture-account-" <> Ecto.UUID.generate(),
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
    stage_handler_id = attach_turn_stage_handler()
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

    assert_turn_stage(:oauth_access_token, :not_applicable)
    assert_turn_stage(:model_resolution, :miss)
    assert_turn_stage(:request_to_first_output, :not_applicable)
    assert_turn_stage(:provider_stream, :not_applicable)
    :telemetry.detach(stage_handler_id)
  end

  test "sends an explicitly selected model without fetching the account catalog", context do
    test_pid = self()
    stage_handler_id = attach_turn_stage_handler()
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

    assert_turn_stage(:oauth_access_token, :not_applicable)
    assert_turn_stage(:model_resolution, :not_used)
    assert_turn_stage(:request_to_first_output, :not_applicable)
    assert_turn_stage(:provider_stream, :not_applicable)
    :telemetry.detach(stage_handler_id)
  end

  test "maps a fast Req receive-timeout transport error to the quick-retry class", context do
    http = fn :post, "https://api.openai.com/v1/responses", options ->
      assert Keyword.fetch!(options, :receive_timeout) == 90_000
      refute Keyword.has_key?(options, :timeout_classification)
      {:error, %Req.TransportError{reason: :timeout}}
    end

    assert {:error, :network_error} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "gpt-6-luna"
               },
               store: context.store,
               http: http
             )
  end

  test "maps a fast Req receive-timeout error during body enumeration to the quick class",
       context do
    partial_delta =
      "event: response.output_text.delta\ndata: " <>
        Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "partial text"}) <>
        "\n\n"

    http = fn :post, "https://api.openai.com/v1/responses", _options ->
      %{
        status: 200,
        body: async_body_with_error([partial_delta], %Req.TransportError{reason: :timeout}, 0)
      }
    end

    assert {:error, :network_error} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "gpt-6-luna"
               },
               store: context.store,
               http: http
             )
  end

  test "keeps an elapsed Req receive timeout during body enumeration in the long-timeout class",
       context do
    partial_delta =
      "event: response.output_text.delta\ndata: " <>
        Jason.encode!(%{"type" => "response.output_text.delta", "delta" => "partial text"}) <>
        "\n\n"

    http = fn :post, "https://api.openai.com/v1/responses", _options ->
      %{
        status: 200,
        body: async_body_with_error([partial_delta], %Req.TransportError{reason: :timeout}, 150)
      }
    end

    assert {:error, :timeout} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "gpt-6-luna"
               },
               store: context.store,
               http: http,
               response_stream_receive_timeout: 150
             )
  end

  test "executes one local lookup and replays the full completed output before its result",
       context do
    test_pid = self()
    request = lookup_request()

    full_output = [
      %{
        "type" => "reasoning",
        "id" => "rs_fixture",
        "summary" => [%{"type" => "summary_text", "text" => "Checking the ledger."}]
      },
      %{
        "type" => "function_call",
        "call_id" => "call_fixture_1",
        "name" => "lookup_campaign_canon",
        "arguments" => "{\"query\":\"Mara\",\"category\":\"character\"}"
      }
    ]

    first = function_call_completion(full_output, %{"input_tokens" => 12, "output_tokens" => 5})

    second =
      completion_event("Mara is still at the Finca.", %{
        "input_tokens" => 19,
        "output_tokens" => 8
      })

    calls = :atomics.new(1, signed: false)

    http = fn :post, "https://api.openai.com/v1/responses", options ->
      call = :atomics.add_get(calls, 1, 1)
      send(test_pid, {:responses_request, call, options})
      %{status: 200, body: if(call == 1, do: split_stream(first), else: split_stream(second))}
    end

    executor = fn arguments ->
      send(test_pid, {:lookup_arguments, arguments})
      %{"records" => [%{"id" => "mara", "visibility" => "public"}]}
    end

    assert {:ok,
            %{text: "Mara is still at the Finca.", usage: %{input_tokens: 31, output_tokens: 13}}} =
             OpenAI.stream_response(Map.put(request, :campaign_lookup_executor, executor),
               store: context.store,
               http: http
             )

    assert_receive {:lookup_arguments, %{"query" => "Mara", "category" => "character"}}
    assert_receive {:responses_request, 1, first_options}
    first_body = Keyword.fetch!(first_options, :json)
    assert first_body["input"] == request.input
    refute Map.has_key?(first_body, "tools")
    assert first_body["store"] == false and first_body["stream"] == true

    assert_receive {:responses_request, 2, second_options}
    second_body = Keyword.fetch!(second_options, :json)
    expected_output = Jason.encode!(%{"records" => [%{"id" => "mara", "visibility" => "public"}]})

    assert second_body["input"] ==
             request.input ++
               full_output ++
               [
                 %{
                   "type" => "function_call_output",
                   "call_id" => "call_fixture_1",
                   "output" => expected_output
                 }
               ]

    refute Map.has_key?(second_body, "tools")
    refute Map.has_key?(second_body, "previous_response_id")
    assert second_body["store"] == false and second_body["stream"] == true
    refute_receive {:responses_request, _, _}
  end

  test "rejects unknown, malformed, multiple, or unadvertised function calls without retrying",
       context do
    malformed_calls = [
      [%{"type" => "function_call", "call_id" => "c1", "name" => "unknown", "arguments" => "{}"}],
      [
        %{
          "type" => "function_call",
          "call_id" => "",
          "name" => "lookup_campaign_canon",
          "arguments" => "{}"
        }
      ],
      [
        %{
          "type" => "function_call",
          "call_id" => "c1",
          "name" => "lookup_campaign_canon",
          "arguments" => "[]"
        }
      ],
      [
        %{
          "type" => "function_call",
          "call_id" => "c1",
          "name" => "lookup_campaign_canon",
          "arguments" => String.duplicate("x", 6_001)
        }
      ],
      [
        %{
          "type" => "function_call",
          "call_id" => "c1",
          "name" => "lookup_campaign_canon",
          "arguments" => "{}"
        },
        %{
          "type" => "function_call",
          "call_id" => "c2",
          "name" => "lookup_campaign_canon",
          "arguments" => "{}"
        }
      ]
    ]

    Enum.each(malformed_calls, fn calls_to_return ->
      test_pid = self()
      count = :atomics.new(1, signed: false)

      http = fn :post, "https://api.openai.com/v1/responses", options ->
        call = :atomics.add_get(count, 1, 1)
        send(test_pid, {:responses_request, call, options})
        %{status: 200, body: split_stream(function_call_completion(calls_to_return, nil))}
      end

      executor = fn _arguments ->
        send(test_pid, :executor_should_not_run)
        %{}
      end

      assert {:error, _reason} =
               OpenAI.stream_response(
                 Map.put(lookup_request(), :campaign_lookup_executor, executor),
                 store: context.store,
                 http: http
               )

      assert_receive {:responses_request, 1, _}
      refute_receive {:responses_request, _, _}
      refute_receive :executor_should_not_run
    end)
  end

  test "rejects an oversized lookup continuation payload before running the lookup", context do
    output_items = [
      %{
        "type" => "reasoning",
        "id" => "rs_large_fixture",
        "summary" => [
          %{"type" => "summary_text", "text" => String.duplicate("reasoning ", 1_700)}
        ]
      },
      %{
        "type" => "function_call",
        "call_id" => "call_large_fixture",
        "name" => "lookup_campaign_canon",
        "arguments" => "{\"query\":\"Mara\"}"
      }
    ]

    stream = function_call_completion(output_items, nil)
    request = lookup_request()
    executor_called = :atomics.new(1, signed: false)

    executor = fn _arguments ->
      :atomics.put(executor_called, 1, 1)
      %{"records" => []}
    end

    assert {:error, :provider_error} =
             OpenAI.stream_response(
               Map.put(request, :campaign_lookup_executor, executor),
               store: context.store,
               http: provider_http(self(), stream)
             )

    assert_receive {:responses_request, _options}
    refute_receive {:responses_request, _options}
    assert :atomics.get(executor_called, 1) == 0
  end

  test "fails closed when the local lookup executor is missing or returns too much data",
       context do
    tool_call = [
      %{
        "type" => "function_call",
        "call_id" => "call_fixture_2",
        "name" => "lookup_campaign_canon",
        "arguments" => "{\"query\":\"Mara\"}"
      }
    ]

    for executor <- [nil, fn _args -> %{"large" => String.duplicate("x", 6_001)} end] do
      test_pid = self()
      count = :atomics.new(1, signed: false)

      http = fn :post, "https://api.openai.com/v1/responses", options ->
        call = :atomics.add_get(count, 1, 1)
        send(test_pid, {:responses_request, call, options})
        %{status: 200, body: split_stream(function_call_completion(tool_call, nil))}
      end

      request = lookup_request()

      request =
        if executor, do: Map.put(request, :campaign_lookup_executor, executor), else: request

      assert {:error, _reason} = OpenAI.stream_response(request, store: context.store, http: http)
      assert_receive {:responses_request, 1, _}
      refute_receive {:responses_request, _, _}
    end
  end

  test "does not execute unadvertised tools or permit a second lookup in one turn", context do
    call = fn id ->
      %{
        "type" => "function_call",
        "call_id" => id,
        "name" => "lookup_campaign_canon",
        "arguments" => "{\"query\":\"Mara\"}"
      }
    end

    unadvertised_request = lookup_request() |> Map.update!(:input, &Enum.take(&1, 1))
    test_pid = self()

    unadvertised_http = fn :post, "https://api.openai.com/v1/responses", options ->
      send(test_pid, {:responses_request, options})
      %{status: 200, body: split_stream(function_call_completion([call.("unadvertised")], nil))}
    end

    assert {:error, :invalid_response} =
             OpenAI.stream_response(unadvertised_request,
               store: context.store,
               http: unadvertised_http
             )

    assert_receive {:responses_request, _}
    refute_receive {:responses_request, _}

    call_count = :atomics.new(1, signed: false)
    executor_count = :atomics.new(1, signed: false)

    http = fn :post, "https://api.openai.com/v1/responses", options ->
      round = :atomics.add_get(call_count, 1, 1)
      send(test_pid, {:responses_request, round, options})

      %{status: 200, body: split_stream(function_call_completion([call.("call_#{round}")], nil))}
    end

    executor = fn _arguments ->
      :atomics.add(executor_count, 1, 1)
      %{"found" => true}
    end

    assert {:error, :unsupported_capability} =
             OpenAI.stream_response(
               Map.put(lookup_request(), :campaign_lookup_executor, executor),
               store: context.store,
               http: http
             )

    assert_receive {:responses_request, 1, _}
    assert_receive {:responses_request, 2, _}
    refute_receive {:responses_request, 3, _}
    assert :atomics.get(executor_count, 1) == 1
  end

  test "enforces exact serialized byte limits for the initial and tool continuation bodies",
       context do
    request = lookup_request()

    initial_body = %{
      "model" => "fixture-model",
      "instructions" => request.instructions,
      "input" => request.input,
      "store" => false,
      "stream" => true
    }

    initial_limit = byte_size(Jason.encode!(initial_body)) - 1
    initial_http = provider_http(self(), completion_event("unused"))

    assert {:error, :context_budget_exceeded} =
             OpenAI.stream_response(Map.put(request, :request_size_limit_bytes, initial_limit),
               store: context.store,
               http: initial_http
             )

    refute_receive {:responses_request, _}

    output_items = [
      %{
        "type" => "function_call",
        "call_id" => "call_fixture_3",
        "name" => "lookup_campaign_canon",
        "arguments" => "{\"query\":\"Mara\"}"
      }
    ]

    call_stream = function_call_completion(output_items, nil)
    output_json = Jason.encode!(%{"found" => true})

    continuation_body = %{
      initial_body
      | "input" =>
          request.input ++
            output_items ++
            [
              %{
                "type" => "function_call_output",
                "call_id" => "call_fixture_3",
                "output" => output_json
              }
            ]
    }

    continuation_limit = byte_size(Jason.encode!(continuation_body)) - 1
    test_pid = self()
    calls = :atomics.new(1, signed: false)

    http = fn :post, "https://api.openai.com/v1/responses", options ->
      call = :atomics.add_get(calls, 1, 1)
      send(test_pid, {:responses_request, call, options})
      %{status: 200, body: split_stream(call_stream)}
    end

    executor = fn _arguments -> %{"found" => true} end

    request =
      request
      |> Map.put(:campaign_lookup_executor, executor)
      |> Map.put(:local_context_metrics, %{request_size_limit_bytes: continuation_limit})

    assert {:error, :context_followup_too_large} =
             OpenAI.stream_response(request, store: context.store, http: http)

    assert_receive {:responses_request, 1, _}
    refute_receive {:responses_request, 2, _}
  end

  test "reports model catalog cache miss and hit using bounded labels", context do
    test_pid = self()
    _stage_handler_id = attach_turn_stage_handler()
    cache = start_supervised!({ModelCatalogCache, name: nil})
    http = provider_http(test_pid, completion_event("The scene continues."))

    request = %{
      instructions: "Return text.",
      input: [%{role: "user", content: "Continue."}]
    }

    for _ <- 1..2 do
      assert {:ok, %{text: "The scene continues."}} =
               OpenAI.stream_response(request,
                 store: context.store,
                 http: http,
                 model_catalog_cache: cache
               )
    end

    assert_receive {:models_request, _}
    assert_receive {:responses_request, _}
    assert_receive {:responses_request, _}

    assert_turn_stage(:oauth_access_token, :not_applicable)
    assert_turn_stage(:model_resolution, :miss)
    assert_turn_stage(:request_to_first_output, :not_applicable)
    assert_turn_stage(:provider_stream, :not_applicable)
    assert_turn_stage(:oauth_access_token, :not_applicable)
    assert_turn_stage(:model_resolution, :hit)
    assert_turn_stage(:request_to_first_output, :not_applicable)
    assert_turn_stage(:provider_stream, :not_applicable)
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

  test "lists only visible models with slugs that fit the automatic-model envelope", context do
    catalog = model_catalog()

    catalog =
      update_in(catalog["models"], fn models ->
        models ++
          [
            %{
              "slug" => String.duplicate("m", 256),
              "display_name" => "Too long",
              "visibility" => "list"
            }
          ]
      end)

    http = fn :get, "https://api.openai.com/v1/models", _options ->
      %{status: 200, body: Jason.encode!(catalog)}
    end

    assert {:ok, [%{slug: "fixture-model", display_name: "Fixture Model"}]} =
             OpenAI.models(store: context.store, http: http)
  end

  test "Automatic caches catalogs per OAuth subject, expires them, and leaves settings fresh",
       context do
    test_pid = self()

    cache =
      start_supervised!({Storyteller.GM.ModelCatalogCache, [name: nil, ttl_ms: 200]},
        id: make_ref()
      )

    other_store =
      fixture_account_store(context.credentials, "other-account-subject", "fixture-access-token")

    catalog_calls = :atomics.new(1, signed: false)

    http = fn method, url, options ->
      cond do
        method == :get and url == "https://api.openai.com/v1/models" ->
          call = :atomics.add_get(catalog_calls, 1, 1)
          send(test_pid, {:models_request, call})

          catalog =
            case call do
              2 ->
                %{
                  "models" => [
                    %{"slug" => "other-model", "display_name" => "Other", "visibility" => "list"}
                  ]
                }

              4 ->
                %{
                  "models" => [
                    %{"slug" => "fresh-model", "display_name" => "Fresh", "visibility" => "list"}
                  ]
                }

              _ ->
                model_catalog()
            end

          %{status: 200, body: Jason.encode!(catalog)}

        method == :post and url == "https://api.openai.com/v1/responses" ->
          send(test_pid, {:selected_model, Keyword.fetch!(options, :json)["model"]})
          %{status: 200, body: split_stream(completion_event("The scene continues."))}

        true ->
          {:error, :unexpected_request}
      end
    end

    request = %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]}

    assert {:ok, _response} =
             OpenAI.stream_response(request,
               store: context.store,
               http: http,
               model_catalog_cache: cache
             )

    assert_receive {:models_request, 1}
    assert_receive {:selected_model, "fixture-model"}

    assert {:ok, _response} =
             OpenAI.stream_response(request,
               store: context.store,
               http: http,
               model_catalog_cache: cache
             )

    assert_receive {:selected_model, "fixture-model"}
    refute_receive {:models_request, _}

    assert {:ok, _response} =
             OpenAI.stream_response(request,
               store: other_store,
               http: http,
               model_catalog_cache: cache
             )

    assert_receive {:models_request, 2}
    assert_receive {:selected_model, "other-model"}

    Process.sleep(230)

    assert {:ok, _response} =
             OpenAI.stream_response(request,
               store: context.store,
               http: http,
               model_catalog_cache: cache
             )

    assert_receive {:models_request, 3}
    assert_receive {:selected_model, "fixture-model"}

    # The account settings page and model-save validation use models/1, which
    # deliberately fetches a fresh catalog rather than consulting this cache.
    assert {:ok, [%{slug: "fresh-model"}]} =
             OpenAI.models(
               store: context.store,
               http: http
             )

    assert_receive {:models_request, 4}
    assert :atomics.get(catalog_calls, 1) == 4
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
         }), :provider_unavailable, true},
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
    error_cases = [
      {"subscription_sharing_invalid_user", :reauth_required},
      {"chatpass_v2_scope_not_authorized", :authorization_configuration},
      {"chatpass_v2_invalid_authorization_context", :authorization_configuration}
    ]

    Enum.with_index(error_cases)
    |> Enum.each(fn {{error_code, expected_error}, index} ->
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

      if index == 0,
        do: assert_receive({:models_request, _}),
        else: refute_receive({:models_request, _})

      assert_receive {:responses_request, _}
    end)
  end

  test "maps plan-sharing errors from asynchronous HTTP error bodies", context do
    error_cases = [
      {429, "subscription_sharing_usage_limit_exceeded", :usage_limit},
      {503, "subscription_sharing_usage_unavailable", :usage_unavailable},
      {503, "subscription_sharing_user_unavailable", :usage_unavailable},
      {503, "server_error", :provider_unavailable},
      {429, "rate_limit_exceeded", :provider_unavailable},
      {403, "subscription_sharing_user_not_eligible", :account_ineligible},
      {403, "policy_violation", :provider_error},
      {403, "subscription_sharing_route_not_supported", :unsupported_capability},
      {400, "subscription_sharing_unsupported_capability", :unsupported_capability}
    ]

    Enum.with_index(error_cases)
    |> Enum.each(fn {{status, code, expected}, index} ->
      body = Jason.encode!(%{"error" => %{"code" => code, "param" => "model"}})
      http = provider_http_error(self(), status, async_body(split_stream(body)))

      assert {:error, ^expected} =
               OpenAI.stream_response(
                 %{instructions: "Return text.", input: [%{role: "user", content: "Hello"}]},
                 store: context.store,
                 http: http
               )

      if index == 0,
        do: assert_receive({:models_request, _}),
        else: refute_receive({:models_request, _})

      assert_receive {:responses_request, _}
    end)
  end

  test "maps a model context-window rejection to a distinct retryable failure", context do
    body = Jason.encode!(%{"error" => %{"code" => "context_length_exceeded", "param" => "input"}})

    assert {:error, :context_length_exceeded} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "fixture-model"
               },
               store: context.store,
               http: provider_http_error(self(), 400, body)
             )

    assert_receive {:responses_request, _}
    refute_receive {:models_request, _}
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

  defp attach_turn_stage_handler do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler_id,
               TurnTelemetry.event(),
               fn event, measurements, metadata, _config ->
                 if self() == test_pid do
                   send(test_pid, {:turn_stage_event, event, measurements, metadata})
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    handler_id
  end

  defp assert_turn_stage(stage, cache) do
    assert_receive {:turn_stage_event, event, measurements, metadata}, 1_000
    assert event == TurnTelemetry.event()
    assert is_integer(measurements.duration) and measurements.duration >= 0
    assert measurements.success == 1
    assert measurements.failure == 0
    assert Map.keys(measurements) |> Enum.sort() == [:duration, :failure, :success]
    assert metadata == %{stage: stage, cache: cache}
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

  defp fixture_account_store(credentials, subject, access_token) do
    directory =
      Path.join(System.tmp_dir!(), "storyteller-openai-account-#{Ecto.UUID.generate()}")

    path = Path.join(directory, "credentials.json")
    on_exit(fn -> File.rm_rf(directory) end)
    store = start_supervised!({TokenStore, [path: path, name: nil]}, id: make_ref())

    account_credentials = %{
      credentials
      | subject: subject,
        email: credentials.email,
        host_id: TokenStore.host_id(store),
        access_token: access_token
    }

    assert :ok = TokenStore.put_credentials(account_credentials, store)
    store
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

  defp async_body_with_error(chunks, reason, delay_ms) do
    ref = make_ref()

    stream_fun = fn
      ^ref, {^ref, {:data, chunk}} ->
        {:ok, [data: chunk]}

      ^ref, {^ref, {:error, error}} ->
        if delay_ms > 0, do: Process.sleep(delay_ms)
        {:error, error}
    end

    Enum.each(chunks, fn chunk -> send(self(), {ref, {:data, chunk}}) end)
    send(self(), {ref, {:error, reason}})

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

  defp lookup_request do
    %{
      model: "fixture-model",
      instructions: "Use local campaign canon lookup only when necessary.",
      input: [
        %{"role" => "user", "content" => "Where is Mara?"},
        %{
          "type" => "additional_tools",
          "role" => "developer",
          "tools" => [CampaignLookup.tool_spec()]
        }
      ]
    }
  end

  defp function_call_completion(output_items, usage) do
    response = %{"output" => output_items}
    response = if is_map(usage), do: Map.put(response, "usage", usage), else: response
    event_frame("response.completed", %{"type" => "response.completed", "response" => response})
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
