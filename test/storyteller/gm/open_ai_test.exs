defmodule Storyteller.GM.OpenAITest do
  use ExUnit.Case, async: true

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
      input: [%{role: "user", content: [%{type: "input_text", text: "Resolve this action."}]}]
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
    assert Keyword.fetch!(options, :into) == :self
  end

  test "lists only models visible to the selected account", context do
    http = fn :get, "https://api.openai.com/v1/models", _options ->
      %{status: 200, body: Jason.encode!(model_catalog())}
    end

    assert {:ok, [%{slug: "fixture-model", display_name: "Fixture Model"}]} =
             OpenAI.models(store: context.store, http: http)
  end

  test "rejects a requested model that is absent from the current account catalog", context do
    test_pid = self()
    http = provider_http(test_pid, completion_event("unused"))

    assert {:error, :model_unavailable} =
             OpenAI.stream_response(
               %{
                 instructions: "Return text.",
                 input: [%{role: "user", content: "Hello"}],
                 model: "not-listed"
               },
               store: context.store,
               http: http
             )

    assert_receive {:models_request, _}
    refute_receive {:responses_request, _}
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

  test "maps plan-sharing errors from asynchronous HTTP error bodies", context do
    error_cases = [
      {429, "subscription_sharing_usage_limit_exceeded", :usage_limit},
      {503, "subscription_sharing_usage_unavailable", :usage_unavailable},
      {503, "subscription_sharing_user_unavailable", :usage_unavailable},
      {403, "subscription_sharing_user_not_eligible", :account_ineligible},
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

  defp completion_event(text) do
    "event: response.output_text.delta\ndata: " <>
      Jason.encode!(%{"type" => "response.output_text.delta", "delta" => text}) <>
      "\n\nevent: response.completed\ndata: " <>
      Jason.encode!(%{
        "type" => "response.completed",
        "response" => %{
          "output" => [
            %{
              "type" => "message",
              "content" => [%{"type" => "output_text", "text" => text}]
            }
          ]
        }
      }) <>
      "\n\n"
  end

  defp split_stream(stream) do
    midpoint = div(byte_size(stream), 2)
    <<first::binary-size(midpoint), second::binary>> = stream
    [first, second]
  end
end
