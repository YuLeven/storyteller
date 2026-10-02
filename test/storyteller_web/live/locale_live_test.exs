defmodule StorytellerWeb.LocaleLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Settings
  alias Storyteller.Play
  alias Storyteller.Play.Objective
  alias Storyteller.Play.Turn
  alias Storyteller.Repo
  alias StorytellerWeb.LocaleLiveTest.FakeProvider

  setup do
    previous_provider = Application.get_env(:storyteller, :gm_provider, :not_configured)
    Application.put_env(:storyteller, :gm_provider, FakeProvider)

    on_exit(fn ->
      case previous_provider do
        :not_configured -> Application.delete_env(:storyteller, :gm_provider)
        provider -> Application.put_env(:storyteller, :gm_provider, provider)
      end
    end)

    :ok
  end

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

  test "character voice coaching and limits are translated in setup and edit cards", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{gm_characters: [%{speaker_id: "keeper-elin", name: "Keeper Elin"}]})

    for {locale, example, delivery_guidance, limit_guidance} <- [
          {
            "es",
            "Describe cómo suena, por ejemplo, con pausas medidas, frases breves o palabras bien elegidas.",
            "Este perfil guía cómo el director de juego interpreta al personaje",
            "Cada campo admite hasta 280 caracteres; todas las notas juntas permiten 1200."
          },
          {
            "fr",
            "Décrivez sa façon de parler, par exemple avec des pauses mesurées, des phrases courtes ou des mots choisis avec soin.",
            "Ce profil guide la façon dont le maître de jeu interprète le personnage",
            "Chaque champ accepte jusqu’à 280 caractères"
          }
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)

      {:ok, setup_view, _html} = live(conn, ~p"/campaigns/new")
      setup_html = setup_view |> element("button[phx-click=add-character]") |> render_click()

      assert has_element?(setup_view, "#gm-character-0", example)
      assert setup_html =~ delivery_guidance
      assert setup_html =~ limit_guidance

      {:ok, edit_view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

      for card <- ["#facts-keeper-elin", "#new-gm-character"] do
        assert has_element?(edit_view, card, example)
        assert has_element?(edit_view, card, delivery_guidance)
        assert has_element?(edit_view, card, limit_guidance)
      end
    end
  end

  test "active duty setup, editor guidance, and validation are translated", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        gm_characters: [%{speaker_id: "keeper-elin", name: "Keeper Elin"}]
      })

    story = %{
      title: "The Quiet Beacon",
      premise: "A keeper finds a note beneath the lantern.",
      setting: "A fictional island harbor",
      tone: "Warm and quietly suspenseful",
      narration_language: "English"
    }

    player = %{player_character_name: "Ilya", player_character: "A patient harbor courier."}
    opening = %{starting_location: "The Finca", starting_date: "Day one", world_time: "Morning"}

    for {locale, label, placeholder, setup_help, edit_help, validation_error, setup_error} <- [
          {
            "es",
            "Tarea activa",
            "Cuidar las cubas",
            "se requiere un lugar inicial.",
            "Borra el nombre de la tarea para liberarla.",
            "Una tarea activa requiere un nombre de hasta 160 caracteres, un lugar actual conocido y una duración expresada en minutos enteros entre 0 y 525600.",
            "necesita un lugar de inicio para una tarea activa"
          },
          {
            "fr",
            "Tâche active",
            "Surveiller les cuves",
            "un lieu de départ est requis.",
            "Effacez le nom de la tâche pour la libérer.",
            "Une tâche active exige un nom de 160 caractères maximum, un lieu actuel connu et une durée exprimée en minutes entières de 0 à 525600.",
            "doit avoir un lieu de départ pour une tâche active"
          }
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)

      {:ok, setup_view, _html} = live(conn, ~p"/campaigns/new")
      submit_setup_step(setup_view, story, "continue")
      submit_setup_step(setup_view, Map.merge(story, player), "continue")
      submit_setup_step(setup_view, Map.merge(Map.merge(story, player), opening), "continue")
      setup_html = setup_view |> element("button[phx-click=add-character]") |> render_click()
      assert setup_html =~ label
      assert setup_html =~ placeholder
      assert setup_html =~ setup_help

      invalid_setup =
        Map.merge(Map.merge(Map.merge(story, player), opening), %{
          gm_characters: %{
            "0" => %{name: "Elin", active_duty_name: "Tend the lantern", starting_place: ""}
          }
        })

      error_html = submit_setup_step(setup_view, invalid_setup, "continue")
      assert error_html =~ setup_error

      {:ok, edit_view, edit_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
      assert edit_html =~ label
      assert edit_html =~ edit_help

      invalid_edit = %{
        correction_reason: "Give Elin a current task.",
        character_active_duties: %{"keeper-elin" => %{duty_name: "Watch the harbor"}}
      }

      error_html =
        edit_view |> form("#campaign-edit-form", campaign: invalid_edit) |> render_submit()

      error_text = error_html |> Floki.parse_document!() |> Floki.text()
      assert error_text =~ validation_error
    end
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
    {:ok, _view, spanish_html} = live_session(conn, campaign, session)
    assert spanish_html =~ "Inventario"
    assert spanish_html =~ "Tu personaje"
    assert spanish_html =~ "Poción de luz"
    assert spanish_html =~ "2 viales"
    assert spanish_html =~ "La escena"
    assert spanish_html =~ "Contigo"
    assert spanish_html =~ "Vineyard gate"
    assert spanish_html =~ "The Keeper"

    assert {:ok, _preference} = Settings.set_ui_locale("fr")
    {:ok, _view, french_html} = live_session(conn, campaign, session)
    assert french_html =~ "Inventaire"
    assert french_html =~ "Votre personnage"
    assert french_html =~ "Poción de luz"
    assert french_html =~ "2 viales"
    assert french_html =~ "La scène"
    assert french_html =~ "Avec vous"
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
    campaign =
      campaign_fixture(%{title: "The Glass Observatory", starting_location: "Observatory"})

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
    {:ok, _view, spanish_html} = live_session(conn, campaign, session)

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
    {:ok, _view, french_html} = live_session(conn, campaign, session)

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

  test "new GM character editor labels are translated", %{conn: conn} do
    campaign = campaign_fixture(%{starting_location: "The Finca"})
    [session] = campaign.sessions

    Repo.insert!(
      Turn.changeset(%Turn{}, %{
        campaign_id: campaign.id,
        session_id: session.id,
        idempotency_key: "locale-new-character-pending-turn",
        request_hash: String.duplicate("0", 64),
        player_input: "Look around.",
        intent: :action,
        status: :pending,
        resolution_phase: :initial,
        attempts: 0
      })
    )

    for {locale, labels, pending_error} <- [
          {
            "es",
            [
              "Añadir un personaje controlado por el director de juego",
              "Nombre del personaje (obligatorio)",
              "Datos visibles para el jugador (opcional)",
              "Notas solo para el director de juego (opcional)",
              "Lugar público actual (opcional)",
              "Desconocido / sin ubicación",
              "Permanecerá sin ubicación salvo que elijas un lugar público"
            ],
            "Espera a que el director de juego termine el turno antes de cambiar una tarea activa o añadir un personaje."
          },
          {
            "fr",
            [
              "Ajouter un personnage contrôlé par le maître du jeu",
              "Nom du personnage (obligatoire)",
              "Informations visibles par le joueur (facultatif)",
              "Notes réservées au maître du jeu (facultatif)",
              "Lieu public actuel (facultatif)",
              "Inconnu / sans lieu",
              "Il reste sans lieu jusqu’à ce que vous choisissiez un lieu public"
            ],
            "Attendez que le maître du jeu termine le tour avant de modifier une tâche active ou d’ajouter un personnage."
          }
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

      Enum.each(labels, fn label -> assert html =~ label end)

      pending_html =
        view
        |> form("#campaign-edit-form",
          campaign: %{
            title: campaign.title,
            new_gm_character: %{name: "Pending Arrival"}
          }
        )
        |> render_submit()

      assert pending_html =~ pending_error
    end
  end

  defp submit_setup_step(view, attrs, direction) do
    view
    |> form("#campaign-form", campaign: attrs)
    |> put_submitter("button[name=direction][value=#{direction}]")
    |> render_submit()
  end

  defp live_session(conn, campaign, session) do
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert wait_until(fn ->
             case Play.public_current_turn(campaign.id) do
               %{intent: :opening_scene, status: status} when status in [:pending, :resolving] ->
                 false

               %{intent: :opening_scene, status: :failed} ->
                 false

               %{intent: intent} when intent != :opening_scene ->
                 true

               _ ->
                 has_element?(view, "#turn-input:not([disabled])")
             end
           end),
           "the isolated fake GM did not finish the opening scene"

    {:ok, view, render(view)}
  end

  defp wait_until(fun, attempts \\ 60)
  defp wait_until(fun, 0), do: fun.()

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end
end

defmodule StorytellerWeb.LocaleLiveTest.FakeProvider do
  @behaviour Storyteller.Play.Provider

  @opening_scene %{
    narration: "The opening scene is ready.",
    dialogue: [],
    activities: [],
    public_changes: %{},
    private_changes: %{},
    memory_update: %{public_summary: "", gm_private_summary: ""},
    panel_changes: [],
    character_updates: [],
    character_creations: [],
    inventory_changes: [],
    location_changes: [],
    objective_changes: [],
    continuity_changes: [],
    roll_request: nil
  }

  @impl true
  def stream_response(_request), do: {:ok, @opening_scene}
end
