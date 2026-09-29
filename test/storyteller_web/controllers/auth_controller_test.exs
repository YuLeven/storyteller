defmodule StorytellerWeb.AuthControllerTest do
  use StorytellerWeb.ConnCase, async: false

  alias StorytellerWeb.{AuthController, Router}

  test "connection page states the local MIT and plan-usage prerequisites", %{conn: conn} do
    html = conn |> get("/auth/connect") |> html_response(200)

    assert html =~ "Connection status"
    assert html =~ "MIT license"
    assert html =~ "eligible open-source, locally hosted apps"
    assert html =~ "does not use an API key or API credits"
    assert html =~ "Continue with ChatGPT"
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
    assert Phoenix.Controller.get_flash(conn, :error) =~ "incomplete or expired"
  end

  defp has_route?(routes, verb, path, action) do
    Enum.any?(routes, fn route ->
      route.verb == verb and route.path == path and route.plug == AuthController and
        route.plug_opts == action
    end)
  end
end
