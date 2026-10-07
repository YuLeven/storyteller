defmodule Storyteller.Auth.HTTP do
  @moduledoc "Small, non-logging HTTP boundary for OAuth and Responses calls."

  @default_timeout 20_000
  @stream_timeout_classification :stream_receive_timeout
  @timeout_classification_margin_ms 500

  def request(method, url, options, http \\ nil) when is_atom(method) and is_binary(url) do
    timeout_classification = Keyword.get(options, :timeout_classification)
    receive_timeout = Keyword.get(options, :receive_timeout, @default_timeout)

    options =
      options
      |> Keyword.delete(:timeout_classification)
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, url)
      |> Keyword.put(:retry, false)
      |> Keyword.put(:redirect, false)
      |> Keyword.put_new(:receive_timeout, @default_timeout)

    started_at = System.monotonic_time(:millisecond)

    case http do
      fun when is_function(fun, 3) ->
        safely_call(
          fun,
          method,
          url,
          options,
          timeout_classification,
          started_at,
          receive_timeout
        )

      nil ->
        req_request(options, timeout_classification, started_at, receive_timeout)

      module when is_atom(module) ->
        safely_call_module(
          module,
          method,
          url,
          options,
          timeout_classification,
          started_at,
          receive_timeout
        )

      _ ->
        {:error, :invalid_http_adapter}
    end
  end

  def decode_json(body) when is_map(body), do: {:ok, body}

  def decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_response}
    end
  end

  def decode_json(_), do: {:error, :invalid_response}

  @doc false
  def classify_stream_timeout(started_at, receive_timeout) do
    if long_receive_timeout_elapsed?(started_at, receive_timeout),
      do: :timeout,
      else: :network_error
  end

  defp req_request(options, timeout_classification, started_at, receive_timeout) do
    req = Module.concat(["Req"])

    case apply(req, :request, [options]) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         classify_transport_error(reason, timeout_classification, started_at, receive_timeout)}

      _ ->
        {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp safely_call(fun, method, url, options, timeout_classification, started_at, receive_timeout) do
    case fun.(method, url, options) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         classify_transport_error(reason, timeout_classification, started_at, receive_timeout)}

      response when is_map(response) ->
        {:ok, response}

      _ ->
        {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp safely_call_module(
         module,
         method,
         url,
         options,
         timeout_classification,
         started_at,
         receive_timeout
       ) do
    case apply(module, :request, [method, url, options]) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         classify_transport_error(reason, timeout_classification, started_at, receive_timeout)}

      response when is_map(response) ->
        {:ok, response}

      _ ->
        {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp classify_transport_error(reason, timeout_classification, started_at, receive_timeout)
       when reason == :timeout or
              (is_struct(reason, Req.TransportError) and reason.reason == :timeout) do
    case timeout_classification do
      @stream_timeout_classification ->
        classify_stream_timeout(started_at, receive_timeout)

      _ ->
        :timeout
    end
  end

  defp classify_transport_error(_reason, _timeout_classification, _started_at, _receive_timeout),
    do: :network_error

  defp long_receive_timeout_elapsed?(started_at, receive_timeout)
       when is_integer(receive_timeout) and receive_timeout > 0 do
    margin = min(@timeout_classification_margin_ms, div(receive_timeout, 20))
    elapsed = System.monotonic_time(:millisecond) - started_at
    elapsed >= receive_timeout - margin
  end

  defp long_receive_timeout_elapsed?(_started_at, _receive_timeout), do: false
end
