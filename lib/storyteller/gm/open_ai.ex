defmodule Storyteller.GM.OpenAI do
  require Logger

  @moduledoc """
  Calls the public Responses API with the selected ChatGPT-plan OAuth account.

  This adapter intentionally sends only `model`, `instructions`, and `input`,
  plus the preview-required `store: false` and `stream: true` fields. It does not
  persist provider-side conversation state and reports success only after the
  terminal `response.completed` event.
  """

  alias Storyteller.Auth.{HTTP, OAuth}
  alias Storyteller.GM.ModelCatalogCache

  @models_url "https://api.openai.com/v1/models"
  @responses_url "https://api.openai.com/v1/responses"
  @response_stream_receive_timeout 90_000
  @max_error_body_bytes 65_536
  @max_output_text_bytes 100_000

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
    started_at = System.monotonic_time()

    with {:ok, access_token, account_subject} <-
           log_stage_error(:oauth, OAuth.access_token_with_subject(opts)),
         {:ok, model} <- resolve_model(request, access_token, account_subject, opts),
         {:ok, body} <- log_stage_error(:request_validation, request_body(request, model)),
         {:ok, response} <-
           log_stage_error(:responses_request, post_response(access_token, body, opts)),
         :ok <- require_http_success(response, :responses),
         {:ok, result} <-
           completed_response(
             response,
             local_callback(request, :on_first_output),
             local_callback(request, :on_stream_activity),
             started_at
           ) do
      {:ok, result}
    else
      {:error, reason} -> {:error, normalize_error(reason)}
      _ -> {:error, :provider_error}
    end
  rescue
    error ->
      Logger.warning(
        "ChatGPT plan inference failed phase=adapter_exception exception=#{inspect(error.__struct__)}"
      )

      {:error, :provider_error}
  catch
    kind, _reason ->
      Logger.warning("ChatGPT plan inference failed phase=adapter_throw kind=#{kind}")
      {:error, :provider_error}
  end

  def stream_response(_request, _opts), do: {:error, :invalid_response}

  defp resolve_model(request, access_token, account_subject, opts) do
    case field(request, :model) do
      model when is_binary(model) and model != "" ->
        {:ok, model}

      nil ->
        with {:ok, models} <-
               log_stage_error(
                 :model_catalog,
                 cached_models(account_subject, access_token, opts)
               ) do
          log_stage_error(:model_selection, select_model(request, models))
        end

      _ ->
        log_stage_error(:model_selection, {:error, :model_unavailable})
    end
  end

  defp cached_models(subject, access_token, opts) do
    cache = Keyword.get(opts, :model_catalog_cache, ModelCatalogCache)

    case cache_get(cache, subject) do
      {:ok, models} ->
        {:ok, models}

      :miss ->
        with {:ok, models} <- fetch_models(access_token, opts) do
          cache_put(cache, subject, models)
          {:ok, models}
        end
    end
  end

  defp cache_get(cache, subject) do
    ModelCatalogCache.get(subject, cache)
  catch
    :exit, _reason -> :miss
  end

  defp cache_put(cache, subject, models) do
    ModelCatalogCache.put(subject, models, cache)
  catch
    :exit, _reason -> :ok
  end

  defp fetch_models(access_token, opts) do
    http = http(opts)

    case HTTP.request(
           :get,
           @models_url,
           [headers: bearer_headers(access_token)],
           http
         ) do
      {:ok, response} ->
        with :ok <- require_http_success(response, :model_catalog),
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
        into: :self,
        receive_timeout: @response_stream_receive_timeout
      ],
      http(opts)
    )
  end

  defp require_http_success(response, phase) do
    status = response_status(response)

    if status == 200 do
      :ok
    else
      details = http_error_details(response_body(response))
      log_provider_failure(phase, status, details, request_id(response))
      {:error, error_for_status(status, details.reason)}
    end
  end

  defp error_for_status(401, _reason), do: :reauth_required
  defp error_for_status(403, :provider_error), do: :provider_error
  defp error_for_status(404, _reason), do: :model_unavailable
  defp error_for_status(429, reason), do: reason
  defp error_for_status(status, reason) when status in [400, 503], do: reason

  defp error_for_status(status, _reason) when is_integer(status) and status >= 500,
    do: :provider_error

  defp error_for_status(_status, reason), do: reason

  defp completed_response(response, on_first_output, on_stream_activity, started_at) do
    case consume_sse(response_body(response), on_first_output, on_stream_activity, started_at) do
      {:completed, text, usage} ->
        result = %{text: text}
        result = if map_size(usage) > 0, do: Map.put(result, :usage, usage), else: result
        {:ok, result}

      {:failed, details} ->
        log_provider_failure(
          :response_stream,
          response_status(response),
          details,
          request_id(response)
        )

        {:error, details.reason}

      {:incomplete, :response_incomplete} ->
        details = stream_diagnostic(:response_incomplete)

        log_provider_failure(
          :response_stream,
          response_status(response),
          details,
          request_id(response)
        )

        {:error, :stream_incomplete}

      {:incomplete, diagnostic} ->
        details = stream_diagnostic(diagnostic)

        log_provider_failure(
          :response_stream,
          response_status(response),
          details,
          request_id(response)
        )

        failure =
          if diagnostic == :response_incomplete, do: :stream_incomplete, else: :invalid_response

        {:error, failure}

      :missing_completion ->
        details = stream_diagnostic(:missing_completion)

        log_provider_failure(
          :response_stream,
          response_status(response),
          details,
          request_id(response)
        )

        {:error, :stream_incomplete}
    end
  end

  defp consume_sse(body, on_first_output, on_stream_activity, started_at)
       when is_binary(body),
       do: consume_chunks([body], on_first_output, on_stream_activity, started_at)

  defp consume_sse(body, on_first_output, on_stream_activity, started_at) do
    if Enumerable.impl_for(body),
      do: consume_chunks(body, on_first_output, on_stream_activity, started_at),
      else: {:incomplete, :malformed}
  end

  defp consume_chunks(chunks, on_first_output, on_stream_activity, started_at) do
    initial = {:ok, "", {:waiting, [], 0, false}}

    result =
      Enum.reduce_while(chunks, initial, fn
        chunk, {:ok, buffer, {:waiting, _deltas, _size, _first_output?} = status}
        when is_binary(chunk) ->
          safely_call(on_stream_activity)
          {frames, rest} = split_frames(buffer <> chunk)

          case process_frames(frames, rest, status, on_first_output, started_at) do
            {:ok, next_buffer, next_status} -> {:cont, {:ok, next_buffer, next_status}}
            {:halt, terminal} -> {:halt, terminal}
          end

        _, _state ->
          {:halt, {:incomplete, :non_binary_chunk}}
      end)

    case result do
      {:ok, buffer, {:waiting, _deltas, _size, _first_output?} = status} ->
        final_status =
          if String.trim(buffer) == "" do
            status
          else
            process_frame(buffer, status, on_first_output, started_at)
          end

        case final_status do
          {:completed, _, _} = completed -> completed
          {:failed, _} = failed -> failed
          {:incomplete, _} = incomplete -> incomplete
          _ -> :missing_completion
        end

      terminal ->
        terminal
    end
  rescue
    error -> {:incomplete, {:stream_read_exception, error.__struct__}}
  catch
    kind, _reason -> {:incomplete, {:stream_read_throw, kind}}
  end

  defp split_frames(buffer) do
    parts = String.split(buffer, ~r/\r\n\r\n|\n\n|\r\r/, trim: false)

    if length(parts) > 1 do
      {Enum.drop(parts, -1), List.last(parts)}
    else
      {[], buffer}
    end
  end

  defp process_frames(frames, buffer, status, on_first_output, started_at) do
    Enum.reduce_while(frames, {:ok, buffer, status}, fn frame, {:ok, rest, current} ->
      case process_frame(frame, current, on_first_output, started_at) do
        {:waiting, _deltas, _size, _first_output?} = waiting ->
          {:cont, {:ok, rest, waiting}}

        terminal ->
          {:halt, {:halt, terminal}}
      end
    end)
  end

  defp process_frame(_frame, {:completed, _, _} = completed, _callback, _started_at),
    do: completed

  defp process_frame(_frame, {:failed, _} = failed, _callback, _started_at), do: failed

  defp process_frame(_frame, {:incomplete, _} = incomplete, _callback, _started_at),
    do: incomplete

  defp process_frame(frame, {:waiting, deltas, size, first_output?}, on_first_output, started_at) do
    {event, data} = parse_frame(frame)

    case data do
      nil ->
        {:waiting, deltas, size, first_output?}

      "[DONE]" ->
        {:waiting, deltas, size, first_output?}

      encoded ->
        case Jason.decode(encoded) do
          {:ok, payload} when is_map(payload) ->
            process_event(
              event,
              payload,
              deltas,
              size,
              first_output?,
              on_first_output,
              started_at
            )

          _ ->
            {:incomplete, :invalid_sse_json}
        end
    end
  end

  defp process_frame(frame, _status, on_first_output, started_at) do
    {event, data} = parse_frame(frame)

    case data do
      nil ->
        {:waiting, [], 0, false}

      "[DONE]" ->
        {:waiting, [], 0, false}

      encoded ->
        case Jason.decode(encoded) do
          {:ok, payload} when is_map(payload) ->
            process_event(
              event,
              payload,
              [],
              0,
              false,
              on_first_output,
              started_at
            )

          _ ->
            {:incomplete, :invalid_sse_json}
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

  defp process_event(event, payload, deltas, size, first_output?, on_first_output, started_at) do
    case payload["type"] || event do
      "response.completed" ->
        usage = response_usage(payload["response"])

        case output_text(payload["response"]) do
          {:ok, text} ->
            {:completed, text, usage}

          _ when size > 0 ->
            {:completed, deltas |> Enum.reverse() |> IO.iodata_to_binary(), usage}

          _ ->
            {:incomplete, :completed_without_text}
        end

      "response.output_text.delta" ->
        delta = payload["delta"]

        first_output? =
          if not first_output? and is_binary(delta) and delta != "" do
            notify_first_output(on_first_output, started_at)
            true
          else
            first_output?
          end

        case append_output_delta(deltas, size, delta) do
          {:waiting, next_deltas, next_size} ->
            {:waiting, next_deltas, next_size, first_output?}

          terminal ->
            terminal
        end

      "response.failed" ->
        {:failed,
         response_error_details(
           (payload["response"] && payload["response"]["error"]) || payload["error"]
         )}

      "response.incomplete" ->
        {:incomplete, :response_incomplete}

      "error" ->
        {:failed, response_error_details(payload["error"] || payload)}

      _ ->
        {:waiting, deltas, size, first_output?}
    end
  end

  defp notify_first_output(on_first_output, started_at) do
    duration = System.monotonic_time() - started_at

    emit_first_text_delta_latency(duration)
    safely_call(on_first_output)
  end

  defp safely_call(callback) when is_function(callback, 0) do
    try do
      callback.()
    rescue
      _error -> :ok
    catch
      _kind, _reason -> :ok
    end
  end

  defp safely_call(_callback), do: :ok

  defp emit_first_text_delta_latency(duration) when is_integer(duration) and duration >= 0 do
    :telemetry.execute(
      [:storyteller, :gm, :provider, :first_text_delta, :stop],
      %{duration: duration},
      %{}
    )

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp emit_first_text_delta_latency(_duration), do: :ok

  defp append_output_delta(deltas, size, delta) when is_binary(delta) do
    if size + byte_size(delta) <= @max_output_text_bytes do
      {:waiting, [delta | deltas], size + byte_size(delta)}
    else
      {:incomplete, :output_too_large}
    end
  end

  defp append_output_delta(deltas, size, _delta), do: {:waiting, deltas, size}

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

  defp response_usage(%{"usage" => usage}) when is_map(usage) do
    [:input_tokens, :output_tokens]
    |> Enum.reduce(%{}, fn key, acc ->
      case usage[Atom.to_string(key)] do
        count when is_integer(count) and count >= 0 -> Map.put(acc, key, count)
        _ -> acc
      end
    end)
  end

  defp response_usage(_response), do: %{}

  defp http_error_details(body) do
    case decode_error_body(body) do
      {:ok, %{"error" => error}} when is_map(error) ->
        diagnostic_details(error, :error)

      {:ok, %{"code" => code} = details} when is_binary(code) ->
        diagnostic_details(details, :code)

      {:ok, %{"detail" => _detail}} ->
        empty_diagnostic(:detail)

      {:ok, _body} ->
        empty_diagnostic(:json)

      {:error, _reason} ->
        empty_diagnostic(:invalid_json)
    end
  end

  defp response_error_details(error) when is_map(error),
    do: diagnostic_details(error, :stream_error)

  defp response_error_details(_error), do: empty_diagnostic(:stream_error)

  defp diagnostic_details(details, shape) do
    code = field(details, :code)
    param = field(details, :param)

    %{
      reason: if(is_binary(code), do: map_error_code(code), else: :provider_error),
      code: safe_diagnostic_value(code),
      param: safe_diagnostic_value(param),
      shape: shape
    }
  end

  defp empty_diagnostic(shape),
    do: %{reason: :provider_error, code: nil, param: nil, shape: shape}

  defp stream_diagnostic({shape, exception}) when is_atom(shape) and is_atom(exception),
    do: empty_diagnostic("#{shape}_#{inspect(exception)}")

  defp stream_diagnostic(shape) when is_atom(shape), do: empty_diagnostic(shape)
  defp stream_diagnostic(_shape), do: empty_diagnostic(:invalid_stream)

  defp log_provider_failure(phase, status, details, request_id) do
    Logger.warning(
      "ChatGPT plan inference failed phase=#{phase} status=#{format_status(status)} " <>
        "shape=#{details.shape} code=#{details.code || "none"} " <>
        "param=#{details.param || "none"} request_id=#{request_id || "none"}"
    )
  end

  defp log_stage_error(phase, {:error, reason} = result) do
    Logger.warning(
      "ChatGPT plan inference failed phase=#{phase} reason=#{diagnostic_reason(reason)}"
    )

    result
  end

  defp log_stage_error(_phase, result), do: result

  defp diagnostic_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp diagnostic_reason(_reason), do: "unknown"

  defp format_status(status) when is_integer(status), do: Integer.to_string(status)
  defp format_status(_status), do: "unknown"

  defp safe_diagnostic_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_.\/:\-]/, "_")
    |> String.slice(0, 128)
  end

  defp safe_diagnostic_value(_value), do: nil

  defp request_id(response) do
    headers = response_headers(response)

    (header_value(headers, "x-request-id") || header_value(headers, "x-openai-request-id"))
    |> case do
      [value | _] -> safe_diagnostic_value(value)
      value when is_binary(value) -> safe_diagnostic_value(value)
      _ -> nil
    end
  end

  defp response_headers(%{headers: headers}), do: headers
  defp response_headers(%{"headers" => headers}), do: headers
  defp response_headers(_response), do: nil

  defp header_value(headers, name) when is_map(headers) do
    Map.get(headers, name)
  end

  defp header_value(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) -> if String.downcase(key) == name, do: value
      {key, value} when is_atom(key) -> if Atom.to_string(key) == name, do: value
      _ -> nil
    end)
  end

  defp header_value(_headers, _name), do: nil

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
       when code in ["subscription_sharing_invalid_user"],
       do: :reauth_required

  defp map_error_code(code)
       when code in [
              "chatpass_v2_scope_not_authorized",
              "chatpass_v2_invalid_authorization_context"
            ],
       do: :authorization_configuration

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

  defp local_callback(request, key) do
    case field(request, key) do
      callback when is_function(callback, 0) -> callback
      _ -> nil
    end
  end

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
