defmodule Storyteller.Auth.HTTP do
  @moduledoc "Small, non-logging HTTP boundary for OAuth and Responses calls."

  @default_timeout 20_000

  def request(method, url, options, http \\ nil) when is_atom(method) and is_binary(url) do
    options =
      options
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, url)
      |> Keyword.put(:retry, false)
      |> Keyword.put(:redirect, false)
      |> Keyword.put_new(:receive_timeout, @default_timeout)

    case http do
      fun when is_function(fun, 3) -> safely_call(fun, method, url, options)
      nil -> req_request(options)
      module when is_atom(module) -> safely_call_module(module, method, url, options)
      _ -> {:error, :invalid_http_adapter}
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

  defp req_request(options) do
    req = Module.concat(["Req"])

    case apply(req, :request, [options]) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, classify_transport_error(reason)}
      _ -> {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp safely_call(fun, method, url, options) do
    case fun.(method, url, options) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, classify_transport_error(reason)}
      response when is_map(response) -> {:ok, response}
      _ -> {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp safely_call_module(module, method, url, options) do
    case apply(module, :request, [method, url, options]) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, classify_transport_error(reason)}
      response when is_map(response) -> {:ok, response}
      _ -> {:error, :invalid_response}
    end
  rescue
    _ -> {:error, :network_error}
  catch
    _, _ -> {:error, :network_error}
  end

  defp classify_transport_error(:timeout), do: :timeout
  defp classify_transport_error(%Req.TransportError{reason: :timeout}), do: :timeout
  defp classify_transport_error(_reason), do: :network_error
end
