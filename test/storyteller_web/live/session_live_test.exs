defmodule StorytellerWeb.SessionLiveTest.FakeProvider do
  @behaviour Storyteller.Play.Provider

  @impl true
  def stream_response(request) do
    Application.fetch_env!(:storyteller, :session_live_test_handler).(request)
  end
end

defmodule StorytellerWeb.SessionLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.Auth.{Credentials, TokenStore}
  alias Storyteller.Play
  alias Storyteller.Play.{Event, Objective, State, Turn}
  alias Storyteller.Repo
  alias Storyteller.Settings
  alias StorytellerWeb.SessionLiveTest.FakeProvider

  setup do
    previous_provider = Application.get_env(:storyteller, :gm_provider, :not_configured)

    previous_handler =
      Application.get_env(:storyteller, :session_live_test_handler, :not_configured)

    previous_roll_source = Application.get_env(:storyteller, :d20_roll_source, :not_configured)

    previous_plan_usage_store =
      Application.get_env(:storyteller, :plan_usage_token_store, :not_configured)

    pause_store_directory =
      Path.join(System.tmp_dir!(), "storyteller-live-pause-#{Ecto.UUID.generate()}")

    pause_store =
      start_supervised!(
        {TokenStore, path: Path.join(pause_store_directory, "state.json"), name: nil}
      )

    Application.put_env(:storyteller, :plan_usage_token_store, pause_store)

    Application.put_env(:storyteller, :gm_provider, FakeProvider)

    on_exit(fn ->
      restore_env(:gm_provider, previous_provider)
      restore_env(:session_live_test_handler, previous_handler)
      restore_env(:d20_roll_source, previous_roll_source)
      restore_env(:plan_usage_token_store, previous_plan_usage_store)
      File.rm_rf(pause_store_directory)
    end)

    :ok
  end

  test "campaign premise stays available as a collapsed in-play reference", %{conn: conn} do
    premise = "A lantern has gone dark above the sleeping harbor."
    campaign = campaign_fixture(%{premise: premise})
    session = hd(campaign.sessions)

    {:ok, view, html} = live(conn, session_path(campaign, session))

    assert has_element?(view, "details#campaign-premise > summary", "Story premise")
    refute has_element?(view, "details#campaign-premise[open]")
    assert has_element?(view, "#app-settings > summary", "Settings")
    refute has_element?(view, "#app-settings[open]")
    refute html =~ "Your local campaign archive"
    refute html =~ "Narration:"
    assert html =~ premise
  end

  test "an incomplete textarea change event does not take down the live play screen", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    {:ok, view, _html} = live(conn, session_path(campaign, session))

    render_change(view, "change-input", %{
      "_target" => ["turn", "input"],
      "turn" => %{"idempotency_key" => Ecto.UUID.generate()}
    })

    assert has_element?(view, "#turn-input")
  end

  test "campaign board shows durable public memory and omits GM-private continuity details", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    set_handler(fn _request ->
      {:ok,
       %{
         narration: "The cellar door remains sealed for another day.",
         dialogue: [],
         activities: [],
         public_changes: %{},
         private_changes: %{},
         character_updates: [],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         continuity_changes: [
           %{
             "type" => "create",
             "entry" => %{
               "entry_id" => "campaign-glasshouse-promise",
               "kind" => "commitment",
               "title" => "The glasshouse promise",
               "details" => "You promised to repair the glasshouse roof before the first frost.",
               "visibility" => "public"
             },
             "reason" => "The keeper asks the player to honor the promise."
           },
           %{
             "type" => "create",
             "entry" => %{
               "entry_id" => "gm-hidden-passage",
               "kind" => "fact",
               "title" => "Hidden north passage",
               "details" => "The north cellar wall conceals a passage.",
               "visibility" => "gm_private"
             },
             "reason" => "Keep the discovery secret until the player finds the latch."
           }
         ],
         roll_request: nil
       }}
    end)

    assert {:ok, _turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "campaign-memory-board",
               "I check the cellar.",
               provider: FakeProvider
             )

    {:ok, view, html} = live(conn, session_path(campaign, session))

    assert has_element?(view, "#campaign-memory", "The glasshouse promise")
    assert has_element?(view, "#campaign-memory", "before the first frost")
    refute has_element?(view, "#story-timeline", "Campaign memory")
    refute has_element?(view, "#story-timeline", "You promised to repair the glasshouse roof")
    refute has_element?(view, "#campaign-memory", "Hidden north passage")
    refute render(view) =~ "north cellar wall conceals a passage"
    refute has_element?(view, "#campaign-memory details[open]")

    memory_list_classes =
      html
      |> Floki.parse_document!()
      |> Floki.find("#campaign-memory ul")
      |> hd()
      |> Floki.attribute("class")
      |> hd()

    refute "overflow-y-auto" in String.split(memory_list_classes)
  end

  test "narrow session navigation targets the scene, story, and character board",
       %{
         conn: conn
       } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    assert has_element?(view, "nav#session-sections[aria-label]")
    assert has_element?(view, "#session-sections.lg\\:hidden")

    for target <- [
          "turn-composer-card",
          "current-place",
          "story-timeline",
          "character-inventory",
          "campaign-memory"
        ] do
      assert has_element?(view, "#session-sections a[href='##{target}']")

      tabindex = if target == "story-timeline", do: "0", else: "-1"
      assert has_element?(view, "##{target}[tabindex='#{tabindex}']")
    end

    assert has_element?(view, "#session-sections a[href='#current-place']", "The scene")
    assert has_element?(view, "#session-sections a[href='#campaign-memory']", "Campaign memory")
    refute has_element?(view, "#session-sections a[href='#world-state']")

    refute has_element?(view, "#session-sections a[href='#campaign-objectives']")
    refute has_element?(view, "#session-sections a[href='#campaign-fields']")
    refute has_element?(view, "#campaign-fields")
  end

  test "the scene card shows the latest public narration as the current situation", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, context["player_action"]})

      narration =
        case context["player_action"] do
          "I listen for footsteps." -> "Footsteps echo from the upper gallery."
          "I open the gallery door." -> "Cold rain sweeps into the gallery."
        end

      {:ok,
       %{
         narration: narration,
         dialogue: [],
         activities: [],
         public_changes: %{},
         private_changes: %{"secret" => "A hidden passage lies behind the shelves."},
         character_updates: [],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    assert has_element?(
             view,
             "#current-place #current-situation",
             "No current situation has been recorded yet."
           )

    for {action, narration} <- [
          {"I listen for footsteps.", "Footsteps echo from the upper gallery."},
          {"I open the gallery door.", "Cold rain sweeps into the gallery."}
        ] do
      view
      |> form("#turn-composer", turn: %{input: action})
      |> render_submit()

      assert_receive {:fake_gm_call, ^action}, 1_000

      assert wait_until(fn ->
               has_element?(view, "#current-place #current-situation", narration)
             end)

      refute has_element?(
               view,
               "#current-place #current-situation",
               "A hidden passage lies behind the shelves."
             )
    end

    assert has_element?(view, "#story-timeline", "Footsteps echo from the upper gallery.")
    assert has_element?(view, "#story-timeline", "Cold rain sweeps into the gallery.")

    refute has_element?(
             view,
             "#current-place #current-situation",
             "Footsteps echo from the upper gallery."
           )

    refute render(view) =~ "A hidden passage lies behind the shelves."
  end

  test "current situation label and empty state follow the selected interface locale", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    for {locale, label, empty_state} <- [
          {"es", "Situación actual", "Aún no se ha registrado la situación actual."},
          {"fr", "Situation actuelle", "La situation actuelle n’a pas encore été enregistrée."}
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      {:ok, view, _html} = live(conn, session_path(campaign, session))

      assert has_element?(view, "#current-situation-label", label)
      assert has_element?(view, "#current-situation", empty_state)
    end
  end

  test "session navigation adds links when public objectives or tracked resources exist", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        panel_fields: %{
          "0" => %{
            key: "lamp_oil",
            panel: "Supplies",
            label: "Lamp oil",
            value_type: "quantity",
            unit: "flasks",
            visibility: "public",
            initial_value: "2"
          }
        }
      })

    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    Repo.insert!(
      Objective.changeset(%Objective{}, %{
        campaign_id: campaign.id,
        objective_id: "find-the-signal",
        title: "Find the signal source",
        status: :open,
        visibility: :public
      })
    )

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    for target <- [
          "current-place",
          "story-timeline",
          "character-inventory",
          "turn-composer-card",
          "campaign-objectives",
          "campaign-fields"
        ] do
      assert has_element?(view, "#session-sections a[href='##{target}']")

      tabindex = if target == "story-timeline", do: "0", else: "-1"
      assert has_element?(view, "##{target}[tabindex='#{tabindex}']")
    end
  end

  test "the play header pairs a moon cue with mist across English Spanish and French terms", %{
    conn: conn
  } do
    for {time, weather, sky_icon} <- [
          {"Midnight", "Cool mist", "moon"},
          {"Medianoche", "Niebla fresca", "moon"},
          {"Minuit", "Brume fraîche", "moon"},
          {"Midmorning", "Cool mist", "sun"},
          {"Media mañana", "Niebla fresca", "sun"},
          {"Matinée", "Brume fraîche", "sun"}
        ] do
      campaign = campaign_fixture()
      session = hd(campaign.sessions)

      state = Repo.get_by!(State, campaign_id: campaign.id)

      Repo.update!(
        State.changeset(state, %{
          public_state: Map.merge(state.public_state, %{"time" => time, "weather" => weather})
        })
      )

      {:ok, view, _html} = live(conn, session_path(campaign, session))

      mode = if sky_icon == "moon", do: "night", else: "day"

      assert has_element?(
               view,
               "#scene-weather-cue[data-scene-cue='#{mode}-mist'][data-time-mode='#{mode}'][data-weather-mode='mist'] svg"
             )

      assert has_element?(view, "#scene-weather-cue [data-sky-icon='#{sky_icon}']")
      assert has_element?(view, "#scene-weather-cue [data-weather-icon='cloud']")
      assert has_element?(view, "#scene-weather-cue [data-weather-icon='mist']")

      assert has_element?(view, "#world-time", time)
      assert has_element?(view, "#world-weather", weather)
    end

    for {time, mode} <- [{"12:00 AM", "night"}, {"12:00 PM", "day"}] do
      campaign = campaign_fixture()
      session = hd(campaign.sessions)
      state = Repo.get_by!(State, campaign_id: campaign.id)

      Repo.update!(
        State.changeset(state, %{
          public_state: Map.merge(state.public_state, %{"time" => time, "weather" => "cloudy"})
        })
      )

      {:ok, view, _html} = live(conn, session_path(campaign, session))
      assert has_element?(view, "#scene-weather-cue[data-time-mode='#{mode}'] svg")
    end

    for {time, weather} <- [
          {"first watch", "unfamiliar sky"},
          {"22:00", "unclear"},
          {"22:00", "train"}
        ] do
      fallback_campaign = campaign_fixture()
      fallback_session = hd(fallback_campaign.sessions)
      fallback_state = Repo.get_by!(State, campaign_id: fallback_campaign.id)

      Repo.update!(
        State.changeset(fallback_state, %{
          public_state:
            Map.merge(fallback_state.public_state, %{"time" => time, "weather" => weather})
        })
      )

      {:ok, fallback_view, _html} = live(conn, session_path(fallback_campaign, fallback_session))
      assert has_element?(fallback_view, "#scene-weather-cue[data-scene-cue='neutral'] svg")
    end
  end

  test "the story stays conversational while world and NPC state update in their panels", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{title: "The Amber Road", starting_location: "Observatory grounds"})

    [session] = campaign.sessions

    {:ok, _state} =
      Play.initialize_campaign(campaign, %{
        public_state: %{"date" => "Day 3, June 10", "time" => "09:15", "weather" => "Cloudy"},
        characters: [%{speaker_id: "rhea", name: "Rhea Vale"}]
      })

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state:
          Map.merge(state.public_state, %{
            "date" => "Day 3, June 10",
            "time" => "09:15",
            "weather" => "Cloudy"
          })
      })
    )

    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, context})

      {:ok,
       %{
         narration: "The stone archway opens onto a quiet road.",
         dialogue: [%{speaker_id: "rhea", text: "The western path is clear."}],
         activities: [%{speaker_id: "rhea", text: "Rhea checks the gate latch."}],
         public_changes: %{
           "date" => "Day 3, June 10",
           "time" => "09:20",
           "weather" => "A light rain begins"
         },
         location_changes: [
           %{
             type: "create_place",
             place: %{
               place_id: "western-road",
               name: "The western road",
               visibility: "public",
               facts: %{"path" => "western"}
             },
             reason: "The stone archway opens onto the road."
           },
           %{
             type: "move_character",
             speaker_id: "player",
             place_id: "western-road",
             reason: "The player passes through the archway."
           },
           %{
             type: "move_character",
             speaker_id: "rhea",
             place_id: "western-road",
             reason: "Rhea joins the player by the archway."
           }
         ],
         private_changes: %{"unseen_clue" => "This stays private"},
         character_updates: [
           %{speaker_id: "rhea", visible_facts: %{"trust" => "She trusts your judgment."}}
         ],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))
    refute has_element?(view, "#roll-panel")
    assert has_element?(view, "#chatgpt-plan-status a[href='/auth/connect']")

    view
    |> form("#turn-composer",
      turn: %{
        input: "I test the latch and ask Rhea about the road."
      }
    )
    |> render_submit()

    assert_receive {:fake_gm_call, %{"phase" => "initial"}}, 1_000
    assert wait_until(fn -> render(view) =~ "The western path is clear." end)
    html = render(view)

    assert html =~ "The stone archway opens onto a quiet road."
    assert html =~ "Rhea Vale"
    assert html =~ "Rhea checks the gate latch."
    refute has_element?(view, "#story-timeline", "Rhea checks the gate latch.")
    assert html =~ "The western road"
    assert has_element?(view, "#current-place", "The western road")
    assert has_element?(view, "#world-location", "The western road")
    assert has_element?(view, "#current-place", "Rhea Vale")
    assert html =~ "09:20"
    assert html =~ "A light rain begins"
    assert html =~ "Day 3, June 10"
    refute html =~ "This stays private"
    refute html =~ "UTC"

    player_action = Repo.get_by!(Event, campaign_id: campaign.id, event_type: :player_action)
    gm_narration = Repo.get_by!(Event, campaign_id: campaign.id, event_type: :gm_narration)
    private_change = Repo.get_by!(Event, campaign_id: campaign.id, visibility: :gm_private)

    assert player_action.game_time == %{"date" => "Day 3, June 10", "time" => "09:15"}
    assert gm_narration.game_time == %{"date" => "Day 3, June 10", "time" => "09:20"}
    assert private_change.game_time == nil
    assert has_element?(view, "#event-#{player_action.sequence}", "Day 3, June 10 · 09:15")
    assert has_element?(view, "#event-#{gm_narration.sequence}", "Day 3, June 10 · 09:20")
    assert has_element?(view, "#world-weather[data-panel-watch='world-weather']")

    {:ok, public_events} = Play.public_timeline(campaign.id)
    {:ok, %{events: story_events}} = Play.public_story_timeline_page(campaign.id)
    assert Enum.any?(public_events, &(&1.event_type == :state_change))
    assert Enum.any?(public_events, &(&1.event_type == :character_activity))
    refute Enum.any?(story_events, &(&1.event_type in [:state_change, :character_activity]))

    for {locale, label} <- [{"es", "Hora del juego"}, {"fr", "Heure du jeu"}] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      {:ok, localized_view, localized_html} = live(conn, session_path(campaign, session))

      assert has_element?(
               localized_view,
               "#event-#{gm_narration.sequence}",
               label
             )

      refute localized_html =~ "UTC"
    end

    assert {:ok, _preference} = Settings.set_ui_locale("en")

    {:ok, projection} = Play.public_projection(campaign.id)
    rhea = Enum.find(projection.characters, &(&1.speaker_id == "rhea"))
    assert rhea.visible_activity == "Rhea checks the gate latch."
    assert rhea.visible_facts["trust"] == "She trusts your judgment."
    assert projection.world["location"] == "The western road"

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "location", "A stale world location")
      })
    )

    {:ok, reloaded_view, reloaded_html} = live(conn, session_path(campaign, session))
    assert has_element?(reloaded_view, "#world-location", "The western road")
    refute reloaded_html =~ "A stale world location"
  end

  test "campaign story is a keyboard-scrollable independent timeline", %{conn: conn} do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    {:ok, _state} = Play.initialize_campaign(campaign)

    {:ok, view, html} = live(conn, session_path(campaign, session))

    timeline = Floki.parse_document!(html) |> Floki.find("#story-timeline") |> hd()
    assert Floki.attribute(timeline, "tabindex") == ["0"]
    assert Floki.attribute(timeline, "phx-hook") == ["StoryTimeline"]
    assert has_element?(view, "#story-reveal-controls[hidden]")
    assert has_element?(view, "#story-reveal-announcement[role='status'][aria-live='polite']")
    assert html =~ "lg:sticky"
    assert html =~ "lg:overflow-y-auto"
    assert html =~ "lg:overscroll-y-auto"
    refute html =~ "overscroll-y-contain"
  end

  test "legacy time aliases appear once and agree across the player board", %{conn: conn} do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state:
          Map.merge(state.public_state, %{
            "time" => "Early morning",
            "world_time" => "Midmorning"
          })
      })
    )

    {:ok, view, html} = live(conn, session_path(campaign, session))

    assert has_element?(view, "#world-time", "Early morning")
    refute html =~ "Midmorning"
    refute has_element?(view, "#world-state")

    time_facts =
      html
      |> Floki.parse_document!()
      |> Floki.find("#world-time")

    assert length(time_facts) == 1
  end

  test "player character fact updates appear on the board without a system chat entry", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        player_character_details: [%{label: "Health", value: "Weary"}]
      })

    session = hd(campaign.sessions)

    set_handler(fn _request ->
      {:ok,
       %{
         narration: "After resting, you feel ready to return to the terrace.",
         dialogue: [],
         activities: [],
         public_changes: %{},
         private_changes: %{},
         panel_changes: [],
         character_updates: [
           %{
             speaker_id: "player",
             visible_facts: %{"Health" => "Rested"},
             reason: "The player rests through the afternoon."
           }
         ],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         inventory_changes: [],
         location_changes: [],
         objective_changes: [],
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    assert has_element?(
             view,
             "#story-live-timeline[aria-live='polite'][aria-relevant='additions'][aria-atomic='false']"
           )

    assert has_element?(view, "#empty-timeline")

    view
    |> form("#turn-composer", turn: %{input: "I rest through the afternoon."})
    |> render_submit()

    assert wait_until(fn -> render(view) =~ "Rested" end)
    refute has_element?(view, "#story-timeline", "Character details updated")
    refute has_element?(view, "#story-timeline", "The player rests through the afternoon.")

    assert has_element?(
             view,
             "#story-live-timeline[aria-live='polite'][aria-relevant='additions'][aria-atomic='false']"
           )

    assert has_element?(view, "#campaign-characters", "Health")

    {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.visible_facts["Health"] == "Rested"
  end

  test "resource transactions update their panel without a system chat entry", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        panel_fields: %{
          "0" => %{
            key: "orchard_cash",
            panel: "Orchard ledger",
            label: "Cash",
            value_type: "money",
            unit: "silver",
            visibility: "public",
            initial_value: "18.50"
          },
          "1" => %{
            key: "keeper_secret",
            panel: "GM notes",
            label: "Hidden clue",
            value_type: "text",
            visibility: "gm_private",
            initial_value: "secret stock in the north cellar"
          }
        }
      })

    [session] = campaign.sessions

    set_handler(fn _request ->
      {:ok,
       %{
         narration: "The customer pays for a basket of apples.",
         dialogue: [],
         activities: [],
         public_changes: %{},
         private_changes: %{},
         panel_changes: [
           %{
             type: "delta",
             key: "orchard_cash",
             delta: "6.25",
             reason: "A customer pays for one basket of apples."
           }
         ],
         character_updates: [],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         inventory_changes: [],
         location_changes: [],
         objective_changes: [],
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer", turn: %{input: "Sell a basket of apples."})
    |> render_submit()

    assert wait_until(fn -> render(view) =~ "The customer pays for a basket of apples." end)
    assert has_element?(view, "#campaign-fields", "24.75")
    assert has_element?(view, "#campaign-fields details > summary", "Last changed")
    assert has_element?(view, "#campaign-fields details", "Cash: 18.5 silver → 24.75 silver")

    assert has_element?(
             view,
             "#campaign-fields details",
             "A customer pays for one basket of apples."
           )

    refute has_element?(view, "#campaign-fields details[open]")
    refute render(view) =~ "secret stock in the north cellar"
    refute has_element?(view, "#story-timeline", "Cash: 18.5 silver → 24.75 silver")
    refute has_element?(view, "#story-timeline", "A customer pays for one basket of apples.")

    state_event = Repo.get_by!(Event, campaign_id: campaign.id, event_type: :state_change)
    assert state_event.payload["panel_changes"] != []

    assert state_event.payload["panel_changes"] |> hd() |> Map.fetch!("reason") ==
             "A customer pays for one basket of apples."
  end

  test "new character introductions render the name and public facts without private facts", %{
    conn: conn
  } do
    campaign = campaign_fixture(%{title: "The Amber Road"})
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    set_handler(fn _request ->
      {:ok,
       %{
         narration: "A courier steps out from under the stone arch.",
         dialogue: [%{speaker_id: "npc:orin", text: "I can show you the safe road."}],
         activities: [],
         public_changes: %{},
         private_changes: %{},
         panel_changes: [],
         character_creations: [
           %{
             speaker_id: "npc:orin",
             name: "Orin Vale",
             visible_facts: %{"trade" => "Courier"},
             gm_private_facts: %{"real_goal" => "find the sealed map"}
           }
         ],
         character_updates: [],
         memory_update: %{
           public_summary: "Orin is a courier.",
           gm_private_summary: "Orin seeks a map."
         },
         inventory_changes: [],
         location_changes: [],
         objective_changes: [],
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer", turn: %{input: "Ask the stranger about the road."})
    |> render_submit()

    assert wait_until(fn -> render(view) =~ "Orin Vale" end)
    html = render(view)
    assert has_element?(view, "#story-timeline", "A courier steps out from under the stone arch.")
    assert has_element?(view, "#story-timeline", "I can show you the safe road.")
    refute has_element?(view, "#story-timeline", "Character introduced")
    assert has_element?(view, "#campaign-characters", "Orin Vale")
    assert has_element?(view, "#campaign-characters", "Courier")
    assert html =~ "Orin Vale"
    refute html =~ "find the sealed map"
    refute html =~ "seeks a map"
  end

  test "a connected ChatGPT plan is clear beside the composer and links to usage settings", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

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

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    assert has_element?(view, "#chatgpt-plan-status", "Using ChatGPT plan")

    assert has_element?(
             view,
             "#chatgpt-plan-status a[href='https://chatgpt.com/settings/usage']",
             "Manage usage"
           )
  end

  test "public player and party items append an editable action in the narration language", %{
    conn: conn
  } do
    cases = [
      {"English", "es", "Usar en la acción", "Usa Sunstone en tu acción", "I use Sunstone.",
       "I use Copper lantern."},
      {"Spanish", "fr", "Utiliser dans l’action", "Utiliser Sunstone dans votre action",
       "Uso Sunstone.", "Uso Copper lantern."},
      {"French", "en", "Use in action", "Use Sunstone in your action", "J’utilise Sunstone.",
       "J’utilise Copper lantern."}
    ]

    for {narration_language, ui_locale, button_label, accessible_label, sentence, party_sentence} <-
          cases do
      campaign =
        campaign_fixture(%{
          narration_language: narration_language
        })

      session = hd(campaign.sessions)
      seed_action_items(campaign.id)
      assert {:ok, _preference} = Settings.set_ui_locale(ui_locale)
      {:ok, view, _html} = live(conn, session_path(campaign, session))

      player_button = "#inventory-item-player-sunstone button[phx-click]"
      party_button = "#inventory-item-party-lantern button[phx-click]"
      npc_button = "#inventory-item-keeper-key button[phx-click]"

      assert has_element?(view, player_button, button_label)
      assert has_element?(view, party_button, button_label)
      refute has_element?(view, npc_button)
      refute render(view) =~ "Hidden obsidian relic"

      assert [accessible_label] ==
               Floki.parse_document!(render(view))
               |> Floki.find(player_button)
               |> Floki.attribute("aria-label")

      {:ok, before_projection} = Play.public_projection(campaign.id)
      {:ok, before_timeline} = Play.public_timeline(campaign.id)

      view
      |> form("#turn-composer", turn: %{input: "I listen at the door."})
      |> render_change()

      view |> element(player_button) |> render_click()
      assert render(view) =~ "I listen at the door.\n#{sentence}"

      first_draft = "I listen at the door.\n#{sentence}"

      assert_push_event(view, "action-composer:update", %{
        draft: ^first_draft
      })

      assert has_element?(
               view,
               "#turn-input[phx-hook='ActionComposer']"
             )

      view |> element(party_button) |> render_click()
      assert render(view) =~ "I listen at the door.\n#{sentence}\n#{party_sentence}"

      combined_draft = "I listen at the door.\n#{sentence}\n#{party_sentence}"

      assert_push_event(view, "action-composer:update", %{
        draft: ^combined_draft
      })

      assert has_element?(view, "#turn-input[phx-hook='ActionComposer']")

      edited_draft = "I listen at the door.\n#{sentence}\n#{party_sentence} I change my mind."

      view
      |> form("#turn-composer", turn: %{input: edited_draft})
      |> render_change()

      assert render(view) =~ edited_draft
      assert is_nil(Play.public_current_turn(campaign.id))
      {:ok, after_projection} = Play.public_projection(campaign.id)
      {:ok, after_timeline} = Play.public_timeline(campaign.id)
      assert after_projection.inventory == before_projection.inventory
      assert after_timeline == before_timeline

      # Forged public-NPC and hidden IDs are treated exactly like unknown IDs.
      before_forged_click = render(view)
      render_click(view, "use-in-action", %{"item_id" => "keeper-key"})
      render_click(view, "use-in-action", %{"item_id" => "hidden-relic"})
      assert render(view) == before_forged_click
      assert is_nil(Play.public_current_turn(campaign.id))
    end
  end

  test "inventory details humanize keys and compact nested player-authored properties", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    seed_action_items(campaign.id, %{
      "remaining_charges" => 2,
      "attunement" => "Once per dawn",
      "crafting_data" => %{
        "maker_name" => "Mira Vale",
        "ingredients" => ["Moon leaf", "RED MOSS"],
        "engraving" => %{"text" => "<star>"}
      }
    })

    {:ok, view, _html} = live(conn, session_path(campaign, session))
    details = "#inventory-item-player-sunstone details"
    html = render(view)

    assert has_element?(view, details <> " summary", "Item details")
    assert html =~ "Remaining charges"
    assert html =~ "Once per dawn"
    assert html =~ "Crafting data / Maker name"
    assert html =~ "Mira Vale"
    assert html =~ "Crafting data / Ingredients"

    assert html =~ "[&quot;Moon leaf&quot;, &quot;RED MOSS&quot;]" or
             html =~ "[\"Moon leaf\", \"RED MOSS\"]"

    assert html =~ "Engraving / Text"
    assert html =~ "&lt;star&gt;"
    refute html =~ "<star>"
    refute has_element?(view, details <> " pre")

    summary =
      html
      |> Floki.parse_document!()
      |> Floki.find(details <> " summary")
      |> hd()

    summary_classes = summary |> Floki.attribute("class") |> hd() |> String.split()
    assert "focus-visible:ring-2" in summary_classes
  end

  test "play sidebar keeps at-a-glance context and quick item actions visible", %{conn: conn} do
    campaign = campaign_fixture(%{starting_location: "The Observatory"})
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    inventory =
      Enum.map(1..5, fn index ->
        %{
          "id" => "ration-#{index}",
          "name" => "Ration #{index}",
          "category" => "Food",
          "quantity" => index,
          "owner_id" => "player",
          "visibility" => "public",
          "properties" => %{}
        }
      end)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", inventory)
      })
    )

    {:ok, projection} = Play.public_projection(campaign.id)
    expected_visible_items = Enum.take(projection.inventory, 2)
    [first_additional_item | _] = Enum.drop(projection.inventory, 2)

    {:ok, view, html} = live(conn, session_path(campaign, session))

    refute has_element?(view, "#campaign-objectives[open]")
    assert has_element?(view, "#campaign-objectives > summary [role='heading']", "Objectives")
    assert has_element?(view, "#current-place #current-situation")
    refute has_element?(view, "#scene-details[open]")
    assert has_element?(view, "#scene-details summary", "Scene details and people")
    refute has_element?(view, "#campaign-characters[open]")
    assert has_element?(view, "#campaign-characters > summary [role='heading']", "Characters")

    at_a_glance_ids =
      html
      |> Floki.parse_document!()
      |> Floki.find("#inventory-at-a-glance > li")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))

    expected_visible_ids =
      Enum.map(expected_visible_items, fn item ->
        "inventory-item-" <> Map.fetch!(item, "id")
      end)

    assert at_a_glance_ids == expected_visible_ids

    first_visible_id = "inventory-item-" <> Map.fetch!(hd(expected_visible_items), "id")

    assert has_element?(
             view,
             "#inventory-at-a-glance ##{first_visible_id} button[phx-click]",
             "Use in action"
           )

    refute has_element?(view, "#inventory-additional[open]")
    assert has_element?(view, "#inventory-additional summary", "See 3 more")

    first_additional_id = "inventory-item-" <> Map.fetch!(first_additional_item, "id")

    assert has_element?(
             view,
             "#inventory-additional-list ##{first_additional_id} button[phx-click]"
           )
  end

  test "D20 is only generated after the validated roll request is clicked", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, self(), context})

      if context["phase"] == "initial" do
        receive do
          :continue_resolution -> :ok
        after
          5_000 -> flunk("initial resolution was not released")
        end

        {:ok,
         %{
           narration: "The narrow bridge sways over the ravine.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: %{test: "Agility", difficulty: "Hard", target: 14}
         }}
      else
        receive do
          :continue_resolution -> :ok
        after
          5_000 -> flunk("after-roll resolution was not released")
        end

        {:ok,
         %{
           narration: "You steady your footing and reach the far side.",
           dialogue: [],
           activities: [],
           public_changes: %{"weather" => "Clear"},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: nil
         }}
      end
    end)

    Application.put_env(:storyteller, :d20_roll_source, fn ->
      send(test_pid, :d20_source_used)
      17
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    assert has_element?(
             view,
             "#turn-announcement[role='status'][aria-live='polite'][aria-atomic='true']"
           )

    refute has_element?(view, "#turn-status[aria-live]")
    refute has_element?(view, "#turn-error[aria-live]")
    refute has_element?(view, "#roll-panel[aria-live]")
    refute has_element?(view, "button[phx-click='roll-d20']")

    view
    |> form("#turn-composer",
      turn: %{input: "I cross the bridge carefully."}
    )
    |> render_submit()

    assert_receive {:fake_gm_call, initial_provider, %{"phase" => "initial"}}, 1_000
    assert has_element?(view, "#turn-status")
    assert has_element?(view, "#turn-announcement", "The game master is responding")
    assert has_element?(view, "#composer-turn-status", "The game master is responding")
    assert has_element?(view, "#story-pending-action", "I cross the bridge carefully.")
    assert has_element?(view, "#turn-input[disabled]")
    refute has_element?(view, "#story-timeline #event-1")
    refute has_element?(view, "#turn-status[aria-live]")
    send(initial_provider, :continue_resolution)
    assert wait_until(fn -> has_element?(view, "#roll-panel", "Agility") end)
    refute has_element?(view, "#roll-panel[aria-live]")
    assert has_element?(view, "#turn-announcement", "Roll requested: Agility")
    assert has_element?(view, "#composer-turn-status", "Roll requested: Agility")
    refute has_element?(view, "#story-pending-action")
    assert has_element?(view, "#story-timeline", "Agility")
    assert has_element?(view, "#story-timeline", "Difficulty: Hard")
    assert has_element?(view, "#story-timeline", "Target: 14")
    refute_receive :d20_source_used, 100

    view |> element("#roll-panel button[phx-click='roll-d20']") |> render_click()
    assert_receive :d20_source_used, 1_000
    assert_receive {:fake_gm_call, after_roll_provider, %{"phase" => "after_roll"}}, 1_000
    assert has_element?(view, "#turn-announcement", "The game master is responding")
    assert has_element?(view, "#composer-turn-status", "The game master is responding")
    assert has_element?(view, "#turn-announcement", "D20 result: 17")
    send(after_roll_provider, :continue_resolution)
    assert wait_until(fn -> render(view) =~ "You steady your footing and reach the far side." end)
    assert has_element?(view, "#turn-announcement", "Your turn is complete.")
    assert has_element?(view, "#composer-turn-status", "Your turn is complete.")
    refute has_element?(view, "#story-pending-action")

    html = render(view)
    assert html =~ "D20 result: 17"
    assert html =~ "You steady your footing and reach the far side."
    assert has_element?(view, "#event-1[data-event-type='player_action']")

    action_occurrences =
      html
      |> Floki.parse_document!()
      |> Floki.find("#story-timeline #event-1")
      |> Enum.count(&(Floki.text(&1) =~ "I cross the bridge carefully."))

    assert action_occurrences == 1

    {:ok, resumed, _html} = live(conn, session_path(campaign, session))
    assert has_element?(resumed, "#story-timeline", "Difficulty: Hard")
    assert has_element?(resumed, "#story-timeline", "Target: 14")
    refute has_element?(resumed, "#turn-announcement", "complete")
  end

  test "a pending action survives a fresh connection and is replaced by its canonical event", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)
    action = "I carry the basket into the press house."

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, Ecto.UUID.generate(), action,
               provider: nil
             )

    assert turn.status == :pending
    assert {:ok, []} = Play.public_timeline(campaign.id)

    test_pid = self()

    set_handler(fn _request ->
      send(test_pid, {:provider_waiting, self()})

      receive do
        :continue -> :ok
      after
        5_000 -> flunk("pending turn was not released")
      end

      {:ok,
       %{
         narration: "The press house is quiet and ready for the apples.",
         dialogue: [],
         activities: [],
         public_changes: %{},
         private_changes: %{},
         character_updates: [],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         roll_request: nil
       }}
    end)

    # A fresh mount stands in for reload/reconnect. Before resolution finishes,
    # the durable pending turn is the only source for its visible action.
    {:ok, view, _html} = live(conn, session_path(campaign, session))
    assert_receive {:provider_waiting, provider_pid}, 1_000
    assert has_element?(view, "#story-pending-action", action)
    assert has_element?(view, "#composer-turn-status")
    refute has_element?(view, "#story-timeline [data-event-type='player_action']")

    send(provider_pid, :continue)

    assert wait_until(fn ->
             has_element?(view, "#story-timeline", "The press house is quiet and ready")
           end)

    refute has_element?(view, "#story-pending-action")
    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert [player_action] = Enum.filter(timeline, &(&1.event_type == :player_action))
    assert has_element?(view, "#event-#{player_action.sequence}[data-event-type='player_action']")

    action_occurrences =
      render(view)
      |> Floki.parse_document!()
      |> Floki.find("#story-timeline [data-event-type='player_action']")
      |> Enum.count(&(Floki.text(&1) =~ action))

    assert action_occurrences == 1
  end

  test "completion announcements are localized and are not replayed on reconnect", %{conn: conn} do
    for {locale, completion} <- [
          {"es", "Tu turno se ha completado."},
          {"fr", "Votre tour est terminé."}
        ] do
      campaign = campaign_fixture()
      [session] = campaign.sessions
      assert {:ok, _preference} = Settings.set_ui_locale(locale)

      set_handler(fn _request ->
        {:ok,
         %{
           narration: "The lanterns glow along the harbor wall.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: nil
         }}
      end)

      {:ok, view, _html} = live(conn, session_path(campaign, session))
      refute has_element?(view, "#turn-announcement", "completado")
      refute has_element?(view, "#turn-announcement", "terminé")

      view
      |> form("#turn-composer", turn: %{input: "I light the harbor lanterns."})
      |> render_submit()

      assert wait_until(fn -> has_element?(view, "#turn-announcement", completion) end)
      assert has_element?(view, "#composer-turn-status", completion)

      {:ok, resumed, _html} = live(conn, session_path(campaign, session))
      refute has_element?(resumed, "#turn-announcement", "completado")
      refute has_element?(resumed, "#turn-announcement", "terminé")
    end
  end

  test "usage-limit recovery explains the shared pause and explicit resume in each locale", %{
    conn: conn
  } do
    test_pid = self()

    for {locale, guidance, resume_label, retry_label} <- [
          {"es",
           "ChatGPT informó de un límite de uso del plan, así que las solicitudes están pausadas en todas las sesiones. Revisa los ajustes de Uso, reanuda cuando creas que las solicitudes vuelven a estar disponibles y luego vuelve a intentar este turno guardado.",
           "Reanudar solicitudes", "Reintentar este turno"},
          {"fr",
           "ChatGPT a signalé une limite d’utilisation du forfait ; les requêtes sont donc suspendues dans toutes les sessions. Consultez les paramètres d’utilisation, reprenez les requêtes lorsque vous pensez qu’elles sont de nouveau disponibles, puis réessayez ce tour sauvegardé.",
           "Reprendre les requêtes", "Réessayer ce tour"}
        ] do
      campaign = campaign_fixture()
      [session] = campaign.sessions
      assert {:ok, _preference} = Settings.set_ui_locale(locale)

      set_handler(fn _request ->
        send(test_pid, :fake_usage_limit_call)
        {:error, :usage_limit}
      end)

      {:ok, view, _html} = live(conn, session_path(campaign, session))

      view
      |> form("#turn-composer", turn: %{input: "I check whether the road is open."})
      |> render_submit()

      assert wait_until(fn -> has_element?(view, "#turn-error", guidance) end)
      assert_receive :fake_usage_limit_call, 1_000

      assert has_element?(
               view,
               "#plan-usage-paused button[phx-click='resume-plan-usage']",
               resume_label
             )

      refute has_element?(view, "#turn-error button[phx-click='retry-turn']")
      assert render(view) =~ "I check whether the road is open."

      view
      |> element("#plan-usage-paused button[phx-click='resume-plan-usage']")
      |> render_click()

      refute has_element?(view, "#plan-usage-paused")
      assert has_element?(view, "#turn-error button[phx-click='retry-turn']", retry_label)
      refute_receive :fake_usage_limit_call, 50
    end
  end

  test "a plan limit blocks stale submissions in other sessions until a manual retry relatches it",
       %{
         conn: conn
       } do
    first_campaign = campaign_fixture(%{title: "First Plan-Limit Table"})
    [first_session] = first_campaign.sessions
    second_campaign = campaign_fixture(%{title: "Second Plan-Limit Table"})
    [second_session] = second_campaign.sessions
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    test_pid = self()

    set_handler(fn _request ->
      call_number = Agent.get_and_update(calls, fn count -> {count + 1, count + 1} end)
      send(test_pid, {:fake_plan_request, call_number})
      {:error, :usage_limit}
    end)

    {:ok, first_view, _html} = live(conn, session_path(first_campaign, first_session))
    {:ok, second_view, _html} = live(conn, session_path(second_campaign, second_session))

    first_view
    |> form("#turn-composer", turn: %{input: "I inspect the old road."})
    |> render_submit()

    assert_receive {:fake_plan_request, 1}, 1_000

    assert wait_until(fn ->
             case Play.public_current_turn(first_campaign.id) do
               %{failure_code: "usage_limit"} ->
                 has_element?(first_view, "#story-pending-action", "old road")

               _ ->
                 false
             end
           end)

    first_turn = Play.public_current_turn(first_campaign.id)
    assert first_turn.failure_code == "usage_limit"
    assert first_turn.player_input == "I inspect the old road."

    assert {:error, :plan_usage_paused} =
             Play.submit_turn(
               second_campaign.id,
               second_session.id,
               "stale-api-submit",
               "I should be blocked in the service too.",
               token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store),
               provider: fn _request ->
                 send(test_pid, :provider_called_while_paused)
                 {:error, :provider_error}
               end
             )

    assert {:error, :plan_usage_paused} =
             Play.retry_turn(first_turn.id,
               token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store),
               provider: fn _request ->
                 send(test_pid, :provider_called_while_paused)
                 {:error, :provider_error}
               end
             )

    second_view
    |> form("#turn-composer", turn: %{input: "I enter the second table."})
    |> render_submit()

    assert has_element?(second_view, "#plan-usage-paused")
    assert is_nil(Play.public_current_turn(second_campaign.id))
    refute_receive :provider_called_while_paused, 100
    refute_receive {:fake_plan_request, 2}, 100

    second_view
    |> element("#plan-usage-paused button[phx-click='resume-plan-usage']")
    |> render_click()

    refute Play.plan_usage_paused?(
             token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store)
           )

    refute_receive {:fake_plan_request, 2}, 100

    {:ok, resumed_view, _html} = live(conn, session_path(first_campaign, first_session))

    assert has_element?(
             resumed_view,
             "#turn-error button[phx-click='retry-turn']",
             "Retry this turn"
           )

    resumed_view
    |> element("#turn-error button[phx-click='retry-turn']")
    |> render_click()

    assert_receive {:fake_plan_request, 2}, 1_000
    assert wait_until(fn -> has_element?(resumed_view, "#plan-usage-paused") end)

    assert Play.plan_usage_paused?(
             token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store)
           )

    relatched_turn = Play.public_current_turn(first_campaign.id)
    assert relatched_turn.id == first_turn.id
    assert relatched_turn.player_input == first_turn.player_input
    assert relatched_turn.failure_code == "usage_limit"
    refute_receive {:fake_plan_request, 3}, 100
  end

  test "a generic provider failure does not latch the account-wide plan pause", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    set_handler(fn _request -> {:error, :provider_error} end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer", turn: %{input: "I ask about the distant lighthouse."})
    |> render_submit()

    assert wait_until(fn -> has_element?(view, "#turn-error") end)
    refute has_element?(view, "#plan-usage-paused")

    refute Play.plan_usage_paused?(
             token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store)
           )
  end

  test "a plan limit after a D20 keeps its result and requires explicit resume before retry", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, after_roll_attempts} = Agent.start_link(fn -> 0 end)
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)

      send(
        test_pid,
        {:fake_gm_call, self(), context["phase"], get_in(context, ["player_roll", "result"])}
      )

      if context["phase"] == "initial" do
        {:ok,
         %{
           narration: "The rope trembles above the lower floor.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: %{test: "Agility", difficulty: "Hard", target: 14}
         }}
      else
        attempt = Agent.get_and_update(after_roll_attempts, fn value -> {value, value + 1} end)

        if attempt == 0 do
          {:error, :usage_limit}
        else
          receive do
            :continue_retry -> :ok
          after
            5_000 -> flunk("retry resolution was not released")
          end

          {:ok,
           %{
             narration: "You reach the upper gallery with the rope still in hand.",
             dialogue: [],
             activities: [],
             public_changes: %{},
             private_changes: %{},
             character_updates: [],
             memory_update: %{public_summary: "", gm_private_summary: ""},
             roll_request: nil
           }}
        end
      end
    end)

    Application.put_env(:storyteller, :d20_roll_source, fn ->
      send(test_pid, :d20_source_used)
      17
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer", turn: %{input: "I climb the rope to the gallery."})
    |> render_submit()

    assert_receive {:fake_gm_call, _initial_provider, "initial", nil}, 1_000
    assert wait_until(fn -> has_element?(view, "#roll-panel", "Agility") end)

    view |> element("#roll-panel button[phx-click='roll-d20']") |> render_click()
    assert_receive :d20_source_used, 1_000
    assert_receive {:fake_gm_call, _failed_provider, "after_roll", 17}, 1_000

    assert wait_until(fn ->
             has_element?(view, "#turn-error", "D20 result: 17") and
               has_element?(view, "#turn-error", "Your D20 result is saved.") and
               has_element?(view, "#turn-announcement", "This turn needs attention") and
               has_element?(view, "#turn-announcement", "D20 result: 17")
           end)

    refute has_element?(view, "#turn-error[aria-live]")

    assert has_element?(
             view,
             "#turn-announcement",
             "ChatGPT reported a plan usage limit"
           )

    assert has_element?(
             view,
             "#turn-error",
             "Retry continues this same turn with that result."
           )

    assert Play.plan_usage_paused?(
             token_store: Application.fetch_env!(:storyteller, :plan_usage_token_store)
           )

    assert has_element?(view, "#plan-usage-paused")

    view
    |> element("#plan-usage-paused button[phx-click='resume-plan-usage']")
    |> render_click()

    refute has_element?(view, "#plan-usage-paused")
    refute_receive {:fake_gm_call, _, "after_roll", 17}, 50

    view |> element("#turn-error button[phx-click='retry-turn']") |> render_click()
    assert_receive {:fake_gm_call, retry_provider, "after_roll", 17}, 1_000
    assert has_element?(view, "#turn-announcement", "Retrying…")
    assert has_element?(view, "#turn-announcement", "D20 result: 17")
    send(retry_provider, :continue_retry)

    assert wait_until(fn ->
             has_element?(
               view,
               "#story-timeline",
               "You reach the upper gallery with the rope still in hand."
             )
           end)

    refute has_element?(view, "#turn-error")
    refute_receive :d20_source_used, 100

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_action)) == 1
    assert Enum.count(timeline, &(&1.event_type == :player_roll)) == 1
    assert Enum.find(timeline, &(&1.event_type == :player_roll)).payload["result"] == 17
  end

  test "failed turn and reconnect guidance survive a new LiveView connection", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      attempt = Agent.get_and_update(agent, fn attempt -> {attempt, attempt + 1} end)
      send(test_pid, {:fake_gm_attempt, attempt, context["phase"]})

      if attempt == 0 do
        {:error, :reauth_required}
      else
        {:ok,
         %{
           narration: "The saved action now moves the story forward.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: nil
         }}
      end
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer",
      turn: %{input: "I light the old signal beacon."}
    )
    |> render_submit()

    assert_receive {:fake_gm_attempt, 0, "initial"}, 1_000
    assert wait_until(fn -> has_element?(view, "#turn-error", "needs attention") end)

    assert has_element?(
             view,
             "#turn-error",
             "Your saved action is still unresolved. Retry continues this same turn."
           )

    assert has_element?(view, "#turn-error", "ChatGPT could not verify this account's permission")
    assert has_element?(view, "#turn-error a[href='/auth/connect']", "Reconnect account")
    assert has_element?(view, "#story-pending-action", "I light the old signal beacon.")

    {:ok, resumed, resumed_html} = live(conn, session_path(campaign, session))
    assert resumed_html =~ "Reconnect the account"
    assert has_element?(resumed, "#story-pending-action", "I light the old signal beacon.")
    assert has_element?(resumed, "#turn-error a[href='/auth/connect']", "Reconnect account")

    resumed |> element("#turn-error button[phx-click='retry-turn']") |> render_click()
    assert_receive {:fake_gm_attempt, 1, "initial"}, 1_000

    assert wait_until(fn ->
             render(resumed) =~ "The saved action now moves the story forward."
           end)

    assert render(resumed) =~ "The saved action now moves the story forward."
  end

  test "OAuth client configuration failure gives repair guidance without a reconnect action", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    set_handler(fn _request -> {:error, :authorization_configuration} end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer", turn: %{input: "I ask the keeper about the locked cellar."})
    |> render_submit()

    guidance =
      "ChatGPT could not authorize Storyteller to use this account's plan. Check the selected account and workspace, then verify Storyteller's client and plan-usage grant configuration before retrying."

    assert wait_until(fn -> has_element?(view, "#turn-error", guidance) end)
    refute has_element?(view, "#turn-error a[href='/auth/connect']")
    assert has_element?(view, "#turn-error button[phx-click='retry-turn']")
  end

  test "campaign story pages reach older events and keep them through live refreshes", %{
    conn: conn
  } do
    campaign = campaign_fixture()
    [earlier_session] = campaign.sessions

    {:ok, earlier_turn} =
      Play.submit_turn(
        campaign.id,
        earlier_session.id,
        "earlier-history-turn",
        "Seed earlier history"
      )

    Repo.update_all(from(turn in Turn, where: turn.id == ^earlier_turn.id),
      set: [status: :completed]
    )

    {:ok, session} = Storyteller.Campaigns.start_session(campaign)
    {:ok, _state} = Play.initialize_campaign(campaign)

    {:ok, turn} =
      Play.submit_turn(campaign.id, session.id, "history-window-turn", "Seed long history")

    Repo.update_all(from(turn in Turn, where: turn.id == ^turn.id), set: [status: :completed])

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    events =
      Enum.map(1..1_101, fn sequence ->
        %{
          campaign_id: campaign.id,
          session_id: if(sequence <= 551, do: earlier_session.id, else: session.id),
          turn_id: if(sequence <= 551, do: earlier_turn.id, else: turn.id),
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "History marker #{sequence}"},
          inserted_at: now
        }
      end)

    assert {1_101, nil} = Repo.insert_all(Event, events)

    {:ok, timeline} = Play.public_timeline(campaign.id)
    assert length(timeline) == 500
    assert hd(timeline).payload["text"] == "History marker 602"
    assert List.last(timeline).payload["text"] == "History marker 1101"

    {:ok, view, _html} = live(conn, session_path(campaign, session))
    assert has_element?(view, "#load-earlier-story", "Load earlier story")
    assert has_element?(view, "#event-602", "History marker 602")
    assert has_element?(view, "#event-1101", "History marker 1101")
    refute has_element?(view, "#event-601")

    event_ids = fn html ->
      html
      |> Floki.parse_document!()
      |> Floki.find("#story-timeline li[id]")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))
      |> Enum.filter(&String.starts_with?(&1, "event-"))
      |> Enum.map(&(String.replace_prefix(&1, "event-", "") |> String.to_integer()))
    end

    assert event_ids.(render(view)) == Enum.to_list(602..1_101)

    live_ids = fn html ->
      html
      |> Floki.parse_document!()
      |> Floki.find("#story-live-timeline li[id]")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))
      |> Enum.map(&(String.replace_prefix(&1, "event-", "") |> String.to_integer()))
    end

    assert live_ids.(render(view)) == Enum.to_list(1_082..1_101)

    view |> element("#load-earlier-story") |> render_click()
    assert has_element?(view, "#event-102", "History marker 102")
    refute has_element?(view, "#event-101")
    assert event_ids.(render(view)) == Enum.to_list(102..1_101)
    assert live_ids.(render(view)) == Enum.to_list(1_082..1_101)
    assert has_element?(view, "#event-102", "Earlier session")

    Repo.insert!(
      Event.changeset(%Event{}, %{
        campaign_id: campaign.id,
        session_id: session.id,
        turn_id: turn.id,
        sequence: 1_102,
        event_type: :gm_narration,
        visibility: :public,
        payload: %{"text" => "A new scene arrives."}
      })
    )

    send(view.pid, :refresh_turn)
    assert wait_until(fn -> has_element?(view, "#event-1102", "A new scene arrives.") end)
    assert has_element?(view, "#event-102", "History marker 102")
    assert event_ids.(render(view)) == Enum.to_list(102..1_102)
    assert live_ids.(render(view)) == Enum.to_list(1_083..1_102)
    assert has_element?(view, "#load-earlier-story")

    view |> element("#load-earlier-story") |> render_click()
    assert has_element?(view, "#event-1", "History marker 1")
    assert has_element?(view, "#event-1", "Earlier session")
    refute has_element?(view, "#load-earlier-story")
    assert event_ids.(render(view)) == Enum.to_list(1..1_102)

    before_forged_load = event_ids.(render(view))
    render_click(view, "load-earlier-story", %{})
    assert event_ids.(render(view)) == before_forged_load
  end

  test "older campaign story controls use the selected interface locale", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)
    {:ok, turn} = Play.submit_turn(campaign.id, session.id, "localized-history", "Seed history")

    Repo.update_all(from(turn in Turn, where: turn.id == ^turn.id), set: [status: :completed])

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    events =
      Enum.map(1..501, fn sequence ->
        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: turn.id,
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "Localized marker #{sequence}"},
          inserted_at: now
        }
      end)

    assert {501, nil} = Repo.insert_all(Event, events)

    for {locale, button, history_label} <- [
          {"es", "Cargar relato anterior", "Relato anterior de la campaña"},
          {"fr", "Charger le récit précédent", "Récit précédent de la campagne"}
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      {:ok, view, _html} = live(conn, session_path(campaign, session))

      assert has_element?(view, "#load-earlier-story", button)
      assert has_element?(view, "#story-history[aria-label='#{history_label}']")
    end
  end

  defp session_path(campaign, session),
    do: ~p"/campaigns/#{campaign.id}/sessions/#{session.id}"

  defp seed_action_items(campaign_id, player_properties \\ %{}) do
    state = Repo.get_by!(State, campaign_id: campaign_id)

    public_inventory = [
      %{
        "id" => "player-sunstone",
        "name" => "Sunstone",
        "quantity" => 1,
        "owner_id" => "player",
        "visibility" => "public",
        "properties" => player_properties
      },
      %{
        "id" => "party-lantern",
        "name" => "Copper lantern",
        "quantity" => 1,
        "owner_id" => "party",
        "visibility" => "public",
        "properties" => %{}
      },
      %{
        "id" => "keeper-key",
        "name" => "Keeper's key",
        "quantity" => 1,
        "owner_id" => "npc:keeper",
        "visibility" => "public",
        "properties" => %{}
      }
    ]

    private_inventory = [
      %{
        "id" => "hidden-relic",
        "name" => "Hidden obsidian relic",
        "quantity" => 1,
        "owner_id" => "player",
        "visibility" => "gm_private",
        "properties" => %{}
      }
    ]

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", public_inventory),
        gm_private_state: Map.put(state.gm_private_state, "inventory", private_inventory)
      })
    )
  end

  defp set_handler(handler) do
    Application.put_env(:storyteller, :session_live_test_handler, handler)
  end

  defp provider_context(request) do
    request.input
    |> hd()
    |> Map.fetch!(:content)
    |> hd()
    |> Map.fetch!(:text)
    |> Jason.decode!()
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

  defp restore_env(key, :not_configured), do: Application.delete_env(:storyteller, key)
  defp restore_env(key, value), do: Application.put_env(:storyteller, key, value)
end
