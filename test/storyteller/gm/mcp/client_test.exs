defmodule Storyteller.GM.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.MCP
  alias Storyteller.GM.MCP.Client

  test "initializes a Streamable HTTP session, lists tools over SSE, and calls a tool" do
    test_pid = self()

    mcp_tools =
      [
        %{
          "name" => "read_entries",
          "description" => "Read the fixture ledger",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"category" => %{"type" => "string"}}
          }
        },
        %{
          "name" => "record_campaign_fact",
          "description" => "Record a campaign fact established in the story",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"fact" => %{"type" => "string"}},
            "required" => ["fact"]
          }
        },
        %{
          "name" => "write_story_journal",
          "description" => "Write an established event to the story journal",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"entry" => %{"type" => "string"}},
            "required" => ["entry"]
          }
        }
      ] ++
        Enum.map(1..67, fn index ->
          %{
            "name" => "fixture_tool_#{index}",
            "description" => "Fixture catalog entry #{index}",
            "inputSchema" => %{"type" => "object", "properties" => %{}}
          }
        end)

    plug = fn conn, _opts ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(test_pid, {:mcp_request, request, conn.req_headers})

      conn = Plug.Conn.put_resp_header(conn, "mcp-session-id", "test-session")

      case request["method"] do
        "initialize" ->
          result = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "protocolVersion" => "2025-03-26",
              "capabilities" => %{"tools" => %{}},
              "serverInfo" => %{"name" => "Fixture MCP", "version" => "1.0"}
            }
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(result))

        "notifications/initialized" ->
          Plug.Conn.resp(conn, 202, "")

        "tools/list" ->
          result = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "tools" => mcp_tools
            }
          }

          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.resp(200, "event: message\ndata: #{Jason.encode!(result)}\n\n")

        "tools/call" ->
          result = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "content" => [%{"type" => "text", "text" => "Two entries found."}],
              "structuredContent" => %{"count" => 2}
            }
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(result))
      end
    end

    {:ok, server} =
      Bandit.start_link(
        plug: plug,
        ip: {127, 0, 0, 1},
        port: 0,
        startup_log: false
      )

    Process.unlink(server)
    on_exit(fn -> Supervisor.stop(server) end)
    assert {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    list_result = Client.list_tools("http://127.0.0.1:#{port}/mcp")

    assert_receive {:mcp_request, initialize, initialize_headers}
    assert_receive {:mcp_request, %{"method" => "notifications/initialized"}, notified_headers}
    assert_receive {:mcp_request, %{"method" => "tools/list", "id" => 2}, list_headers}

    assert {:ok, client, listed_tools} = list_result
    assert client.session_id == "test-session"
    assert length(listed_tools) == 70
    tool = Enum.find(listed_tools, &(&1["name"] == "read_entries"))
    assert tool["name"] == "read_entries"

    assert {:ok, result} = Client.call_tool(client, "read_entries", %{"category" => "public"})
    assert result["structuredContent"] == %{"count" => 2}

    assert initialize["method"] == "initialize"
    assert initialize["params"]["clientInfo"]["name"] == "Storyteller"
    refute Enum.any?(initialize_headers, fn {name, _value} -> name == "mcp-session-id" end)

    assert header(notified_headers, "mcp-session-id") == "test-session"
    assert header(notified_headers, "mcp-protocol-version") == "2025-03-26"

    assert header(list_headers, "mcp-session-id") == "test-session"

    assert_receive {:mcp_request,
                    %{
                      "method" => "tools/call",
                      "id" => 3,
                      "params" => %{
                        "name" => "read_entries",
                        "arguments" => %{"category" => "public"}
                      }
                    }, call_headers}

    assert header(call_headers, "mcp-session-id") == "test-session"

    registry =
      MCP.prepare([
        %{
          "id" => "fixture-project",
          "name" => "Fixture project",
          "mcp_endpoint_url" => "http://127.0.0.1:#{port}/mcp",
          "instructions" => "Check the fixture ledger before writing."
        }
      ])

    assert [%{available?: true, tool_count: 70}] = registry.statuses
    assert Enum.map(registry.tools, & &1["name"]) == ["mcp1_search_tools", "mcp1_call_tool"]

    assert {:ok, %{"tools" => discovered_tools}} =
             registry.executors["mcp1_search_tools"].(%{"query" => "campaign fact"})

    discovered = Enum.find(discovered_tools, &(&1["name"] == "record_campaign_fact"))
    assert discovered["inputSchema"]["properties"]["fact"]["type"] == "string"

    call_tool_spec = Enum.at(registry.tools, 1)

    assert "record_campaign_fact" in call_tool_spec["parameters"]["properties"]["tool_name"][
             "enum"
           ]

    assert {:ok, dispatched_result} =
             registry.executors["mcp1_call_tool"].(%{
               "tool_name" => "record_campaign_fact",
               "arguments" => %{"fact" => "The keeper opened the old cellar."}
             })

    assert dispatched_result["structuredContent"] == %{"count" => 2}

    assert {:ok, %{"error" => _message}} =
             registry.executors["mcp1_call_tool"].(%{
               "tool_name" => "not_registered",
               "arguments" => %{}
             })
  end

  test "accepts Finca-style JSON tool catalogs without an MCP session" do
    plug = fn conn, _opts ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      case request["method"] do
        "initialize" ->
          rpc_response = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "protocolVersion" => "2025-03-26",
              "capabilities" => %{"tools" => %{"listChanged" => false}},
              "serverInfo" => %{"name" => "finca-la-esperanza", "version" => "0.1.0"}
            }
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(rpc_response))

        "notifications/initialized" ->
          Plug.Conn.resp(conn, 202, "")

        "tools/list" ->
          rpc_response = %{
            "jsonrpc" => "2.0",
            "id" => request["id"],
            "result" => %{
              "tools" => [
                %{
                  "name" => "record_campaign_fact",
                  "description" => "Record a fact established in the campaign.",
                  "inputSchema" => %{
                    "type" => "object",
                    "properties" => %{"fact" => %{"type" => "string"}},
                    "required" => ["fact"]
                  }
                }
              ]
            }
          }

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(rpc_response))
      end
    end

    {:ok, server} =
      Bandit.start_link(
        plug: plug,
        ip: {127, 0, 0, 1},
        port: 0,
        startup_log: false
      )

    Process.unlink(server)
    on_exit(fn -> Supervisor.stop(server) end)
    assert {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    assert {:ok, client, [tool]} = Client.list_tools("http://127.0.0.1:#{port}/mcp")
    assert is_nil(client.session_id)
    assert tool["name"] == "record_campaign_fact"
  end

  defp header(headers, key) do
    case Enum.find(headers, fn {name, _value} -> name == key end) do
      {_name, value} -> value
      nil -> nil
    end
  end
end
