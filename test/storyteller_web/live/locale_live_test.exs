defmodule StorytellerWeb.LocaleLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Settings
  alias Storyteller.Play.Objective
  alias Storyteller.Repo

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

  test "player character detail setup labels are translated", %{conn: conn} do
    assert {:ok, _preference} = Settings.set_ui_locale("es")
    {:ok, spanish_view, _html} = live(conn, ~p"/campaigns/new")

    spanish_html =
      spanish_view |> element("button[phx-click=add-player-detail]") |> render_click()

    assert spanish_html =~ "Detalles del personaje del jugador"
    assert spanish_html =~ "Opcional"
    assert spanish_html =~ "Añadir detalle del personaje"
    assert spanish_html =~ "Salud, habilidades o función"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, french_view, _html} = live(conn, ~p"/campaigns/new")
    french_html = french_view |> element("button[phx-click=add-player-detail]") |> render_click()
    assert french_html =~ "Détails du personnage joueur"
    assert french_html =~ "Facultatif"
    assert french_html =~ "Ajouter un détail du personnage"
    assert french_html =~ "Santé, compétences ou rôle"
  end

  test "GM starting-place setup guidance is translated", %{conn: conn} do
    assert {:ok, _preference} = Settings.set_ui_locale("es")
    {:ok, spanish_view, _html} = live(conn, ~p"/campaigns/new")
    spanish_html = spanish_view |> element("button[phx-click=add-character]") |> render_click()

    assert spanish_html =~ "Lugar de inicio"
    assert spanish_html =~ "Para empezar con el jugador"
    assert spanish_html =~ "lugar público separado"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, french_view, _html} = live(conn, ~p"/campaigns/new")
    french_html = french_view |> element("button[phx-click=add-character]") |> render_click()

    assert french_html =~ "Lieu de départ"
    assert french_html =~ "Pour commencer avec le joueur"
    assert french_html =~ "lieu public distinct"
  end

  test "inventory board labels are translated while campaign items remain unchanged", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        starting_location: "Vineyard gate",
        gm_characters: [
          %{
            speaker_id: "npc:keeper",
            name: "The Keeper",
            visible_facts: %{"location" => "Vineyard gate", "role" => "Cellar keeper"}
          }
        ],
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
    assert spanish_html =~ "Tu personaje"
    assert spanish_html =~ "Poción de luz"
    assert spanish_html =~ "2 viales"
    assert spanish_html =~ "La escena"
    assert spanish_html =~ "Personas aquí"
    assert spanish_html =~ "Vineyard gate"
    assert spanish_html =~ "The Keeper"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")
    assert french_html =~ "Inventaire"
    assert french_html =~ "Votre personnage"
    assert french_html =~ "Poción de luz"
    assert french_html =~ "2 viales"
    assert french_html =~ "La scène"
    assert french_html =~ "Personnes présentes"
    assert french_html =~ "Vineyard gate"
    assert french_html =~ "The Keeper"
  end

  test "active session controls explain resume and completion in every UI locale", %{conn: conn} do
    campaign = campaign_fixture()

    assert {:ok, _preference} = Settings.set_ui_locale("en")
    {:ok, _view, english_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert english_html =~ "Resume current session"
    assert english_html =~ "Start another session"
    assert english_html =~ "Starting another session completes the active session."

    assert {:ok, _preference} = Settings.set_ui_locale("es")
    {:ok, _view, spanish_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert spanish_html =~ "Reanudar la sesión actual"
    assert spanish_html =~ "Iniciar otra sesión"
    assert spanish_html =~ "La historia completa permanece guardada."

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert french_html =~ "Reprendre la session actuelle"
    assert french_html =~ "Commencer une autre session"
    assert french_html =~ "Toute son histoire reste enregistrée."
  end

  test "the objectives board localizes statuses and excludes GM-private objectives", %{
    conn: conn
  } do
    campaign = campaign_fixture(%{title: "The Glass Observatory"})
    session = hd(campaign.sessions)

    for {id, title, status, visibility} <- [
          {"repair-roof", "Repair the observatory roof", :open, :public},
          {"chart-stars", "Chart the winter stars", :completed, :public},
          {"close-cellar", "Close the unsafe cellar", :abandoned, :public},
          {"hidden-witness", "Find the hidden witness", :open, :gm_private}
        ] do
      Repo.insert!(
        Objective.changeset(%Objective{}, %{
          campaign_id: campaign.id,
          objective_id: id,
          title: title,
          status: status,
          visibility: visibility
        })
      )
    end

    assert {:ok, _preference} = Settings.set_ui_locale("es")
    {:ok, _view, spanish_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert spanish_html =~ "Compromisos de campaña"
    assert spanish_html =~ "Objetivos"
    assert spanish_html =~ "Abierto"
    assert spanish_html =~ "Completada"
    assert spanish_html =~ "Abandonado"
    assert spanish_html =~ "Repair the observatory roof"
    assert spanish_html =~ "Chart the winter stars"
    assert spanish_html =~ "Close the unsafe cellar"
    refute spanish_html =~ "Find the hidden witness"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert french_html =~ "Engagements de campagne"
    assert french_html =~ "Objectifs"
    assert french_html =~ "En cours"
    assert french_html =~ "Terminée"
    assert french_html =~ "Abandonné"
    assert french_html =~ "Repair the observatory roof"
    assert french_html =~ "Chart the winter stars"
    assert french_html =~ "Close the unsafe cellar"
    refute french_html =~ "Find the hidden witness"
  end
end
