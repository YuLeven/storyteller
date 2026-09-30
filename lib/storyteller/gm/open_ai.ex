defmodule Storyteller.GM.OpenAI do
  @moduledoc """
  Calls the public Responses API with the selected ChatGPT-plan OAuth account.

  This adapter intentionally sends only `model`, `instructions`, and `input`,
  plus the preview-required `store: false` and `stream: true` fields. It does not
  persist provider-side conversation state and reports success only after the
  terminal `response.completed` event.
  """

  alias Storyteller.Auth.{HTTP, OAuth}

  @models_url "https://api.openai.com/v1/models"
  @responses_url "https://api.openai.com/v1/responses"
  @max_error_body_bytes 65_536

  @doc "Lists displayable models for the currently connected ChatGPT account."
  def models(opts \\ []) do
    with {:ok, access_token} <- OAuth.access_token(opts),
         {:ok, models} <- fetch_models(access_token, opts) do
      {:ok, models}
    end
  end

  @doc "Streams one Responses request and returns plain text after completion."
  def stream_response(request), do: stream_response(request, [])

  @doc false
  def stream_response(request, opts) when is_map(request) do
    with {:ok, access_token} <- OAuth.access_token(opts),
         {:ok, models} <- fetch_models(access_token, opts),
         {:ok, model} <- select_model(request, models),
         {:ok, body} <- request_body(request, model),
         {:ok, response} <- post_response(access_token, body, opts),
         :ok <- require_http_success(response),
         {:ok, text} <- completed_response(response_body(response)) do
      {:ok, %{text: text}}
    else
      {:error, reason} -> {:error, normalize_error(reason)}
      _ -> {:error, :provider_error}
    end
  rescue
    _ -> {:error, :provider_error}
  catch
    _, _ -> {:error, :provider_error}
  end

  def stream_response(_request, _opts), do: {:error, :invalid_response}

  defp fetch_models(access_token, opts) do
    http = http(opts)

    case HTTP.request(
           :get,
           @models_url,
           [headers: bearer_headers(access_token)],
           http
         ) do
      {:ok, response} ->
        with :ok <- require_http_success(response),
             {:ok, body} <- HTTP.decode_json(response_body(response)),
             %{"models" => entries} when is_list(entries) <- body do
          models =
            entries
            |> Enum.filter(&(is_map(&1) and &1["visibility"] == "list"))
            |> Enum.reduce([], fn entry, acc ->
              slug = entry["slug"]
              name = entry["display_name"]

              if is_binary(slug) and slug != "" do
                acc ++
                  [
                    %{
                      slug: slug,
                      display_name: if(is_binary(name) and name != "", do: name, else: slug)
                    }
                  ]
              else
                acc
              end
            end)

          if models == [], do: {:error, :model_unavailable}, else: {:ok, models}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, :invalid_response}
        end

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp select_model(request, models) do
    requested = field(request, :model)

    selected =
      case requested do
        model when is_binary(model) and model != "" -> Enum.find(models, &(&1.slug == model))
        nil -> List.first(models)
        _ -> nil
      end

    if selected, do: {:ok, selected.slug}, else: {:error, :model_unavailable}
  end

  defp request_body(request, model) do
    instructions = field(request, :instructions)
    input = field(request, :input)

    cond do
      not is_binary(instructions) or instructions == "" ->
        {:error, :invalid_response}

      not is_list(input) or input == [] ->
        {:error, :invalid_response}

      Enum.any?(input, &system_message?/1) ->
        {:error, :unsupported_capability}

      true ->
        {:ok,
         %{
           "model" => model,
           "instructions" => instructions,
           "input" => input,
           "store" => false,
           "stream" => true
         }}
    end
  end

  defp post_response(access_token, body, opts) do
    HTTP.request(
      :post,
      @responses_url,
      [
        headers: bearer_headers(access_token, "text/event-stream"),
        json: body,
        into: :self
      ],
      http(opts)
    )
  end

  defp require_http_success(response) do
    case response_status(response) do
      200 -> :ok
      401 -> {:error, :reauth_required}
      403 -> status_error(response, :account_ineligible)
      404 -> {:error, :model_unavailable}
      429 -> {:error, http_error_code(response_body(response))}
      status when status in [400, 503] -> status_error(response, :provider_error)
      status when is_integer(status) and status >= 500 -> {:error, :provider_error}
      status when is_integer(status) -> {:error, http_error_code(response_body(response))}
      _ -> {:error, :provider_error}
    end
  end

  defp status_error(response, fallback) do
    case http_error_code(response_body(response)) do
      :provider_error -> {:error, fallback}
      code -> {:error, code}
    end
  end

  defp completed_response(body) do
    case consume_sse(body) do
      {:completed, text} -> {:ok, text}
      {:failed, reason} -> {:error, reason}
      {:incomplete, :response_incomplete} -> {:error, :stream_incomplete}
      {:incomplete, :malformed} -> {:error, :invalid_response}
      :missing_completion -> {:error, :stream_incomplete}
    end
  end

  defp consume_sse(body) when is_binary(body), do: consume_chunks([body])

  defp consume_sse(body) do
    if Enumerable.impl_for(body), do: consume_chunks(body), else: {:incomplete, :malformed}
  end

  defp consume_chunks(chunks) do
    initial = {:ok, "", :waiting}

    result =
      Enum.reduce_while(chunks, initial, fn
        chunk, {:ok, buffer, status} when is_binary(chunk) ->
          {frames, rest} = split_frames(buffer <> chunk)

          case process_frames(frames, rest, status) do
            {:ok, next_buffer, next_status} -> {:cont, {:ok, next_buffer, next_status}}
            {:halt, terminal} -> {:halt, terminal}
          end

        _, _state ->
          {:halt, {:incomplete, :malformed}}
      end)

    case result do
      {:ok, buffer, status} ->
        final_status =
          if String.trim(buffer) == "" do
            status
          else
            process_frame(buffer, status)
          end

        case final_status do
          {:completed, _} = completed -> completed
          {:failed, _} = failed -> failed
          {:incomplete, _} = incomplete -> incomplete
          _ -> :missing_completion
        end

      terminal ->
        terminal
    end
  rescue
    _ -> {:incomplete, :malformed}
  catch
    _, _ -> {:incomplete, :malformed}
  end

  defp split_frames(buffer) do
    parts = String.split(buffer, ~r/\r\n\r\n|\n\n|\r\r/, trim: false)

    if length(parts) > 1 do
      {Enum.drop(parts, -1), List.last(parts)}
    else
      {[], buffer}
    end
  end

  defp process_frames(frames, buffer, status) do
    Enum.reduce_while(frames, {:ok, buffer, status}, fn frame, {:ok, rest, current} ->
      case process_frame(frame, current) do
        :waiting -> {:cont, {:ok, rest, :waiting}}
        terminal -> {:halt, {:halt, terminal}}
      end
    end)
  end

  defp process_frame(_frame, {:completed, _} = completed), do: completed
  defp process_frame(_frame, {:failed, _} = failed), do: failed
  defp process_frame(_frame, {:incomplete, _} = incomplete), do: incomplete

  defp process_frame(frame, _status) do
    {event, data} = parse_frame(frame)

    case data do
      nil ->
        :waiting

      "[DONE]" ->
        :waiting

      encoded ->
        case Jason.decode(encoded) do
          {:ok, payload} when is_map(payload) -> process_event(event, payload)
          _ -> {:incomplete, :malformed}
        end
    end
  end

  defp parse_frame(frame) do
    lines = String.split(frame, ~r/\r\n|\n|\r/, trim: false)

    event =
      lines
      |> Enum.find_value(fn line ->
        case line do
          "event:" <> value -> String.trim(value)
          _ -> nil
        end
      end)

    data =
      lines
      |> Enum.flat_map(fn
        "data:" <> value -> [String.trim_leading(value, " ")]
        _ -> []
      end)
      |> case do
        [] -> nil
        values -> Enum.join(values, "\n")
      end

    {event, data}
  end

  defp process_event(event, payload) do
    case payload["type"] || event do
      "response.completed" ->
        case output_text(payload["response"]) do
          {:ok, text} -> {:completed, text}
          _ -> {:incomplete, :malformed}
        end

      "response.failed" ->
        {:failed,
         error_code((payload["response"] && payload["response"]["error"]) || payload["error"])}

      "response.incomplete" ->
        {:incomplete, :response_incomplete}

      "error" ->
        {:failed, error_code(payload["error"] || payload)}

      _ ->
        :waiting
    end
  end

  defp output_text(%{"output" => output}) when is_list(output) do
    texts =
      Enum.flat_map(output, fn item ->
        case item do
          %{"content" => content} when is_list(content) ->
            Enum.flat_map(content, fn
              %{"type" => "output_text", "text" => text} when is_binary(text) -> [text]
              _ -> []
            end)

          _ ->
            []
        end
      end)

    if texts == [], do: {:error, :missing_text}, else: {:ok, Enum.join(texts)}
  end

  defp output_text(_), do: {:error, :missing_output}

  defp error_code(%{"code" => code}) when is_binary(code), do: map_error_code(code)
  defp error_code(%{code: code}) when is_binary(code), do: map_error_code(code)
  defp error_code(_), do: :provider_error

  defp http_error_code(body) do
    case decode_error_body(body) do
      {:ok, %{"error" => error}} -> error_code(error)
      {:ok, %{"code" => code}} when is_binary(code) -> map_error_code(code)
      _ -> :provider_error
    end
  end

  defp decode_error_body(body) when is_binary(body), do: HTTP.decode_json(body)
  defp decode_error_body(%_{} = body), do: decode_streamed_error_body(body)
  defp decode_error_body(body) when is_map(body), do: HTTP.decode_json(body)
  defp decode_error_body(body), do: decode_streamed_error_body(body)

  defp decode_streamed_error_body(body) do
    if Enumerable.impl_for(body) do
      body
      |> Enum.reduce_while({:ok, [], 0}, fn
        chunk, {:ok, chunks, size}
        when is_binary(chunk) and size + byte_size(chunk) <= @max_error_body_bytes ->
          {:cont, {:ok, [chunk | chunks], size + byte_size(chunk)}}

        _chunk, {:ok, _chunks, _size} ->
          {:halt, :too_large}
      end)
      |> case do
        {:ok, chunks, _size} ->
          chunks |> Enum.reverse() |> IO.iodata_to_binary() |> HTTP.decode_json()

        _ ->
          {:error, :invalid_response}
      end
    else
      {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :invalid_response}
  catch
    _, _ -> {:error, :invalid_response}
  end

  defp map_error_code(code)
       when code in ["subscription_sharing_usage_limit_exceeded", "usage_limit_exceeded"],
       do: :usage_limit

  defp map_error_code(code)
       when code in ["subscription_sharing_usage_unavailable", "usage_unavailable"],
       do: :usage_unavailable

  defp map_error_code(code)
       when code in ["subscription_sharing_user_unavailable"],
       do: :usage_unavailable

  defp map_error_code(code)
       when code in ["subscription_sharing_user_not_eligible"],
       do: :account_ineligible

  defp map_error_code(code)
       when code in [
              "subscription_sharing_unsupported_capability",
              "subscription_sharing_route_not_supported"
            ],
       do: :unsupported_capability

  defp map_error_code(code)
       when code in ["invalid_api_key", "invalid_token", "token_expired", "authentication_error"],
       do: :reauth_required

  defp map_error_code(code)
       when code in ["model_not_found", "model_unavailable", "invalid_model"],
       do: :model_unavailable

  defp map_error_code(_), do: :provider_error

  defp normalize_error(:network_error), do: :timeout
  defp normalize_error(:timeout), do: :timeout
  defp normalize_error(:temporary_auth_error), do: :provider_error
  defp normalize_error(:not_authenticated), do: :account_ineligible
  defp normalize_error(:plan_usage_not_authorized), do: :account_ineligible
  defp normalize_error(reason), do: reason

  defp system_message?(%{} = item) do
    role = field(item, :role)
    role == "system"
  end

  defp system_message?(_), do: false

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_map, _key), do: nil

  defp bearer_headers(access_token, accept \\ "application/json") do
    [{"authorization", "Bearer " <> access_token}, {"accept", accept}]
  end

  defp http(opts) do
    config = Application.get_env(:storyteller, Storyteller.Auth.OAuth, [])
    Keyword.get(opts, :http, Keyword.get(config, :http))
  end

  defp response_status(%{status: status}) when is_integer(status), do: status
  defp response_status(%{"status" => status}) when is_integer(status), do: status
  defp response_status(_), do: nil

  defp response_body(%{body: body}), do: body
  defp response_body(%{"body" => body}), do: body
  defp response_body(_), do: nil
end
