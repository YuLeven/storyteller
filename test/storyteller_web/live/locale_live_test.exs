defmodule StorytellerWeb.LocaleLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Settings

  test "the locale selector persists its choice and redirects to a local page", %{conn: conn} do
    conn = get(conn, "/")

    assert [csrf_token] =
             Regex.run(~r/name="_csrf_token" value="([^"]+)"/, conn.resp_body,
               capture: :all_but_first
             )

    conn =
      conn
      |> recycle()
      |> put_req_header("referer", "http://www.example.com/campaigns/new")
      |> post("/locale", %{"locale" => "fr", "_csrf_token" => csrf_token})

    assert redirected_to(conn) == "/campaigns/new"
    assert get_session(conn, :ui_locale) == "fr"
    assert Settings.ui_locale() == "fr"
  end

  test "the saved interface locale changes labels without rewriting campaign content", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        title: "Moon Orchard",
        premise: "Keep this player-authored premise.",
        setting: "A quiet coast",
        tone: "Reflective",
        narration_language: "French",
        player_character: "Ari Vale"
      })

    assert {:ok, _preference} = Settings.set_ui_locale("es")
    assert Settings.ui_locale() == "es"

    {:ok, _view, html} = live(conn, ~p"/campaigns/#{campaign.id}")

    assert html =~ "Campañas"
    assert html =~ "Archivar campaña"
    assert html =~ "Keep this player-authored premise."
    assert html =~ "Ari Vale"
    assert html =~ "Narración en French"
    refute html =~ "Narration in French"

    stored_campaign = Storyteller.Campaigns.get_campaign!(campaign.id)
    assert stored_campaign.premise == "Keep this player-authored premise."
    assert stored_campaign.narration_language == "French"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live(conn, ~p"/campaigns/new")

    assert french_html =~ "Langue de l’interface"
    assert french_html =~ "Configurez votre campagne"
  end

  test "unsupported UI locales are rejected without changing the saved preference" do
    assert {:ok, _preference} = Settings.set_ui_locale("es")
    assert {:error, :invalid_locale} = Settings.set_ui_locale("de")
    assert Settings.ui_locale() == "es"
  end

  test "inventory board labels are translated while campaign items remain unchanged", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        inventory: [
          %{
            name: "Poción de luz",
            quantity: "2",
            unit: "viales",
            category: "Elixir"
          }
        ]
      })

    session = hd(campaign.sessions)

    assert {:ok, _preference} = Settings.set_ui_locale("es")
    {:ok, _view, spanish_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")
    assert spanish_html =~ "Inventario"
    assert spanish_html =~ "Objetos, provisiones y recuerdos"
    assert spanish_html =~ "Poción de luz"
    assert spanish_html =~ "2 viales"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")
    assert french_html =~ "Inventaire"
    assert french_html =~ "Objets, provisions et souvenirs"
    assert french_html =~ "Poción de luz"
    assert french_html =~ "2 viales"
  end
end
