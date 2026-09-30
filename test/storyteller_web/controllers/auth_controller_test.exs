defmodule StorytellerWeb.AuthControllerTest do
  use StorytellerWeb.ConnCase, async: false

  alias Storyteller.Auth.{Credentials, TokenStore}
  alias StorytellerWeb.{AuthController, Router}

  test "connection page states the local MIT and plan-usage prerequisites", %{conn: conn} do
    html = conn |> get("/auth/connect") |> html_response(200)

    assert html =~ "Connection status"
    assert html =~ "MIT license"
    assert html =~ "eligible open-source, locally hosted apps"
    assert html =~ "does not use an API key or API credits"

    assert html =~
             "If a limit blocks a turn, Storyteller preserves it so you can retry after the limit resets."

    refute html =~ "Storyteller pauses play"
    assert html =~ "Continue with ChatGPT"
  end

  test "connected account page links to ChatGPT usage settings", %{conn: conn} do
    credentials = %Credentials{
      client_id: "test-client",
      subject: "test-account",
      email: "player@example.test",
      host_id: TokenStore.host_id(),
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: System.system_time(:second) + 3_600,
      scopes: ["openid", "chatgpt.tokens.use.direct"]
    }

    assert :ok = TokenStore.put_credentials(credentials)

    on_exit(fn ->
      _ = TokenStore.sign_out(fn _credentials -> :ok end)
    end)

    html = conn |> get("/auth/connect") |> html_response(200)

    assert html =~ "ChatGPT plan usage is connected."
    assert html =~ "https://chatgpt.com/settings/usage"
    assert html =~ "Manage usage"
  end

  test "OAuth routes use the required loopback callback path and browser post endpoints" do
    routes = Router.__routes__()

    assert has_route?(routes, :get, "/auth/connect", :connect)
    assert has_route?(routes, :post, "/auth/authorize", :authorize)
    assert has_route?(routes, :get, "/auth/callback", :callback)
    assert has_route?(routes, :post, "/auth/disconnect", :disconnect)
  end

  test "an incomplete callback is safely returned to connection status", %{conn: conn} do
    conn = conn |> get("/auth/callback")

    assert redirected_to(conn) == "/auth/connect"
  end

  defp has_route?(routes, verb, path, action) do
    Enum.any?(routes, fn route ->
      route.verb == verb and route.path == path and route.plug == AuthController and
        route.plug_opts == action
    end)
  end
end
