defmodule Storyteller.GM.OpenAI do
  require Logger

  @moduledoc """
  Calls the public Responses API with the selected ChatGPT-plan OAuth account.

  The request includes `model`, `instructions`, and `input`, plus the
  preview-required `store: false` and `stream: true` fields. Recognized reasoning
  models also receive low reasoning effort. It does not persist provider-side
  conversation state and reports success only after the terminal
  `response.completed` event.
  """

  alias Storyteller.Auth.{HTTP, OAuth}
  alias Storyteller.GM.{ModelCatalogCache, RequestEnvelope, TurnTelemetry}

  @models_url "https://api.openai.com/v1/models"
  @responses_url "https://api.openai.com/v1/responses"
  @response_stream_receive_timeout 90_000
  @max_error_body_bytes 65_536
  @max_output_text_bytes 100_000
  @max_narration_preview_chars 3_000
  @max_preview_source_bytes 20_000
  # Scan and forward streamed drafts in meaningful increments, rather than
  # reparsing the whole JSON prefix and re-rendering on every tiny token delta.
  @narration_preview_min_source_growth_bytes 32
  @campaign_lookup_tool_name "lookup_campaign_canon"
  @max_tool_argument_bytes 6_000
  @max_tool_output_bytes 6_000
  @max_tool_completion_output_bytes 16_000
  @max_tool_call_id_bytes 256
  @max_tool_calls_per_response 4
  @max_tool_calls_per_turn 8
  @safe_error_types ~w(
    authentication_error
    invalid_request_error
    permission_error
    rate_limit_error
    server_error
  )

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
    access_token_result =
      timed_stage(:oauth_access_token, fn ->
        log_stage_error(:oauth, OAuth.access_token_with_subject(opts))
      end)

    with {:ok, access_token, account_subject} <-
           access_token_result,
         {:ok, model} <- timed_model_resolution(request, access_token, account_subject, opts),
         {:ok, body} <- log_stage_error(:request_validation, request_body(request, model)),
         {:ok, result} <- request_and_stream_response(access_token, body, request, opts) do
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
        {:ok, model, :not_used}

      nil ->
        case cached_models(account_subject, access_token, opts) do
          {:ok, models, cache_status} ->
            case log_stage_error(:model_selection, select_model(request, models)) do
              {:ok, model} -> {:ok, model, cache_status}
              {:error, reason} -> {:error, reason, cache_status}
            end

          {:error, reason, cache_status} ->
            {:error, reason, cache_status}
        end

      _ ->
        {:error, :model_unavailable, :not_used}
    end
  end

  defp timed_model_resolution(request, access_token, account_subject, opts) do
    started_at = System.monotonic_time()

    result = resolve_model(request, access_token, account_subject, opts)

    case result do
      {:ok, model, cache_status} ->
        TurnTelemetry.stop(:model_resolution, started_at, :ok, cache_status)
        {:ok, model}

      {:error, reason, cache_status} ->
        TurnTelemetry.stop(:model_resolution, started_at, :error, cache_status)
        {:error, reason}
    end
  end

  defp timed_stage(stage, fun) do
    started_at = System.monotonic_time()
    result = fun.()

    outcome =
      if is_tuple(result) and tuple_size(result) > 0 and elem(result, 0) == :ok,
        do: :ok,
        else: :error

    TurnTelemetry.stop(stage, started_at, outcome)
    result
  end

  defp request_and_stream_response(access_token, body, request, opts) do
    started_at = System.monotonic_time()

    first_output = one_shot_callback(local_callback(request, :on_first_output))
    narration_preview = local_callback(request, :on_narration_preview, 1)
    safely_call(local_callback(request, :on_stream_start))

    result =
      run_response_turn(
        access_token,
        body,
        request,
        opts,
        started_at,
        first_output,
        narration_preview,
        0,
        %{}
      )

    if match?({:error, _}, result), do: safely_call(local_callback(request, :on_stream_error))

    outcome = if match?({:ok, _}, result), do: :ok, else: :error
    TurnTelemetry.stop(:provider_stream, started_at, outcome)
    result
  end

  defp cached_models(subject, access_token, opts) do
    cache = Keyword.get(opts, :model_catalog_cache, ModelCatalogCache)

    case cache_get(cache, subject) do
      {:ok, models} ->
        {:ok, models, :hit}

      :miss ->
        case log_stage_error(:model_catalog, fetch_models(access_token, opts)) do
          {:ok, models} ->
            cache_put(cache, subject, models)
            {:ok, models, :miss}

          {:error, reason} ->
            {:error, reason, :miss}
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

              if is_binary(slug) and slug != "" and
                   byte_size(slug) <= RequestEnvelope.maximum_model_slug_bytes() do
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
        body = RequestEnvelope.body(model, instructions, input)

        with :ok <- validate_advertised_tools(input),
             {:ok, limit} <- request_size_limit(request),
             :ok <- enforce_body_size(body, limit) do
          {:ok, body}
        end
    end
  end

  defp run_response_turn(
         access_token,
         body,
         request,
         opts,
         started_at,
         first_output,
         narration_preview,
         tool_calls_used,
         usage
       ) do
    stream_receive_timeout = response_stream_receive_timeout(opts)

    with {:ok, response} <-
           log_stage_error(
             :responses_request,
             post_response(access_token, body, opts, stream_receive_timeout)
           ),
         :ok <- require_http_success(response, :responses, body),
         {:ok, completed} <-
           completed_response(
             response,
             first_output,
             narration_preview,
             local_callback(request, :on_stream_activity),
             started_at,
             stream_receive_timeout
           ) do
      usage = add_usage(usage, completed.usage)

      case function_calls(completed.response) do
        [] ->
          {:ok, public_result(completed.text, usage)}

        calls
        when length(calls) <= @max_tool_calls_per_response and
               tool_calls_used + length(calls) <= @max_tool_calls_per_turn ->
          with :ok <-
                 log_stage_error(
                   :tool_completion_validation,
                   validate_tool_completion_output(completed.response)
                 ),
               {:ok, calls_with_arguments} <-
                 log_stage_error(
                   :tool_call_validation,
                   validate_tool_calls(calls, body["input"], request, tool_calls_used)
                 ),
               {:ok, outputs} <- execute_tool_calls(calls_with_arguments, request),
               continuation <- continuation_body(body, completed.response, outputs),
               :ok <- enforce_followup_body_size(continuation, request_size_limit!(request)) do
            run_response_turn(
              access_token,
              continuation,
              request,
              opts,
              started_at,
              first_output,
              narration_preview,
              tool_calls_used + length(calls),
              usage
            )
          end

        _multiple_or_repeated_calls ->
          {:error, :unsupported_capability}
      end
    end
  end

  defp public_result(text, usage) do
    result = %{text: text}
    if map_size(usage) > 0, do: Map.put(result, :usage, usage), else: result
  end

  defp completed_response(
         response,
         on_first_output,
         on_narration_preview,
         on_stream_activity,
         started_at,
         stream_receive_timeout
       ) do
    {last_stream_activity, on_stream_activity} = track_stream_activity(on_stream_activity)

    try do
      case consume_sse(
             response_body(response),
             on_first_output,
             on_narration_preview,
             on_stream_activity,
             started_at
           ) do
        {:completed, text, usage, completed_response} ->
          if (is_binary(text) and text != "") or function_calls(completed_response) != [] do
            {:ok, %{text: text || "", usage: usage, response: completed_response}}
          else
            log_completed_response_failure(response, :completed_without_text)
          end

        {:failed, details} ->
          log_provider_failure(
            :response_stream,
            response_status(response),
            details,
            request_id(response)
          )

          {:error, details.reason}

        {:incomplete, :response_incomplete} ->
          log_completed_response_failure(response, :response_incomplete, :stream_incomplete)

        {:incomplete, diagnostic} ->
          failure =
            if diagnostic == :response_incomplete, do: :stream_incomplete, else: :invalid_response

          log_completed_response_failure(response, diagnostic, failure)

        {:transport_error, %Req.TransportError{reason: :timeout}} ->
          failure =
            HTTP.classify_stream_timeout(
              :atomics.get(last_stream_activity, 1),
              stream_receive_timeout
            )

          log_stream_transport_failure(response, failure, :transport_timeout)
          {:error, failure}

        {:transport_error, %Req.TransportError{}} ->
          log_stream_transport_failure(response, :network_error, :transport_error)
          {:error, :network_error}

        :missing_completion ->
          log_completed_response_failure(response, :missing_completion, :stream_incomplete)
      end
    rescue
      error in Req.TransportError ->
        case error.reason do
          :timeout ->
            failure =
              HTTP.classify_stream_timeout(
                :atomics.get(last_stream_activity, 1),
                stream_receive_timeout
              )

            log_stream_transport_failure(response, failure, :transport_timeout)
            {:error, failure}

          _reason ->
            log_stream_transport_failure(response, :network_error, :transport_error)
            {:error, :network_error}
        end
    end
  end

  defp log_stream_transport_failure(response, failure, shape) do
    log_provider_failure(
      :response_stream,
      response_status(response),
      %{reason: failure, code: nil, param: nil, shape: shape},
      request_id(response)
    )
  end

  defp log_completed_response_failure(response, diagnostic, failure \\ :invalid_response) do
    details = stream_diagnostic(diagnostic)

    log_provider_failure(
      :response_stream,
      response_status(response),
      details,
      request_id(response)
    )

    {:error, failure}
  end

  defp validate_advertised_tools(input) do
    specs = advertised_tool_specs(input)
    names = Enum.map(specs, &field(&1, :name))

    cond do
      length(specs) > 50 ->
        {:error, :unsupported_capability}

      Enum.any?(
        specs,
        &(not is_map(&1) or field(&1, :type) != "function" or
            not is_binary(field(&1, :name)) or field(&1, :name) == "")
      ) ->
        {:error, :unsupported_capability}

      length(names) != length(Enum.uniq(names)) ->
        {:error, :unsupported_capability}

      true ->
        :ok
    end
  end

  defp advertised_tool_specs(input) when is_list(input) do
    Enum.flat_map(input, fn item ->
      if is_map(item) and field(item, :type) == "additional_tools" and
           field(item, :role) == "developer" do
        case field(item, :tools) do
          tools when is_list(tools) -> tools
          tool when is_map(tool) -> [tool]
          _ -> []
        end
      else
        []
      end
    end)
  end

  defp advertised_tool_specs(_), do: []

  defp function_calls(response) when is_map(response) do
    case field(response, :output) do
      output when is_list(output) ->
        Enum.filter(output, &(is_map(&1) and field(&1, :type) == "function_call"))

      _ ->
        []
    end
  end

  defp function_calls(_), do: []

  defp validate_tool_completion_output(response) do
    output = field(response, :output)

    with true <- is_list(output),
         {:ok, encoded} <- Jason.encode(output),
         true <- byte_size(encoded) <= @max_tool_completion_output_bytes do
      :ok
    else
      _ -> {:error, :provider_error}
    end
  rescue
    _error -> {:error, :provider_error}
  end

  defp validate_tool_calls(calls, input, request, calls_already_used) do
    Enum.reduce_while(calls, {:ok, [], MapSet.new(), MapSet.new()}, fn call,
                                                                       {:ok, acc, seen_ids,
                                                                        seen_names} ->
      case validate_tool_call(call, input, request) do
        {:ok, call_id, name, arguments} ->
          cond do
            name == @campaign_lookup_tool_name and calls_already_used > 0 ->
              {:halt, {:error, :unsupported_capability}}

            MapSet.member?(seen_ids, call_id) ->
              {:halt, {:error, :invalid_response}}

            name == @campaign_lookup_tool_name and MapSet.member?(seen_names, name) ->
              {:halt, {:error, :unsupported_capability}}

            true ->
              {:cont,
               {:ok, acc ++ [{call_id, name, arguments}], MapSet.put(seen_ids, call_id),
                MapSet.put(seen_names, name)}}
          end

        _ ->
          {:halt, {:error, :invalid_response}}
      end
    end)
    |> case do
      {:ok, validated, _seen_ids, _seen_names} -> {:ok, validated}
      error -> error
    end
  end

  defp validate_tool_call(call, input, request) when is_map(call) do
    call_id = field(call, :call_id)
    name = field(call, :name)
    arguments = field(call, :arguments)
    advertised? = Enum.count(advertised_tool_specs(input), &(field(&1, :name) == name)) == 1

    with true <- is_binary(name) and advertised? and executable_tool?(request, name),
         true <- is_binary(call_id) and byte_size(call_id) in 1..@max_tool_call_id_bytes,
         {:ok, decoded} <- decode_tool_arguments(arguments),
         true <- is_map(decoded),
         {:ok, encoded} <- Jason.encode(decoded),
         true <- byte_size(encoded) <= @max_tool_argument_bytes do
      {:ok, call_id, name, decoded}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp validate_tool_call(_, _, _), do: {:error, :invalid_response}

  defp decode_tool_arguments(arguments) when is_binary(arguments) do
    if byte_size(arguments) <= @max_tool_argument_bytes do
      Jason.decode(arguments)
    else
      {:error, :arguments_too_large}
    end
  end

  defp decode_tool_arguments(arguments) when is_map(arguments), do: {:ok, arguments}
  defp decode_tool_arguments(_), do: {:error, :invalid_arguments}

  defp executable_tool?(request, @campaign_lookup_tool_name),
    do: is_function(field(request, :campaign_lookup_executor), 1)

  defp executable_tool?(request, name) do
    case field(request, :mcp_tool_executors) do
      executors when is_map(executors) -> is_function(Map.get(executors, name), 1)
      _ -> false
    end
  end

  defp execute_tool_calls(calls, request) do
    Enum.reduce_while(calls, {:ok, []}, fn {call_id, name, arguments}, {:ok, outputs} ->
      with {:ok, output} <-
             log_stage_error(:tool_execution, execute_tool(request, name, arguments)),
           {:ok, encoded_output} <-
             log_stage_error(:tool_result_validation, encode_tool_output(output)) do
        {:cont, {:ok, outputs ++ [{call_id, encoded_output}]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_tool(request, @campaign_lookup_tool_name, arguments) do
    safe_execute(field(request, :campaign_lookup_executor), arguments)
  end

  defp execute_tool(request, name, arguments) do
    case field(request, :mcp_tool_executors) do
      executors when is_map(executors) ->
        safe_execute(Map.get(executors, name), arguments)

      _ ->
        {:error, :unsupported_capability}
    end
  end

  defp safe_execute(executor, arguments) when is_function(executor, 1) do
    case executor.(arguments) do
      {:ok, output} -> {:ok, output}
      other -> {:ok, other}
    end
  rescue
    _error -> {:error, :invalid_response}
  catch
    _kind, _reason -> {:error, :invalid_response}
  end

  defp safe_execute(_, _), do: {:error, :unsupported_capability}

  defp encode_tool_output(output) do
    case Jason.encode(output) do
      {:ok, encoded} ->
        if byte_size(Jason.encode!(%{"output" => encoded})) <= @max_tool_output_bytes do
          {:ok, encoded}
        else
          {:error, :invalid_response}
        end

      {:error, _not_json_safe} ->
        {:error, :invalid_response}
    end
  rescue
    _error -> {:error, :invalid_response}
  end

  defp continuation_body(body, completed_response, outputs) do
    response_output = field(completed_response, :output)

    tool_outputs =
      Enum.map(outputs, fn {call_id, encoded_output} ->
        %{
          "type" => "function_call_output",
          "call_id" => call_id,
          "output" => encoded_output
        }
      end)

    %{
      body
      | "input" =>
          body["input"] ++
            response_output ++
            tool_outputs
    }
  end

  defp request_size_limit(request) do
    metrics = field(request, :local_context_metrics)

    case field(request, :request_size_limit_bytes) ||
           field(metrics || %{}, :request_size_limit_bytes) do
      nil -> {:ok, nil}
      limit when is_integer(limit) and limit > 0 -> {:ok, limit}
      _ -> {:error, :invalid_response}
    end
  end

  defp request_size_limit!(request) do
    case request_size_limit(request) do
      {:ok, limit} -> limit
      {:error, _reason} -> 1
    end
  end

  defp enforce_body_size(_body, nil), do: :ok

  defp enforce_body_size(body, limit) when is_integer(limit) and limit > 0 do
    try do
      if byte_size(Jason.encode!(body)) <= limit, do: :ok, else: {:error, :context_too_large}
    rescue
      _error -> {:error, :invalid_response}
    end
  end

  defp enforce_body_size(_body, _limit), do: {:error, :invalid_response}

  defp enforce_followup_body_size(body, limit) do
    case enforce_body_size(body, limit) do
      {:error, :context_too_large} -> {:error, :context_followup_too_large}
      result -> result
    end
  end

  defp add_usage(accumulated, next) when is_map(next) do
    Enum.reduce([:input_tokens, :output_tokens], accumulated, fn key, acc ->
      case Map.get(next, key) do
        value when is_integer(value) and value >= 0 -> Map.update(acc, key, value, &(&1 + value))
        _ -> acc
      end
    end)
  end

  defp add_usage(accumulated, _next), do: accumulated

  defp one_shot_callback(callback) when is_function(callback, 0) do
    called = :atomics.new(1, signed: false)

    fn ->
      if :atomics.compare_exchange(called, 1, 0, 1) == :ok do
        callback.()
      end
    end
  end

  defp one_shot_callback(_callback), do: nil

  defp post_response(access_token, body, opts, stream_receive_timeout) do
    HTTP.request(
      :post,
      @responses_url,
      [
        headers: bearer_headers(access_token, "text/event-stream"),
        json: body,
        into: :self,
        receive_timeout: stream_receive_timeout,
        timeout_classification: :stream_receive_timeout
      ],
      http(opts)
    )
  end

  defp response_stream_receive_timeout(opts) do
    case Keyword.get(opts, :response_stream_receive_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> @response_stream_receive_timeout
    end
  end

  defp track_stream_activity(callback) do
    last_activity = :atomics.new(1, signed: true)
    :atomics.put(last_activity, 1, System.monotonic_time(:millisecond))

    tracked_callback = fn ->
      :atomics.put(last_activity, 1, System.monotonic_time(:millisecond))
      safely_call(callback)
    end

    {last_activity, tracked_callback}
  end

  defp require_http_success(response, phase, request_body \\ nil) do
    status = response_status(response)

    if status == 200 do
      :ok
    else
      details = http_error_details(response_body(response))

      log_provider_failure(
        phase,
        status,
        details,
        request_id(response),
        request_metrics(request_body)
      )

      {:error, error_for_status(status, details.reason)}
    end
  end

  defp error_for_status(401, _reason), do: :reauth_required
  defp error_for_status(403, :provider_error), do: :provider_error
  defp error_for_status(404, _reason), do: :model_unavailable
  defp error_for_status(429, reason), do: reason
  defp error_for_status(400, reason), do: reason
  defp error_for_status(503, :provider_error), do: :provider_unavailable
  defp error_for_status(503, reason), do: reason

  defp error_for_status(status, _reason) when is_integer(status) and status >= 500,
    do: :provider_unavailable

  defp error_for_status(_status, reason), do: reason

  defp consume_sse(body, on_first_output, on_narration_preview, on_stream_activity, started_at)
       when is_binary(body),
       do:
         consume_chunks(
           [body],
           on_first_output,
           on_narration_preview,
           on_stream_activity,
           started_at
         )

  defp consume_sse(body, on_first_output, on_narration_preview, on_stream_activity, started_at) do
    if Enumerable.impl_for(body),
      do:
        consume_chunks(
          body,
          on_first_output,
          on_narration_preview,
          on_stream_activity,
          started_at
        ),
      else: {:incomplete, :malformed}
  end

  defp consume_chunks(
         chunks,
         on_first_output,
         on_narration_preview,
         on_stream_activity,
         started_at
       ) do
    initial = {:ok, "", {:waiting, [], 0, false, [], initial_preview_state()}}

    result =
      Enum.reduce_while(chunks, initial, fn
        chunk,
        {:ok, buffer,
         {:waiting, _deltas, _size, _first_output?, _output_items, _preview_sent} = status}
        when is_binary(chunk) ->
          safely_call(on_stream_activity)
          {frames, rest} = split_frames(buffer <> chunk)

          case process_frames(
                 frames,
                 rest,
                 status,
                 on_first_output,
                 on_narration_preview,
                 started_at
               ) do
            {:ok, next_buffer, next_status} -> {:cont, {:ok, next_buffer, next_status}}
            {:halt, terminal} -> {:halt, terminal}
          end

        _, _state ->
          {:halt, {:incomplete, :non_binary_chunk}}
      end)

    case result do
      {:ok, buffer,
       {:waiting, _deltas, _size, _first_output?, _output_items, _preview_sent} = status} ->
        final_status =
          if String.trim(buffer) == "" do
            status
          else
            process_frame(buffer, status, on_first_output, on_narration_preview, started_at)
          end

        case final_status do
          {:completed, _, _, _} = completed -> completed
          {:failed, _} = failed -> failed
          {:incomplete, _} = incomplete -> incomplete
          _ -> :missing_completion
        end

      terminal ->
        terminal
    end
  rescue
    error in Req.TransportError -> {:transport_error, error}
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

  defp process_frames(frames, buffer, status, on_first_output, on_narration_preview, started_at) do
    Enum.reduce_while(frames, {:ok, buffer, status}, fn frame, {:ok, rest, current} ->
      case process_frame(frame, current, on_first_output, on_narration_preview, started_at) do
        {:waiting, _deltas, _size, _first_output?, _output_items, _preview_sent} = waiting ->
          {:cont, {:ok, rest, waiting}}

        terminal ->
          {:halt, {:halt, terminal}}
      end
    end)
  end

  defp process_frame(
         _frame,
         {:completed, _, _, _} = completed,
         _callback,
         _preview,
         _started_at
       ),
       do: completed

  defp process_frame(_frame, {:failed, _} = failed, _callback, _preview, _started_at),
    do: failed

  defp process_frame(_frame, {:incomplete, _} = incomplete, _callback, _preview, _started_at),
    do: incomplete

  defp process_frame(
         frame,
         {:waiting, deltas, size, first_output?, output_items, preview_sent},
         on_first_output,
         on_narration_preview,
         started_at
       ) do
    {event, data} = parse_frame(frame)

    case data do
      nil ->
        {:waiting, deltas, size, first_output?, output_items, preview_sent}

      "[DONE]" ->
        {:waiting, deltas, size, first_output?, output_items, preview_sent}

      encoded ->
        case Jason.decode(encoded) do
          {:ok, payload} when is_map(payload) ->
            process_event(
              event,
              payload,
              deltas,
              size,
              first_output?,
              output_items,
              preview_sent,
              on_first_output,
              on_narration_preview,
              started_at
            )

          _ ->
            {:incomplete, :invalid_sse_json}
        end
    end
  end

  defp process_frame(frame, _status, on_first_output, on_narration_preview, started_at) do
    {event, data} = parse_frame(frame)

    case data do
      nil ->
        {:waiting, [], 0, false, [], initial_preview_state()}

      "[DONE]" ->
        {:waiting, [], 0, false, [], initial_preview_state()}

      encoded ->
        case Jason.decode(encoded) do
          {:ok, payload} when is_map(payload) ->
            process_event(
              event,
              payload,
              [],
              0,
              false,
              [],
              initial_preview_state(),
              on_first_output,
              on_narration_preview,
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

  defp process_event(
         event,
         payload,
         deltas,
         size,
         first_output?,
         output_items,
         preview_sent,
         on_first_output,
         on_narration_preview,
         started_at
       ) do
    case payload["type"] || event do
      "response.completed" ->
        response = response_with_streamed_output(payload["response"], output_items)
        usage = response_usage(response)

        case output_text(response) do
          {:ok, text} ->
            complete_stream_response(text, usage, response, preview_sent, on_narration_preview)

          _ when size > 0 ->
            text = deltas |> Enum.reverse() |> IO.iodata_to_binary()
            complete_stream_response(text, usage, response, preview_sent, on_narration_preview)

          _ ->
            complete_stream_response("", usage, response, preview_sent, on_narration_preview)
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
            next_preview =
              maybe_emit_narration_preview(
                next_deltas,
                next_size,
                preview_sent,
                on_narration_preview
              )

            {:waiting, next_deltas, next_size, first_output?, output_items, next_preview}

          terminal ->
            terminal
        end

      "response.output_item.done" ->
        case payload["item"] do
          %{"type" => type} = item when type in ["message", "reasoning", "function_call"] ->
            {:waiting, deltas, size, first_output?, [item | output_items], preview_sent}

          _ ->
            {:waiting, deltas, size, first_output?, output_items, preview_sent}
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
        {:waiting, deltas, size, first_output?, output_items, preview_sent}
    end
  end

  defp complete_stream_response(text, usage, response, preview_state, on_narration_preview) do
    emit_completed_narration_preview(text, preview_state, on_narration_preview)
    {:completed, text, usage, response}
  end

  defp response_with_streamed_output(response, streamed_output) when is_map(response) do
    case field(response, :output) do
      output when is_list(output) and output != [] -> response
      _ when streamed_output != [] -> Map.put(response, "output", Enum.reverse(streamed_output))
      _ -> response
    end
  end

  defp response_with_streamed_output(response, _streamed_output), do: response

  defp notify_first_output(on_first_output, started_at) do
    duration = System.monotonic_time() - started_at

    TurnTelemetry.stop(:request_to_first_output, started_at, :ok)
    emit_first_text_delta_latency(duration)
    safely_call(on_first_output)
  end

  defp maybe_emit_narration_preview(_deltas, _size, sent, nil), do: sent

  defp maybe_emit_narration_preview(
         deltas,
         size,
         %{text: sent, source_size: scanned} = state,
         callback
       ) do
    cond do
      size - scanned < @narration_preview_min_source_growth_bytes ->
        state

      scanned >= @max_preview_source_bytes ->
        state

      true ->
        scanned_state = %{state | source_size: size}

        with true <- size > 0,
             output <-
               deltas
               |> Enum.reverse()
               |> IO.iodata_to_binary()
               |> binary_part(0, min(size, @max_preview_source_bytes)),
             {:ok, narration} <- partial_top_level_string(output, "narration"),
             narration <- String.slice(narration, 0, @max_narration_preview_chars),
             true <- byte_size(narration) > byte_size(sent) do
          safely_call(fn -> callback.(narration) end)
          %{text: narration, source_size: size}
        else
          _ -> scanned_state
        end
    end
  end

  defp emit_completed_narration_preview(_text, _state, nil), do: :ok

  defp emit_completed_narration_preview(text, %{text: sent}, callback) do
    with {:ok, narration} <- partial_top_level_string(text, "narration"),
         narration <- String.slice(narration, 0, @max_narration_preview_chars),
         true <- byte_size(narration) > byte_size(sent) do
      safely_call(fn -> callback.(narration) end)
    else
      _ -> :ok
    end
  end

  defp initial_preview_state, do: %{text: "", source_size: 0}

  # Extract only the top-level JSON narration string. A partial or malformed
  # field never falls back to raw response text, so dialogue and proposal data
  # cannot leak into the provisional player-facing preview.
  defp partial_top_level_string(json, wanted_key) do
    scan_top_level(json, 0, 0, wanted_key)
  end

  defp scan_top_level(json, index, _depth, _wanted_key) when index >= byte_size(json),
    do: :not_found

  defp scan_top_level(json, index, depth, wanted_key) do
    case :binary.at(json, index) do
      ?" ->
        case json_string_at(json, index + 1) do
          {:complete, raw, after_quote} ->
            if depth == 1 do
              key = decode_json_string(raw)
              colon = skip_json_whitespace(json, after_quote + 1)

              if key == wanted_key and byte_at(json, colon) == ?: do
                value_start = skip_json_whitespace(json, colon + 1)

                if byte_at(json, value_start) == ?",
                  do: partial_json_string_at(json, value_start + 1),
                  else: :not_found
              else
                scan_top_level(json, after_quote + 1, depth, wanted_key)
              end
            else
              scan_top_level(json, after_quote + 1, depth, wanted_key)
            end

          :incomplete ->
            :not_found
        end

      ?{ ->
        scan_top_level(json, index + 1, depth + 1, wanted_key)

      ?[ ->
        scan_top_level(json, index + 1, depth + 1, wanted_key)

      ?} ->
        scan_top_level(json, index + 1, max(depth - 1, 0), wanted_key)

      ?] ->
        scan_top_level(json, index + 1, max(depth - 1, 0), wanted_key)

      _ ->
        scan_top_level(json, index + 1, depth, wanted_key)
    end
  end

  defp json_string_at(json, index), do: json_string_at(json, index, index, false)

  defp json_string_at(json, index, _start, _escaped?) when index >= byte_size(json),
    do: :incomplete

  defp json_string_at(json, index, start, true),
    do: json_string_at(json, index + 1, start, false)

  defp json_string_at(json, index, start, false) do
    case :binary.at(json, index) do
      ?\\ -> json_string_at(json, index + 1, start, true)
      ?" -> {:complete, binary_part(json, start, index - start), index}
      _ -> json_string_at(json, index + 1, start, false)
    end
  end

  defp partial_json_string_at(json, start) do
    case json_string_at(json, start) do
      {:complete, raw, _after_quote} ->
        decode_json_string(raw)

      :incomplete ->
        raw = binary_part(json, start, byte_size(json) - start)
        decode_json_string(valid_json_string_prefix(raw))
    end
    |> case do
      value when is_binary(value) -> {:ok, value}
      _ -> :not_found
    end
  end

  defp decode_json_string(raw) do
    case Jason.decode("\"" <> raw <> "\"") do
      {:ok, value} when is_binary(value) -> value
      _ -> nil
    end
  end

  defp valid_json_string_prefix(raw), do: valid_json_string_prefix(raw, 0, 0)

  defp valid_json_string_prefix(raw, index, valid_end) when index >= byte_size(raw),
    do: binary_part(raw, 0, valid_end)

  defp valid_json_string_prefix(raw, index, valid_end) do
    byte = :binary.at(raw, index)

    cond do
      byte == ?\\ and index + 1 >= byte_size(raw) ->
        binary_part(raw, 0, valid_end)

      byte == ?\\ and :binary.at(raw, index + 1) == ?u ->
        if index + 6 <= byte_size(raw) and
             Enum.all?((index + 2)..(index + 5), fn offset ->
               hex_byte?(:binary.at(raw, offset))
             end),
           do: valid_json_string_prefix(raw, index + 6, index + 6),
           else: binary_part(raw, 0, valid_end)

      byte == ?\\ and :binary.at(raw, index + 1) in [?\", ?\\, ?/, ?b, ?f, ?n, ?r, ?t] ->
        valid_json_string_prefix(raw, index + 2, index + 2)

      byte == ?\\ ->
        binary_part(raw, 0, valid_end)

      byte < 0x20 ->
        binary_part(raw, 0, valid_end)

      true ->
        valid_json_string_prefix(raw, index + 1, index + 1)
    end
  end

  defp hex_byte?(byte), do: byte in ?0..?9 or byte in ?a..?f or byte in ?A..?F

  defp skip_json_whitespace(json, index) when index >= byte_size(json), do: index

  defp skip_json_whitespace(json, index) do
    if :binary.at(json, index) in [32, 9, 10, 13],
      do: skip_json_whitespace(json, index + 1),
      else: index
  end

  defp byte_at(json, index) when index < byte_size(json), do: :binary.at(json, index)
  defp byte_at(_json, _index), do: nil

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
    type = field(details, :type)
    message = field(details, :message)

    %{
      reason: if(is_binary(code), do: map_error_code(code), else: :provider_error),
      code: safe_diagnostic_value(code),
      param: safe_diagnostic_value(param),
      type: safe_error_type(type),
      message_class: provider_message_class(message),
      shape: shape
    }
  end

  defp empty_diagnostic(shape),
    do: %{
      reason: :provider_error,
      code: nil,
      param: nil,
      type: nil,
      message_class: nil,
      shape: shape
    }

  defp stream_diagnostic({shape, exception}) when is_atom(shape) and is_atom(exception),
    do: empty_diagnostic("#{shape}_#{inspect(exception)}")

  defp stream_diagnostic(shape) when is_atom(shape), do: empty_diagnostic(shape)
  defp stream_diagnostic(_shape), do: empty_diagnostic(:invalid_stream)

  defp log_provider_failure(phase, status, details, request_id, metrics \\ %{}) do
    request_metrics = format_request_metrics(metrics)

    Logger.warning(
      "ChatGPT plan inference failed phase=#{phase} status=#{format_status(status)} " <>
        "shape=#{Map.get(details, :shape, "unknown")} " <>
        "code=#{Map.get(details, :code) || "none"} " <>
        "type=#{Map.get(details, :type) || "none"} " <>
        "message_class=#{Map.get(details, :message_class) || "none"} " <>
        "param=#{Map.get(details, :param) || "none"} request_id=#{request_id || "none"}" <>
        request_metrics
    )
  end

  defp request_metrics(body) when is_map(body) do
    input = body["input"]
    instructions = body["instructions"]

    %{
      body_bytes: encoded_byte_size(body),
      input_bytes: encoded_byte_size(input),
      instruction_bytes: if(is_binary(instructions), do: byte_size(instructions), else: 0),
      input_items: if(is_list(input), do: length(input), else: 0),
      input_kinds: input_kinds(input)
    }
  end

  defp request_metrics(_body), do: %{}

  defp encoded_byte_size(value) do
    value |> Jason.encode!() |> byte_size()
  rescue
    _error -> 0
  end

  defp input_kinds(items) when is_list(items) do
    items
    |> Enum.map(&input_kind/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp input_kinds(_items), do: "none"

  defp input_kind(item) when is_map(item) do
    role = Map.get(item, :role) || Map.get(item, "role")
    type = Map.get(item, :type) || Map.get(item, "type")

    cond do
      role in ["assistant", "developer", "system", "user"] -> role
      type == "additional_tools" -> "additional_tools"
      true -> "other"
    end
  end

  defp input_kind(_item), do: "other"

  defp format_request_metrics(%{
         body_bytes: body_bytes,
         input_bytes: input_bytes,
         instruction_bytes: instruction_bytes,
         input_items: input_items,
         input_kinds: input_kinds
       }) do
    " body_bytes=#{body_bytes} input_bytes=#{input_bytes} " <>
      "instruction_bytes=#{instruction_bytes} input_items=#{input_items} input_kinds=#{input_kinds}"
  end

  defp format_request_metrics(_metrics), do: ""

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

  defp safe_error_type(type) when type in @safe_error_types, do: type
  defp safe_error_type(_type), do: nil

  defp provider_message_class(message) when is_binary(message) do
    normalized = String.downcase(message)

    cond do
      provider_limit_message?(normalized) -> "input_limit"
      provider_input_validation_message?(normalized) -> "input_validation"
      String.contains?(normalized, "unsupported") -> "unsupported"
      message == "" -> nil
      true -> "unclassified"
    end
  end

  defp provider_message_class(_message), do: nil

  defp provider_limit_message?(message) do
    input_or_context = String.contains?(message, "input") or String.contains?(message, "context")
    limit_terms = ["too large", "too long", "maximum", "exceed", "limit", "token"]

    input_or_context and Enum.any?(limit_terms, &String.contains?(message, &1))
  end

  defp provider_input_validation_message?(message) do
    validation_terms = [
      "invalid",
      "expected",
      "must be",
      "required",
      "array",
      "string",
      "content"
    ]

    String.contains?(message, "input") and
      Enum.any?(validation_terms, &String.contains?(message, &1))
  end

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

  defp map_error_code(code)
       when code in [
              "server_error",
              "service_unavailable",
              "overloaded_error",
              "rate_limit_exceeded"
            ],
       do: :provider_unavailable

  defp map_error_code("context_length_exceeded"), do: :context_length_exceeded

  defp map_error_code(_), do: :provider_error

  defp normalize_error(:timeout), do: :timeout
  defp normalize_error(:context_too_large), do: :context_budget_exceeded
  defp normalize_error(:temporary_auth_error), do: :provider_error
  defp normalize_error(:not_authenticated), do: :account_ineligible
  defp normalize_error(:plan_usage_not_authorized), do: :account_ineligible
  defp normalize_error(reason), do: reason

  defp system_message?(%{} = item) do
    role = field(item, :role)
    role == "system"
  end

  defp system_message?(_), do: false

  defp local_callback(request, key), do: local_callback(request, key, 0)

  defp local_callback(request, key, arity) do
    case field(request, key) do
      callback when is_function(callback, arity) -> callback
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
