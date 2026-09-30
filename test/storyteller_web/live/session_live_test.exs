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
  alias Storyteller.Play.{Event, State, Turn}
  alias Storyteller.Repo
  alias Storyteller.Settings
  alias StorytellerWeb.SessionLiveTest.FakeProvider

  setup do
    previous_provider = Application.get_env(:storyteller, :gm_provider, :not_configured)

    previous_handler =
      Application.get_env(:storyteller, :session_live_test_handler, :not_configured)

    previous_roll_source = Application.get_env(:storyteller, :d20_roll_source, :not_configured)

    Application.put_env(:storyteller, :gm_provider, FakeProvider)

    on_exit(fn ->
      restore_env(:gm_provider, previous_provider)
      restore_env(:session_live_test_handler, previous_handler)
      restore_env(:d20_roll_source, previous_roll_source)
    end)

    :ok
  end

  test "submitting an action updates the public world, NPC activity, and attributed timeline", %{
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
    assert html =~ "The western road"
    assert has_element?(view, "#current-place", "The western road")
    assert has_element?(view, "#world-location", "The western road")
    assert has_element?(view, "#current-place", "Rhea Vale")
    assert html =~ "09:20"
    assert html =~ "A light rain begins"
    assert html =~ "Day 3, June 10"
    refute html =~ "This stays private"

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

  test "player character fact updates appear on the board with a reasoned timeline entry", %{
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
         panel_changes: %{},
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
             "#story-timeline[aria-live='polite'][aria-relevant='additions'][aria-atomic='false']"
           )

    assert has_element?(view, "#empty-timeline")

    view
    |> form("#turn-composer", turn: %{input: "I rest through the afternoon."})
    |> render_submit()

    assert wait_until(fn -> render(view) =~ "Rested" end)
    html = render(view)
    assert html =~ "Character details updated"
    assert html =~ "Reason: The player rests through the afternoon."

    assert has_element?(
             view,
             "#story-timeline[aria-live='polite'][aria-relevant='additions'][aria-atomic='false']"
           )

    assert has_element?(view, "#story-timeline", "Health")

    {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.visible_facts["Health"] == "Rested"
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

      view |> element(party_button) |> render_click()
      assert render(view) =~ "I listen at the door.\n#{sentence}\n#{party_sentence}"

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

  test "D20 is only generated after the validated roll request is clicked", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, context})

      if context["phase"] == "initial" do
        {:ok,
         %{
           narration: "The narrow bridge sways over the ravine.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: %{test: "Agility", difficulty: "Hard"}
         }}
      else
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
    refute has_element?(view, "button[phx-click='roll-d20']")

    view
    |> form("#turn-composer",
      turn: %{input: "I cross the bridge carefully."}
    )
    |> render_submit()

    assert_receive {:fake_gm_call, %{"phase" => "initial"}}, 1_000
    assert wait_until(fn -> has_element?(view, "#roll-panel", "Agility") end)
    refute_receive :d20_source_used, 100

    view |> element("#roll-panel button[phx-click='roll-d20']") |> render_click()
    assert_receive :d20_source_used, 1_000
    assert_receive {:fake_gm_call, %{"phase" => "after_roll"}}, 1_000
    assert wait_until(fn -> render(view) =~ "You steady your footing and reach the far side." end)

    html = render(view)
    assert html =~ "D20 result: 17"
    assert html =~ "You steady your footing and reach the far side."
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
    assert has_element?(view, "#turn-error a[href='/auth/connect']", "Reconnect account")
    assert render(view) =~ "I light the old signal beacon."

    {:ok, resumed, resumed_html} = live(conn, session_path(campaign, session))
    assert resumed_html =~ "needs you to reconnect"
    assert resumed_html =~ "I light the old signal beacon."
    assert has_element?(resumed, "#turn-error a[href='/auth/connect']", "Reconnect account")

    resumed |> element("#turn-error button[phx-click='retry-turn']") |> render_click()
    assert_receive {:fake_gm_attempt, 1, "initial"}, 1_000

    assert wait_until(fn ->
             render(resumed) =~ "The saved action now moves the story forward."
           end)

    assert render(resumed) =~ "The saved action now moves the story forward."
  end

  test "the timeline window keeps recent campaign events in chronological order", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    {:ok, turn} =
      Play.submit_turn(campaign.id, session.id, "history-window-turn", "Seed long history")

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
          payload: %{"text" => "History marker #{sequence}"},
          inserted_at: now
        }
      end)

    assert {501, nil} = Repo.insert_all(Event, events)

    {:ok, timeline} = Play.public_timeline(campaign.id)
    assert length(timeline) == 500
    assert hd(timeline).payload["text"] == "History marker 2"
    assert List.last(timeline).payload["text"] == "History marker 501"

    {:ok, _view, html} = live(conn, session_path(campaign, session))
    document = Floki.parse_document!(html)
    first_event = document |> Floki.find("#event-1") |> Floki.text()
    last_event = document |> Floki.find("#event-500") |> Floki.text()

    event_texts =
      document
      |> Floki.find("#story-timeline .story-entry > p")
      |> Enum.map(&Floki.text/1)

    assert first_event =~ "History marker 2"
    assert last_event =~ "History marker 501"
    refute "History marker 1" in event_texts
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
