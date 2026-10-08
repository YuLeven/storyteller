defmodule Storyteller.GM.MCP.Client do
  @moduledoc "Minimal Streamable HTTP MCP client for campaign companion servers."

  defstruct [:url, :protocol_version, :session_id, next_id: 1]

  @protocol_version "2025-03-26"
  @timeout_ms 30_000
  @max_response_bytes 1_000_000
  @max_pages 10

  def list_tools(url) when is_binary(url) do
    with {:ok, client} <- initialize(url),
         {:ok, client} <- notify_initialized(client),
         {:ok, client, tools} <- list_tool_pages(client, [], nil, 0) do
      {:ok, client, tools}
    end
  end

  def list_tools(_url), do: {:error, :invalid_endpoint}

  def call_tool(%__MODULE__{} = client, name, arguments)
      when is_binary(name) and is_map(arguments) do
    with {:ok, response, _client} <-
           request(client, "tools/call", %{"name" => name, "arguments" => arguments}),
         result when is_map(result) <- response["result"] do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_mcp_response}
    end
  end

  defp initialize(url) do
    with :ok <- validate_endpoint(url) do
      client = %__MODULE__{url: url, protocol_version: @protocol_version}

      case post(
             client,
             %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "initialize",
               "params" => %{
                 "protocolVersion" => @protocol_version,
                 "capabilities" => %{},
                 "clientInfo" => %{"name" => "Storyteller", "version" => "0.1.0"}
               }
             },
             initialize?: true
           ) do
        {:ok, %{"result" => %{"protocolVersion" => version}}, session_id}
        when is_binary(version) ->
          if byte_size(version) <= 40 do
            {:ok, %{client | protocol_version: version, session_id: session_id, next_id: 2}}
          else
            {:error, :invalid_mcp_response}
          end

        {:ok, _response, _session_id} ->
          {:error, :invalid_mcp_response}

        error ->
          error
      end
    end
  end

  defp notify_initialized(client) do
    message = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

    case post(client, message) do
      {:ok, _body, _session_id} -> {:ok, client}
      error -> error
    end
  end

  defp list_tool_pages(client, tools, cursor, page) when page < @max_pages do
    params = if is_binary(cursor), do: %{"cursor" => cursor}, else: %{}

    with {:ok, response, updated_client} <- request(client, "tools/list", params),
         result when is_map(result) <- response["result"],
         page_tools when is_list(page_tools) <- result["tools"],
         true <- length(tools) + length(page_tools) <= 100 do
      all_tools = tools ++ page_tools

      case result["nextCursor"] do
        next when is_binary(next) and next != "" ->
          list_tool_pages(updated_client, all_tools, next, page + 1)

        _ ->
          {:ok, updated_client, all_tools}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_mcp_response}
    end
  end

  defp list_tool_pages(_client, _tools, _cursor, _page), do: {:error, :too_many_mcp_tools}

  defp request(%__MODULE__{} = client, method, params) do
    id = client.next_id
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}

    with {:ok, response, session_id} <- post(client, message),
         true <- response["id"] == id do
      {:ok, response, %{client | next_id: id + 1, session_id: session_id || client.session_id}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_mcp_response}
    end
  end

  defp post(client, message, opts \\ []) do
    headers = [
      {"accept", "application/json, text/event-stream"},
      {"content-type", "application/json"}
    ]

    headers =
      if Keyword.get(opts, :initialize?, false) do
        headers
      else
        [{"mcp-protocol-version", client.protocol_version} | session_header(client)] ++ headers
      end

    case Req.post(client.url,
           json: message,
           headers: headers,
           receive_timeout: @timeout_ms,
           connect_options: [timeout: 5_000],
           redirect: false
         ) do
      {:ok, %{status: status} = response} when status in [200, 202] ->
        with {:ok, body} <- decode_response(response, message["id"], status),
             {:ok, encoded} <- Jason.encode(body),
             true <- byte_size(encoded) <= @max_response_bytes,
             {:ok, session_id} <- validated_session_id(get_header(response, "mcp-session-id")) do
          {:ok, body, session_id}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, :mcp_response_too_large}
        end

      {:ok, %{status: 404}} when not is_nil(client.session_id) ->
        {:error, :mcp_session_expired}

      {:ok, _response} ->
        {:error, :mcp_server_unavailable}

      {:error, _reason} ->
        {:error, :mcp_server_unavailable}
    end
  rescue
    _error -> {:error, :mcp_server_unavailable}
  end

  defp decode_response(%{body: _body, headers: _headers}, id, 202) when is_nil(id),
    do: {:ok, %{}}

  defp decode_response(%{body: body, headers: headers}, id, _status) do
    content_type = headers |> Map.get("content-type", []) |> List.first() |> to_string()

    if String.contains?(String.downcase(content_type), "text/event-stream") do
      decode_sse(body, id)
    else
      decode_json_response(body, id)
    end
  end

  defp decode_json_response(body, id) when is_binary(body) do
    with {:ok, response} <- Jason.decode(body),
         true <- is_nil(id) or response["id"] == id do
      {:ok, response}
    else
      _ -> {:error, :invalid_mcp_response}
    end
  end

  defp decode_json_response(response, id) when is_map(response) do
    if is_nil(id) or response["id"] == id,
      do: {:ok, response},
      else: {:error, :invalid_mcp_response}
  end

  defp decode_json_response(_, _), do: {:error, :invalid_mcp_response}

  defp decode_sse(body, id) when is_binary(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.split("\n\n", trim: true)
    |> Enum.flat_map(fn event ->
      event
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.trim_leading(String.trim_leading(&1, "data:"), " "))
    end)
    |> Enum.reduce_while({:error, :invalid_mcp_response}, fn data, _acc ->
      case Jason.decode(data) do
        {:ok, response} when is_map(response) ->
          if is_nil(id) or Map.get(response, "id") == id,
            do: {:halt, {:ok, response}},
            else: {:cont, {:error, :invalid_mcp_response}}

        _ ->
          {:cont, {:error, :invalid_mcp_response}}
      end
    end)
  end

  defp decode_sse(_, _), do: {:error, :invalid_mcp_response}

  defp validate_endpoint(url) do
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_nil(uri.fragment) do
      :ok
    else
      {:error, :invalid_endpoint}
    end
  rescue
    _error -> {:error, :invalid_endpoint}
  end

  defp session_header(%__MODULE__{session_id: session_id}) when is_binary(session_id),
    do: [{"mcp-session-id", session_id}]

  defp session_header(_client), do: []

  defp get_header(%{headers: headers}, name) do
    headers
    |> Map.get(name, [])
    |> List.first()
  end

  defp validated_session_id(nil), do: {:ok, nil}

  defp validated_session_id(session_id)
       when is_binary(session_id) and byte_size(session_id) in 1..256 do
    if String.match?(session_id, ~r/\A[\x21-\x7E]+\z/),
      do: {:ok, session_id},
      else: {:error, :invalid_mcp_response}
  end

  defp validated_session_id(_), do: {:error, :invalid_mcp_response}
end
