defmodule StorytellerWeb.PageControllerTest do
  use StorytellerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Storyteller"
    assert html_response(conn, 200) =~ "Create a campaign"
  end
end
