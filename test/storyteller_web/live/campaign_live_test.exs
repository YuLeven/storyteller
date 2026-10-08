defmodule StorytellerWeb.CampaignLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures
  import Ecto.Query, only: [from: 2]

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Play
  alias Storyteller.Play.Character
  alias Storyteller.Play.Turn
  alias Storyteller.Repo

  setup do
    previous_provider = Application.get_env(:storyteller, :gm_provider, :not_configured)
    Application.put_env(:storyteller, :gm_provider, &test_opening_scene_response/1)

    on_exit(fn ->
      case previous_provider do
        :not_configured -> Application.delete_env(:storyteller, :gm_provider)
        provider -> Application.put_env(:storyteller, :gm_provider, provider)
      end
    end)

    :ok
  end

  test "campaign list keeps two stories in separate cards and links to the right sessions", %{
    conn: conn
  } do
    first =
      campaign_fixture(%{
        title: "Lantern Coast",
        premise: "A ferry light vanishes in a storm.",
        player_character_name: "Sera Vale",
        player_character: "A ferry keeper who reads storm clouds."
      })

    second =
      campaign_fixture(%{
        title: "Copper Archive",
        premise: "A map is missing from the city collection.",
        player_character_name: "Niko Reed",
        player_character: "An archivist with a perfect memory."
      })

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Campaigns"
    assert html =~ "Lantern Coast"
    assert html =~ "Copper Archive"
    assert has_element?(view, "#campaign-persistence-import summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence-import[open]")
    assert has_element?(view, "#campaign-backup-form")

    first_card =
      html |> Floki.parse_document!() |> Floki.find("#campaign-#{first.id}") |> Floki.text()

    second_card =
      html |> Floki.parse_document!() |> Floki.find("#campaign-#{second.id}") |> Floki.text()

    assert first_card =~ "A ferry light vanishes in a storm."
    assert first_card =~ "Character: Sera Vale"
    refute first_card =~ "A ferry keeper who reads storm clouds."
    refute first_card =~ "A map is missing from the city collection."
    assert second_card =~ "A map is missing from the city collection."
    assert second_card =~ "Character: Niko Reed"
    refute second_card =~ "A ferry light vanishes in a storm."

    first_session = hd(first.sessions)
    second_session = hd(second.sessions)

    document = Floki.parse_document!(html)
    first_links = document |> Floki.find("#campaign-#{first.id} a") |> Floki.attribute("href")
    second_links = document |> Floki.find("#campaign-#{second.id} a") |> Floki.attribute("href")

    assert ~p"/campaigns/#{first.id}/sessions/#{first_session.id}" in first_links
    assert ~p"/campaigns/#{second.id}/sessions/#{second_session.id}" in second_links
  end

  test "empty campaign library keeps backup restore available in its collapsed persistence section",
       %{
         conn: conn
       } do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Your next story starts here"
    assert has_element?(view, "#campaign-persistence-import summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence-import[open]")
    assert has_element?(view, "#campaign-backup-form")
    refute html =~ "Download sensitive backup"
  end

  test "campaign setup is reviewed before creation and its first session is resumable", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Blue Lantern",
      premise: "A signal appears on the cliffs after a century of silence.",
      setting: "A fictional coastal city",
      tone: "Patient and hopeful",
      narration_language: "French"
    }

    character = %{
      player_character_name: "Noa Marin",
      player_character: "A lighthouse keeper who listens for bells in fog."
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, character), "continue")
    submit_wizard_step(view, Map.merge(story, character), "continue")
    review_html = submit_wizard_step(view, Map.merge(story, character), "continue")

    assert review_html =~ "Review your campaign"
    assert review_html =~ "The Blue Lantern"
    assert review_html =~ "Noa Marin"
    assert review_html =~ "Character description"
    assert review_html =~ "A lighthouse keeper who listens for bells in fog."
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert campaign.title == "The Blue Lantern"
    assert campaign.player_character_name == "Noa Marin"
    assert campaign.player_character == "A lighthouse keeper who listens for bells in fog."
    assert [%{title: "Session 1", status: :active}] = campaign.sessions

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.name == "Noa Marin"
    assert player.visible_facts["description"] == campaign.player_character

    assert_redirect(view, ~p"/campaigns/#{campaign.id}")
  end

  test "a campaign from setup opens, resolves a player move, and continues with its story and inventory",
       %{conn: conn} do
    test_pid = self()
    previous_provider = Application.get_env(:storyteller, :gm_provider)
    player_action = "Use a moonpetal draught to soothe the blighted sapling."

    time_passage_input =
      "Let a few days pass, stopping at the next meaningful decision I need to make."

    later_action = "Check the remedy basket before the neighbor arrives."

    Application.put_env(:storyteller, :gm_provider, fn request ->
      context = decode_request(request)

      player_items = get_in(context, ["inventory", "player_visible"]) || []

      send(test_pid, {
        :campaign_journey_request,
        context["interaction_mode"],
        context["player_action"],
        player_items
      })

      if context["interaction_mode"] == "opening_scene" do
        send(test_pid, {:campaign_opening_context, context})
      end

      if context["interaction_mode"] == "time_passage" do
        send(test_pid, {:campaign_time_passage_context, context})
      end

      if context["interaction_mode"] == "action" and context["player_action"] == later_action do
        send(test_pid, {:campaign_later_action_context, context})
      end

      if context["interaction_mode"] == "opening_scene" do
        test_opening_scene_response(request)
      else
        if context["interaction_mode"] == "time_passage" do
          {:ok,
           %{
             narration:
               "Three days pass. The orchard stirs under a pale morning sky, and the next choice is yours.",
             public_changes: %{
               "date" => "The fourth morning of frost",
               "time" => "Morning"
             },
             time_advance_minutes: 4_320,
             memory_update: %{
               public_summary: "Three days pass at the orchard.",
               gm_private_summary: ""
             }
           }}
        else
          if context["player_action"] == player_action do
            item = Enum.find(player_items, &(&1["name"] == "Moonpetal draught"))

            if item do
              {:ok,
               %{
                 narration:
                   "The draught calms the trembling leaves. One vial remains for the next difficult night.",
                 memory_update: %{public_summary: "", gm_private_summary: ""},
                 inventory_changes: [
                   %{
                     "type" => "consume",
                     "item_id" => item["id"],
                     "quantity" => 1,
                     "reason" => "One vial is used to soothe the orchard's blighted sapling."
                   }
                 ]
               }}
            else
              {:error, :test_inventory_missing}
            end
          else
            {:ok,
             %{
               narration: "One vial remains in the basket as the neighbor's lantern appears.",
               memory_update: %{public_summary: "", gm_private_summary: ""}
             }}
          end
        end
      end
    end)

    on_exit(fn ->
      case previous_provider do
        nil -> Application.delete_env(:storyteller, :gm_provider)
        provider -> Application.put_env(:storyteller, :gm_provider, provider)
      end
    end)

    {:ok, wizard, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Moonpetal Orchard",
      premise: "A blight has silvered the leaves before the harvest.",
      setting: "A small orchard on a fictional northern coast",
      tone: "Gentle, curious, and grounded",
      narration_language: "English"
    }

    player = %{
      player_character_name: "Mara Vale",
      player_character: "An attentive orchard keeper who notices small changes."
    }

    opening = %{
      starting_location: "Moonpetal orchard",
      starting_date: "The first evening of frost",
      world_time: "Blue hour",
      weather: "Cool mist"
    }

    submit_wizard_step(wizard, story, "continue")
    submit_wizard_step(wizard, Map.merge(story, player), "continue")
    wizard |> element("button[phx-click=add-starting-item]") |> render_click()

    starting_item = %{
      "0" => %{
        name: "Moonpetal draught",
        quantity: "2",
        unit: "vials",
        category: "Remedy",
        description: "A clear infusion made from the orchard's night-blooming petals."
      }
    }

    opening_attrs =
      story
      |> Map.merge(player)
      |> Map.merge(opening)
      |> Map.put(:inventory, starting_item)

    submit_wizard_step(wizard, opening_attrs, "continue")
    submit_wizard_step(wizard, opening_attrs, "continue")
    assert render(wizard) =~ "Review your campaign"
    assert Campaigns.list_campaigns() == []

    wizard |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert campaign.title == "The Moonpetal Orchard"
    [first_session] = campaign.sessions
    assert_redirect(wizard, ~p"/campaigns/#{campaign.id}")

    {:ok, campaign_view, campaign_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert campaign_html =~ "Resume current session"

    assert has_element?(
             campaign_view,
             "a[href='/campaigns/#{campaign.id}/sessions/#{first_session.id}']"
           )

    {:ok, first_view, _opening_html} = open_session(conn, campaign, first_session)
    assert_receive {:campaign_journey_request, "opening_scene", _, opening_items}, 1_000
    assert_receive {:campaign_opening_context, first_opening_context}, 1_000
    assert [%{"name" => "Moonpetal draught", "quantity" => 2}] = opening_items
    assert first_opening_context["world"]["public"]["date"] == "The first evening of frost"
    assert first_opening_context["world"]["public"]["time"] == "Blue hour"

    assert wait_until(fn ->
             has_element?(
               first_view,
               "#story-timeline",
               "The scene takes shape, and a clear choice is yours."
             )
           end)

    assert has_element?(first_view, "#current-place", "Moonpetal orchard")
    assert has_element?(first_view, "#world-date", "The first evening of frost")
    assert has_element?(first_view, "#world-time", "Blue hour")
    assert has_element?(first_view, "#world-weather", "Cool mist")
    assert has_element?(first_view, "#world-location", "Moonpetal orchard")
    assert {:ok, opening_projection} = Play.public_projection(campaign.id)
    [starting_draught] = opening_projection.inventory
    starting_draught_id = starting_draught["id"]
    assert has_element?(first_view, "#inventory-item-#{starting_draught_id}", "2")

    first_view
    |> form("#turn-composer", turn: %{input: player_action})
    |> render_submit()

    assert_receive {
                     :campaign_journey_request,
                     "action",
                     ^player_action,
                     [%{"id" => ^starting_draught_id, "quantity" => 2}]
                   },
                   1_000

    assert wait_until(fn ->
             has_element?(
               first_view,
               "#story-timeline",
               "The draught calms the trembling leaves. One vial remains for the next difficult night."
             )
           end),
           "player turn did not complete: #{inspect(Play.public_current_turn(campaign.id))}"

    assert has_element?(first_view, "#story-timeline", player_action)
    assert has_element?(first_view, "#inventory-item-#{starting_draught_id}", "1")
    assert is_nil(Play.public_current_turn(campaign.id))

    player_before_time_passage =
      Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    first_view
    |> element("#turn-composer button[phx-value-mode='time_passage']")
    |> render_click()

    first_view
    |> element("#turn-composer button[phx-value-nudge_id='few-days']")
    |> render_click()

    assert render(first_view) =~ time_passage_input

    first_view
    |> form("#turn-composer")
    |> render_submit()

    assert_receive {
                     :campaign_journey_request,
                     "time_passage",
                     ^time_passage_input,
                     [%{"id" => ^starting_draught_id, "quantity" => 1}]
                   },
                   1_000

    assert_receive {:campaign_time_passage_context, time_passage_context}, 1_000
    assert time_passage_context["world"]["public"]["date"] == "The first evening of frost"
    assert time_passage_context["elapsed_world_clock"]["total_minutes"] == 0

    assert wait_until(fn ->
             has_element?(
               first_view,
               "#story-timeline",
               "Three days pass. The orchard stirs under a pale morning sky, and the next choice is yours."
             )
           end)

    assert has_element?(first_view, "#world-date", "The fourth morning of frost")
    assert has_element?(first_view, "#world-time", "Morning")

    after_time_passage = Repo.get_by!(Storyteller.Play.State, campaign_id: campaign.id)
    assert after_time_passage.public_state["date"] == "The fourth morning of frost"
    assert after_time_passage.public_state["time"] == "Morning"
    assert after_time_passage.elapsed_world_minutes == 4_320
    assert after_time_passage.elapsed_world_anchor_minutes == 4_320

    player_after_time_passage =
      Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    assert player_after_time_passage.current_place_id ==
             player_before_time_passage.current_place_id

    assert player_after_time_passage.visible_facts == player_before_time_passage.visible_facts

    assert player_after_time_passage.visible_activity ==
             player_before_time_passage.visible_activity

    assert {:ok, first_session_timeline} = Play.public_timeline(campaign.id)
    time_passage_events = Enum.filter(first_session_timeline, &(&1.event_type == :time_passage))
    assert length(time_passage_events) == 1

    assert time_passage_events
           |> hd()
           |> Map.fetch!(:payload)
           |> Map.fetch!("text") == time_passage_input

    time_passage_turn_id = time_passage_events |> hd() |> Map.fetch!(:turn_id)

    time_passage_turn_events =
      Enum.filter(first_session_timeline, &(&1.turn_id == time_passage_turn_id))

    assert Enum.count(time_passage_turn_events, &(&1.event_type == :time_passage)) == 1
    assert Enum.count(time_passage_turn_events, &(&1.event_type == :gm_narration)) == 1

    refute Enum.any?(
             time_passage_turn_events,
             &(&1.event_type in [:player_action, :roll_request, :player_roll])
           )

    first_session_turn_intents =
      Repo.all(
        from turn in Turn,
          where: turn.campaign_id == ^campaign.id,
          select: turn.intent
      )

    assert Enum.frequencies(first_session_turn_intents) == %{
             opening_scene: 1,
             action: 1,
             time_passage: 1
           }

    {:ok, later_campaign_view, _campaign_html} = live(conn, ~p"/campaigns/#{campaign.id}")

    later_campaign_view
    |> form("form[phx-submit=start-session]", session: %{title: "The Second Frost"})
    |> render_submit()

    refreshed_campaign = Campaigns.get_campaign!(campaign.id)
    first_session = Enum.find(refreshed_campaign.sessions, &(&1.id == first_session.id))
    later_session = Enum.find(refreshed_campaign.sessions, &(&1.title == "The Second Frost"))
    assert first_session.status == :completed
    assert later_session.status == :active

    assert_redirect(
      later_campaign_view,
      ~p"/campaigns/#{campaign.id}/sessions/#{later_session.id}"
    )

    {:ok, later_view, _later_html} = open_session(conn, campaign, later_session)

    assert wait_until(fn ->
             has_element?(
               later_view,
               "#story-timeline",
               "The scene takes shape, and a clear choice is yours."
             ) and
               has_element?(
                 later_view,
                 "#story-timeline",
                 "The draught calms the trembling leaves. One vial remains for the next difficult night."
               ) and
               has_element?(
                 later_view,
                 "#story-timeline",
                 "Three days pass. The orchard stirs under a pale morning sky, and the next choice is yours."
               )
           end)

    assert has_element?(later_view, "#story-timeline", player_action)
    assert has_element?(later_view, "#current-place", "Moonpetal orchard")
    assert has_element?(later_view, "#world-date", "The fourth morning of frost")
    assert has_element?(later_view, "#world-time", "Morning")
    assert has_element?(later_view, "#story-timeline", time_passage_input)
    assert has_element?(later_view, "#story-timeline", "Three days pass.")
    assert has_element?(later_view, "#world-weather", "Cool mist")
    assert has_element?(later_view, "#world-location", "Moonpetal orchard")
    assert has_element?(later_view, "#inventory-item-#{starting_draught_id}", "1")
    assert is_nil(Play.public_current_turn(campaign.id))
    assert has_element?(later_view, "#turn-input:not([disabled])")

    later_view
    |> form("#turn-composer", turn: %{input: later_action})
    |> render_submit()

    assert_receive {
                     :campaign_journey_request,
                     "action",
                     ^later_action,
                     [%{"id" => ^starting_draught_id, "quantity" => 1}]
                   },
                   1_000

    assert_receive {:campaign_later_action_context, later_action_context}, 1_000
    assert later_action_context["world"]["public"]["date"] == "The fourth morning of frost"
    assert later_action_context["world"]["public"]["time"] == "Morning"
    assert later_action_context["elapsed_world_clock"]["total_minutes"] == 4_320
    assert later_action_context["elapsed_world_clock"]["anchor_minutes"] == 4_320
    assert later_action_context["elapsed_world_clock"]["minutes_since_anchor"] == 0

    assert later_action_context["elapsed_world_clock"]["anchor"] == %{
             "date" => "The fourth morning of frost",
             "time" => "Morning"
           }

    passage_history_event =
      Enum.find(later_action_context["history"], fn event ->
        event["event_type"] == "time_passage" and event["session_id"] == first_session.id
      end)

    assert passage_history_event["payload"]["text"] == time_passage_input

    assert Enum.any?(later_action_context["history"], fn event ->
             event["payload"]["text"] ==
               "Three days pass. The orchard stirs under a pale morning sky, and the next choice is yours."
           end)

    assert wait_until(fn ->
             has_element?(
               later_view,
               "#story-timeline",
               "One vial remains in the basket as the neighbor's lantern appears."
             )
           end)

    assert has_element?(later_view, "#story-timeline", later_action)
    assert has_element?(later_view, "#inventory-item-#{starting_draught_id}", "1")
    assert is_nil(Play.public_current_turn(campaign.id))
  end

  test "a newly created campaign carries a player-clicked D20 action through resolution", %{
    conn: conn
  } do
    test_pid = self()
    previous_provider = Application.get_env(:storyteller, :gm_provider)
    previous_roll_source = Application.get_env(:storyteller, :d20_roll_source, :not_configured)
    player_action = "Cross the rain-slick bridge while the wind is rising."

    Application.put_env(:storyteller, :gm_provider, fn request ->
      context = decode_request(request)

      if context["interaction_mode"] == "opening_scene" do
        send(test_pid, {:d20_journey_opening_context, context})
        test_opening_scene_response(request)
      else
        send(test_pid, {:d20_journey_gm_call, self(), context})

        case context["phase"] do
          "initial" ->
            receive do
              :continue_initial_resolution ->
                {:ok,
                 %{
                   narration: "The narrow bridge sways above the ravine.",
                   memory_update: %{
                     public_summary: "The bridge is exposed to strong wind.",
                     gm_private_summary: ""
                   },
                   roll_request: %{test: "Balance", difficulty: "Hard", target: 14}
                 }}
            after
              5_000 ->
                flunk("initial D20 resolution was not released")
            end

          "after_roll" ->
            receive do
              :continue_after_roll ->
                {:ok,
                 %{
                   narration: "You brace against the gust and cross safely.",
                   memory_update: %{
                     public_summary: "The crossing is complete.",
                     gm_private_summary: ""
                   },
                   roll_request: nil
                 }}
            after
              5_000 ->
                flunk("after-roll D20 resolution was not released")
            end
        end
      end
    end)

    Application.put_env(:storyteller, :d20_roll_source, fn ->
      send(test_pid, :d20_source_used)
      17
    end)

    on_exit(fn ->
      case previous_provider do
        nil -> Application.delete_env(:storyteller, :gm_provider)
        provider -> Application.put_env(:storyteller, :gm_provider, provider)
      end

      case previous_roll_source do
        :not_configured -> Application.delete_env(:storyteller, :d20_roll_source)
        roll_source -> Application.put_env(:storyteller, :d20_roll_source, roll_source)
      end
    end)

    {:ok, wizard, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Bellglass Crossing",
      premise: "A storm is rising while a sealed signal waits on the far bank.",
      setting: "A fictional mountain observatory above a narrow ravine",
      tone: "Tense, grounded, and quietly hopeful",
      narration_language: "English"
    }

    player = %{
      player_character_name: "Mira Quill",
      player_character: "A careful courier carrying a sealed observatory message."
    }

    opening = %{
      starting_location: "The Bellglass Bridge",
      starting_date: "First night of the storm season",
      world_time: "Late evening",
      weather: "Driving rain"
    }

    submit_wizard_step(wizard, story, "continue")
    submit_wizard_step(wizard, Map.merge(story, player), "continue")
    setup_attrs = story |> Map.merge(player) |> Map.merge(opening)
    submit_wizard_step(wizard, setup_attrs, "continue")
    assert submit_wizard_step(wizard, setup_attrs, "continue") =~ "Review your campaign"

    wizard |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    [session] = campaign.sessions
    assert campaign.title == "The Bellglass Crossing"
    assert campaign.player_character_name == "Mira Quill"

    {:ok, view, _html} = open_session(conn, campaign, session)
    assert_receive {:d20_journey_opening_context, opening_context}, 1_000
    assert opening_context["interaction_mode"] == "opening_scene"
    assert has_element?(view, "#current-place", "The Bellglass Bridge")

    assert wait_until(fn ->
             has_element?(
               view,
               "#story-timeline",
               "The scene takes shape, and a clear choice is yours."
             )
           end)

    view
    |> form("#turn-composer", turn: %{input: player_action})
    |> render_submit()

    assert_receive {
                     :d20_journey_gm_call,
                     initial_provider,
                     %{
                       "phase" => "initial",
                       "interaction_mode" => "action",
                       "player_action" => ^player_action
                     }
                   },
                   1_000

    assert has_element?(view, "#story-pending-action", player_action)
    assert has_element?(view, "#turn-input[disabled]")
    refute has_element?(view, "#story-timeline [data-event-type='player_action']")
    refute_receive :d20_source_used, 100

    send(initial_provider, :continue_initial_resolution)

    assert wait_until(fn -> has_element?(view, "#roll-panel", "Balance") end)
    assert has_element?(view, "#roll-panel", "Difficulty: Hard")
    assert has_element?(view, "#roll-panel", "Target: 14")
    assert has_element?(view, "#story-timeline", player_action)
    assert has_element?(view, "#story-timeline", "The narrow bridge sways above the ravine.")
    assert has_element?(view, "#roll-panel button[phx-click='roll-d20']")
    refute_receive :d20_source_used, 100

    view |> element("#roll-panel button[phx-click='roll-d20']") |> render_click()

    assert_receive :d20_source_used, 1_000

    assert_receive {
                     :d20_journey_gm_call,
                     after_roll_provider,
                     %{
                       "phase" => "after_roll",
                       "player_roll" => %{"result" => 17}
                     }
                   },
                   1_000

    assert has_element?(view, "#turn-announcement", "D20 result: 17")
    assert has_element?(view, "#story-timeline", player_action)

    action_occurrences_while_resolving =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#story-timeline [data-event-type='player_action']")
      |> Enum.count(&(Floki.text(&1) =~ player_action))

    assert action_occurrences_while_resolving == 1

    send(after_roll_provider, :continue_after_roll)

    assert wait_until(fn ->
             has_element?(view, "#story-timeline", "You brace against the gust and cross safely.")
           end)

    assert has_element?(view, "#turn-announcement", "Your turn is complete.")
    assert has_element?(view, "#story-timeline", "D20 result: 17")
    assert is_nil(Play.public_current_turn(campaign.id))

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    action_event = Enum.find(timeline, &(&1.event_type == :player_action))
    action_turn_events = Enum.filter(timeline, &(&1.turn_id == action_event.turn_id))
    assert Enum.count(action_turn_events, &(&1.event_type == :player_action)) == 1
    assert Enum.count(action_turn_events, &(&1.event_type == :roll_request)) == 1
    assert Enum.count(action_turn_events, &(&1.event_type == :player_roll)) == 1
    assert Enum.count(action_turn_events, &(&1.event_type == :gm_narration)) == 2
    assert Enum.find(action_turn_events, &(&1.event_type == :player_roll)).payload["result"] == 17
    assert Repo.get!(Turn, action_event.turn_id).status == :completed
    refute_receive {:d20_journey_gm_call, _, _}, 100
    refute_receive :d20_source_used, 100
  end

  test "campaign review shows every GM character field before persistence and keeps private guidance off the board",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Saffron Kitchen",
      premise: "A sealed recipe arrives with a warning.",
      setting: "A riverside vineyard in southern France",
      tone: "Warm, intimate, and mysterious",
      narration_language: "English"
    }

    player_character = %{
      player_character_name: "Luc Moreau",
      player_character: "A patient cellar keeper."
    }

    opening = %{
      starting_location: "The west cellar",
      starting_date: "Second day of harvest",
      world_time: "Late evening",
      weather: "Cool mist from the river"
    }

    starting_inventory = %{
      inventory: %{
        "0" => %{
          name: "Reserve bottles",
          quantity: "3",
          unit: "bottles",
          category: "wine",
          description: "Kept for the autumn gathering."
        }
      }
    }

    gm_character = %{
      gm_characters: %{
        "0" => %{
          name: "Marcel",
          starting_place: "The river bodega",
          active_duty_name: "Tend the fermentation vats",
          active_duty_duration_minutes: "75",
          visible_facts_text: "A warm, observant beaver cook from Lyon.",
          private_notes: "Secret: he altered the cellar ledger.",
          voice_guidance: %{
            quirks: "Counts each ingredient twice.",
            accent_dialect: "A soft French accent from Lyon.",
            cadence: "Quick phrases that slow before a confession.",
            vocabulary: "Uses kitchen and river words.",
            mannerisms: "Taps the spoon when thinking."
          }
        },
        "1" => %{
          name: "Perrin",
          visible_facts_text: "A quiet cooper who tends the barrels."
        }
      }
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, player_character), "continue")

    view |> element("button[phx-click=add-starting-item]") |> render_click()

    world_and_inventory =
      Map.merge(Map.merge(Map.merge(story, player_character), opening), starting_inventory)

    submit_wizard_step(view, world_and_inventory, "continue")

    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()

    attrs = Map.merge(world_and_inventory, gm_character)
    submit_wizard_step(view, attrs, "continue")

    review_html = render(view)
    assert review_html =~ "Marcel"
    assert review_html =~ "Starting place"
    assert review_html =~ "The river bodega"
    assert review_html =~ "Active duty (GM only)"
    assert review_html =~ "Tend the fermentation vats"
    assert review_html =~ "Available after 75 in-world minutes."
    assert review_html =~ "The west cellar"
    assert review_html =~ "Second day of harvest"
    assert review_html =~ "Late evening"
    assert review_html =~ "Cool mist from the river"
    assert review_html =~ "Reserve bottles"
    assert review_html =~ "· 3 bottles"
    assert review_html =~ "· wine"
    assert review_html =~ "Kept for the autumn gathering."
    assert review_html =~ "Player-visible facts"
    assert review_html =~ "A warm, observant beaver cook from Lyon."
    assert review_html =~ "GM-only notes"
    assert review_html =~ "Secret: he altered the cellar ledger."
    assert review_html =~ "Character voice guidance"
    assert review_html =~ "Quirks"
    assert review_html =~ "Counts each ingredient twice."
    assert review_html =~ "Accent or dialect"
    assert review_html =~ "A soft French accent from Lyon."
    assert review_html =~ "Cadence"
    assert review_html =~ "Quick phrases that slow before a confession."
    assert review_html =~ "Vocabulary"
    assert review_html =~ "Uses kitchen and river words."
    assert review_html =~ "Mannerisms"
    assert review_html =~ "Taps the spoon when thinking."
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=edit]") |> render_click()
    assert has_element?(view, "#gm-starting-place-0[value='The river bodega']")
    assert has_element?(view, "#gm-active-duty-0[value='Tend the fermentation vats']")
    assert has_element?(view, "#gm-active-duty-minutes-0[value='75']")
    assert has_element?(view, "#gm-starting-place-1[value='']")
    submit_wizard_step(view, attrs, "continue")

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert_redirect(view, ~p"/campaigns/#{campaign.id}")
    [session] = campaign.sessions

    assert {:ok, projection} = Play.public_projection(campaign.id)
    marcel = Enum.find(projection.characters, &(&1.speaker_id == "marcel"))
    perrin = Enum.find(projection.characters, &(&1.speaker_id == "perrin"))
    bodega = Enum.find(projection.places, &(&1.name == "The river bodega"))

    assert marcel.current_place_id == bodega.place_id
    assert marcel.current_place == Map.take(bodega, [:place_id, :name, :description, :facts])

    marcel_record = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "marcel")
    assert marcel_record.duty_place_id == bodega.place_id
    assert marcel_record.duty_release_at_world_minute == 75

    refute Map.has_key?(marcel, :active_duty)
    refute Jason.encode!(projection) =~ "Tend the fermentation vats"
    assert is_nil(perrin.current_place_id)
    assert is_nil(perrin.current_place)
    assert Enum.map(projection.places, & &1.name) == ["The river bodega", "The west cellar"]

    {:ok, _campaign_view, campaign_html} = live(conn, ~p"/campaigns/#{campaign.id}")

    {:ok, _session_view, session_html} = open_session(conn, campaign, session)

    assert session_html =~ "Marcel"
    assert session_html =~ "The river bodega"
    assert session_html =~ "Perrin"
    assert session_html =~ "No known location"

    for private_text <- [
          "Secret: he altered the cellar ledger.",
          "Counts each ingredient twice.",
          "A soft French accent from Lyon.",
          "Quick phrases that slow before a confession.",
          "Uses kitchen and river words.",
          "Taps the spoon when thinking.",
          "Tend the fermentation vats"
        ] do
      refute campaign_html =~ private_text
      refute session_html =~ private_text
    end
  end

  test "campaign setup moves through grouped steps and backtracking preserves entered values", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/campaigns/new")
    assert html =~ "Step 1 of 4"
    refute has_element?(view, "#campaign-setup-step-1[hidden]")
    assert has_element?(view, "#campaign-setup-step-2[hidden]")

    story = %{
      title: "The Quiet Beacon",
      premise: "A lighthouse answers a signal no one sent.",
      setting: "The northern coast",
      tone: "Quiet and curious",
      narration_language: "English"
    }

    view |> submit_wizard_step(story, "continue")
    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")

    character = %{
      player_character_name: "Iris",
      player_character: "A keeper who remembers every ship."
    }

    view |> submit_wizard_step(Map.merge(story, character), "continue")
    assert has_element?(view, "#campaign-setup-step-3:not([hidden])")

    submit_wizard_step(view, Map.merge(story, character), "previous")
    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")
    assert render(view) =~ "value=\"Iris\""
    assert render(view) =~ "A keeper who remembers every ship."

    submit_wizard_step(view, Map.merge(story, character), "previous")
    assert has_element?(view, "#campaign-setup-step-1:not([hidden])")
    assert render(view) =~ "value=\"The Quiet Beacon\""
    assert render(view) =~ "The northern coast"
  end

  test "GM starting places stay distinct in the next session's GM context and character board", %{
    conn: _conn
  } do
    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "npc:marcel",
            name: "Marcel",
            starting_place: "The river bodega",
            visible_facts: %{"description" => "The cellar's careful keeper."}
          },
          %{
            speaker_id: "npc:perrin",
            name: "Perrin",
            visible_facts: %{"description" => "A quiet cooper."}
          }
        ]
      })

    {:ok, initial_projection} = Play.public_projection(campaign.id)
    marcel = Enum.find(initial_projection.characters, &(&1.speaker_id == "npc:marcel"))
    perrin = Enum.find(initial_projection.characters, &(&1.speaker_id == "npc:perrin"))
    bodega = Enum.find(initial_projection.places, &(&1.name == "The river bodega"))
    finca = Enum.find(initial_projection.places, &(&1.name == "The Finca"))

    assert marcel.current_place_id == bodega.place_id
    assert Enum.any?(initial_projection.places, &(&1.place_id == marcel.current_place_id))
    assert perrin.current_place_id == nil
    assert perrin.current_place == nil
    refute bodega.place_id == finca.place_id

    {:ok, session} = Campaigns.start_session(campaign)
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    proposal = %{
      "narration" => "Morning light settles over the vineyard.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "time_advance_minutes" => 0,
      "character_updates" => [],
      "location_changes" => [],
      "continuity_changes" => [],
      "roll_request" => nil
    }

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "inspect-starting-places",
               "I check on the winery.",
               provider: fn request ->
                 context = request |> decode_request()
                 Agent.update(captured_context, fn _ -> context end)
                 {:ok, Jason.encode!(proposal)}
               end,
               model: "test-model"
             )

    context = Agent.get(captured_context, & &1)
    context_marcel = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:marcel"))
    context_perrin = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:perrin"))

    assert context_marcel["current_place_id"] == bodega.place_id
    assert context_marcel["current_place"]["name"] == "The river bodega"
    assert context_perrin["current_place_id"] == nil
    assert context_perrin["current_place"] == nil
    assert Enum.any?(context["places"]["public"], &(&1["place_id"] == bodega.place_id))

    refute Enum.any?(context["travel_connections"]["public_routes"], fn route ->
             bodega.place_id in route["place_ids"] and finca.place_id in route["place_ids"]
           end)

    {:ok, board_projection} = Play.public_projection(campaign.id)
    board_marcel = Enum.find(board_projection.characters, &(&1.speaker_id == "npc:marcel"))
    board_perrin = Enum.find(board_projection.characters, &(&1.speaker_id == "npc:perrin"))
    assert board_marcel.current_place.name == "The river bodega"
    assert board_perrin.current_place == nil
  end

  test "review validation returns the player to the step containing invalid fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    attrs = %{
      title: "x",
      premise: "A signal appears.",
      setting: "A coastal town",
      tone: "Thoughtful",
      narration_language: "English",
      player_character_name: "Mira",
      player_character: "A keeper who watches the sea."
    }

    submit_wizard_step(view, attrs, "continue")
    submit_wizard_step(view, attrs, "continue")
    submit_wizard_step(view, attrs, "continue")
    html = submit_wizard_step(view, attrs, "continue")

    assert has_element?(view, "#campaign-setup-step-1:not([hidden])")
    assert html =~ "should be at least 2 character(s)"
    assert Campaigns.list_campaigns() == []
  end

  test "forged GM starting places over the length limit get a field-specific setup error", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The River Cellar",
      premise: "A late harvest brings a visitor.",
      setting: "A riverside vineyard",
      tone: "Grounded and warm",
      narration_language: "English"
    }

    player = %{
      player_character_name: "Mira",
      player_character: "The vineyard's keeper."
    }

    opening = %{starting_location: "The Finca"}
    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, player), "continue")
    submit_wizard_step(view, Map.merge(Map.merge(story, player), opening), "continue")
    view |> element("button[phx-click=add-character]") |> render_click()

    forged_attrs =
      story
      |> Map.merge(player)
      |> Map.merge(opening)
      |> Map.put(:gm_characters, %{
        "0" => %{
          name: "Marcel",
          starting_place: String.duplicate("x", 301),
          visible_facts_text: "A careful cellar keeper."
        }
      })

    html = submit_wizard_step(view, forged_attrs, "continue")

    assert html =~ "GM character 1 starting place must be 300 characters or fewer."
    assert Campaigns.list_campaigns() == []
  end

  test "review validation returns the player to the character step when required details are missing",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Quiet Beacon",
      premise: "A signal appears.",
      setting: "A coastal town",
      tone: "Thoughtful",
      narration_language: "English"
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, story, "continue")
    html = submit_wizard_step(view, story, "continue")

    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")
    html_text = html |> Floki.parse_document!() |> Floki.text()
    assert html_text =~ "can't be blank"
    assert Campaigns.list_campaigns() == []
  end

  test "optional setup sections stay collapsed until they contain rows", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/campaigns/new")

    section_ids = [
      "player-character-details",
      "starting-inventory",
      "gm-characters",
      "campaign-panels"
    ]

    for section_id <- section_ids do
      assert has_element?(view, "details##{section_id}")
      refute has_element?(view, "details##{section_id}[open]")
    end

    assert html =~ "Optional"

    view |> element("button[phx-click=add-player-detail]") |> render_click()
    view |> element("button[phx-click=add-starting-item]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()

    for section_id <- section_ids do
      assert has_element?(view, "details##{section_id}[open]")
    end

    view |> element("button[phx-click=remove-player-detail]") |> render_click()
    view |> element("button[phx-click=remove-starting-item]") |> render_click()
    view |> element("button[phx-click=remove-character]") |> render_click()
    view |> element("button[phx-click=remove-panel-field]") |> render_click()

    for section_id <- section_ids do
      refute has_element?(view, "details##{section_id}[open]")
    end
  end

  test "character voice guidance stays expanded while separate notes are entered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Bellwether Inn",
      premise: "A storm closes the mountain pass for the night.",
      setting: "A fictional inn above a pine forest",
      tone: "Warm and grounded",
      narration_language: "English"
    }

    player = %{
      player_character_name: "Nessa Vale",
      player_character: "A cartographer who listens before deciding."
    }

    opening = %{
      starting_location: "The Bellwether Inn",
      starting_date: "Late autumn",
      world_time: "Evening",
      weather: "Cold rain"
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, player), "continue")
    submit_wizard_step(view, Map.merge(Map.merge(story, player), opening), "continue")

    view |> element("button[phx-click=add-character]") |> render_click()

    attrs =
      Map.merge(Map.merge(Map.merge(story, player), opening), %{
        gm_characters: %{
          "0" => %{
            name: "Bastien Brume",
            starting_place: "The Bellwether Inn",
            visible_facts_text: "A French beaver who cooks for the inn.",
            voice_guidance: %{quirks: "Uses dry humor when nervous."}
          }
        }
      })

    view |> form("#campaign-form", campaign: attrs) |> render_change()

    assert has_element?(view, "#gm-character-voice-0[open]")
    assert render(view) =~ "Uses dry humor when nervous."

    attrs =
      put_in(
        attrs,
        [:gm_characters, "0", :voice_guidance, :accent_dialect],
        "A gentle French accent, never phonetic spelling."
      )

    view |> form("#campaign-form", campaign: attrs) |> render_change()

    assert has_element?(view, "#gm-character-voice-0[open]")
    html = render(view)
    assert html =~ "Uses dry humor when nervous."
    assert html =~ "A gentle French accent, never phonetic spelling."
  end

  test "GM character setup creates stable identities from names without showing internal IDs", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()

    refute has_element?(view, "input[name='campaign[gm_characters][0][speaker_id]']")
    assert has_element?(view, "input[name='campaign[gm_characters][0][name]']")

    attrs = %{
      title: "The Lantern Watch",
      premise: "A signal has returned to the empty harbor.",
      setting: "A quiet coastal town",
      tone: "Grounded and mysterious",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier",
      gm_characters: %{
        "0" => %{name: "Captain Ren"},
        "1" => %{name: "Captain Ren"},
        "2" => %{name: "Player"}
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Captain Ren"
    assert review_html =~ "Player"
    refute review_html =~ "captain_ren"
    refute review_html =~ "gm_player"

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert {:ok, projection} = Play.public_projection(campaign.id)

    gm_speakers =
      projection.characters
      |> Enum.filter(&(&1.role == :gm))
      |> MapSet.new(&{&1.name, &1.speaker_id})

    assert gm_speakers ==
             MapSet.new([
               {"Captain Ren", "captain_ren"},
               {"Captain Ren", "captain_ren_2"},
               {"Player", "gm_player"}
             ])
  end

  test "starting inventory is editable in setup, reviewed, and visible on the play board", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-starting-item]") |> render_click()
    assert has_element?(view, "input[name='campaign[inventory][0][name]']")

    attrs = %{
      title: "The Quiet Observatory",
      premise: "A sealed cabinet waits beneath the star charts.",
      setting: "Asterfall Island",
      tone: "Quiet wonder",
      narration_language: "English",
      player_character_name: "Mira Vale",
      player_character: "A careful apprentice astronomer.",
      inventory: %{
        "0" => %{
          name: "Healing potion",
          quantity: "2",
          unit: "vials",
          category: "Potion",
          description: "A restorative tonic in green glass."
        }
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Starting inventory"
    assert review_html =~ "Healing potion"
    assert review_html =~ "2 vials"
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    session = hd(campaign.sessions)
    {:ok, play_view, play_html} = open_session(conn, campaign, session)

    assert has_element?(play_view, "#character-inventory")
    assert play_html =~ "Healing potion"
    assert play_html =~ "2 vials"
    assert play_html =~ "A restorative tonic in green glass."
  end

  test "optional player details can be reviewed and appear on the player board", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-player-detail]") |> render_click()
    view |> element("button[phx-click=add-player-detail]") |> render_click()

    assert has_element?(view, "input[name='campaign[player_character_details][0][label]']")
    assert has_element?(view, "input[name='campaign[player_character_details][0][value]']")
    assert has_element?(view, "input[name='campaign[player_character_details][1][label]']")
    assert has_element?(view, "input[name='campaign[player_character_details][1][value]']")

    attrs = %{
      title: "The Quiet Orchard",
      premise: "A final harvest is approaching.",
      setting: "A coastal orchard",
      tone: "Grounded and reflective",
      narration_language: "English",
      player_character_name: "Mira Vale",
      player_character: "An orchard keeper with a gentle patience.",
      player_character_details: %{
        "0" => %{label: "Health", value: "Recovering well"},
        "1" => %{label: "Responsibilities", value: "Cares for the northern rows"}
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Player character details"
    assert review_html =~ "Health"
    assert review_html =~ "Recovering well"
    assert review_html =~ "Responsibilities"
    assert review_html =~ "Cares for the northern rows"
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    session = hd(campaign.sessions)

    {:ok, _play_view, play_html} = open_session(conn, campaign, session)

    assert play_html =~ "Known details"
    assert play_html =~ "Health"
    assert play_html =~ "Recovering well"
    assert play_html =~ "Responsibilities"
    assert play_html =~ "Cares for the northern rows"
  end

  test "campaign setup accepts nested character and panel rows and only displays public panel values",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()

    attrs = %{
      title: "The Quiet Relay",
      premise: "A remote signal starts again.",
      setting: "An invented mountain pass",
      tone: "Curious and restrained",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier",
      starting_location: "The east relay station",
      starting_date: "The last day of autumn",
      world_time: "Near midnight",
      weather: "Dry snow",
      gm_characters: %{
        "0" => %{
          name: "Warden Eli",
          visible_facts_text: "The station's night keeper.",
          private_notes: "Knows why the signal stopped."
        }
      },
      panel_fields: %{
        "0" => %{
          key: "lamp_oil",
          panel: "Supplies",
          label: "Lamp oil",
          value_type: "quantity",
          unit: "flasks",
          visibility: "public",
          initial_value: "2"
        },
        "1" => %{
          key: "relay_cause",
          panel: "GM notes",
          label: "Relay cause",
          value_type: "text",
          visibility: "gm_private",
          initial_value: "A damaged receiver."
        }
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Warden Eli"
    assert review_html =~ "Lamp oil"

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert {:ok, state} = Play.public_projection(campaign.id)
    assert state.world["date"] == "The last day of autumn"
    assert state.world["time"] == "Near midnight"
    assert [%{speaker_id: "warden_eli"}] = Enum.filter(state.characters, &(&1.role == :gm))

    assert {:ok, %{panels: panels}} = Panels.public_projection(campaign.id)
    assert [%{name: "Supplies", fields: [%{key: "lamp_oil", value: 2}]}] = panels

    {:ok, _detail, detail_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert detail_html =~ "Lamp oil"
    refute detail_html =~ "relay_cause"
    refute detail_html =~ "A damaged receiver"
  end

  test "campaign detail resumes history and starts a later session", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        player_character_name: "Rin Ashford",
        player_character: "A careful guide who carries a hand-drawn map."
      })

    [first_session] = campaign.sessions

    {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert html =~ first_session.title
    assert has_element?(view, "a", "Edit campaign")
    refute has_element?(view, "a", "Edit setup and character voices")
    assert has_element?(view, "#campaign-persistence summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence[open]")
    refute has_element?(view, "#campaign-backup-form")

    assert has_element?(
             view,
             "#campaign-persistence a[href='/campaigns/#{campaign.id}/backup']"
           )

    assert html =~ "Character name"
    assert html =~ "Rin Ashford"
    assert html =~ "Character description"
    assert html =~ "A careful guide who carries a hand-drawn map."

    assert html =~
             "Starting another session completes the active session. Its full story stays saved."

    assert has_element?(
             view,
             "a[href='/campaigns/#{campaign.id}/sessions/#{first_session.id}']",
             "Resume current session"
           )

    assert has_element?(view, "button", "Start another session")

    assert has_element?(
             view,
             "a[href='/campaigns/#{campaign.id}/sessions/#{first_session.id}']",
             "Resume session"
           )

    view
    |> form("form[phx-submit=start-session]", session: %{title: "A Clear Night"})
    |> render_submit()

    refreshed = Campaigns.get_campaign!(campaign.id)
    assert Enum.find(refreshed.sessions, &(&1.id == first_session.id)).status == :completed
    assert Enum.count(refreshed.sessions, &(&1.status == :active)) == 1
    assert Enum.any?(refreshed.sessions, &(&1.title == "A Clear Night" and &1.status == :active))
    new_session = Enum.find(refreshed.sessions, &(&1.title == "A Clear Night"))
    assert_redirect(view, ~p"/campaigns/#{campaign.id}/sessions/#{new_session.id}")
  end

  test "campaign companion projects expose MCP settings and add a site link", %{conn: conn} do
    campaign = campaign_fixture()
    {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}/integrations")

    assert html =~ "Companion projects"
    view |> element("button[phx-click=add-integration]") |> render_click()
    form_html = render(view)

    assert form_html =~ "MCP Streamable HTTP endpoint"
    assert form_html =~ "GM instructions for this project"

    [_, integration_id] =
      Regex.run(~r/campaign\[integrations\]\[([^\]]+)\]\[name\]/, form_html)

    view
    |> form("#campaign-integrations-form",
      campaign: %{
        integrations: %{
          integration_id => %{
            name: "Finca companion",
            mcp_endpoint_url: "http://127.0.0.1:7780/mcp",
            instructions: "Read current records before changing them.",
            site_label: "Finca ledger",
            site_url: "http://127.0.0.1:7778"
          }
        }
      }
    )
    |> render_submit()

    assert render(view) =~ "Companion projects saved."

    assert Campaigns.get_campaign!(campaign.id).integrations[integration_id]["mcp_endpoint_url"] ==
             "http://127.0.0.1:7780/mcp"

    {:ok, detail_view, detail_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert detail_html =~ "Companion project sites"

    assert has_element?(
             detail_view,
             "#campaign-companion-sites a[href='http://127.0.0.1:7778'][target='_blank'][rel='noopener noreferrer']",
             "Finca ledger"
           )
  end

  test "archive and restore update the campaign list without deleting its history", %{conn: conn} do
    campaign = campaign_fixture(%{title: "The Paper Moon"})
    [session] = campaign.sessions

    {:ok, view, _html} = live(conn, ~p"/")

    archived_html =
      view |> element("#campaign-#{campaign.id} button[phx-click=archive]") |> render_click()

    assert archived_html =~ "Archived"
    archived = Campaigns.get_campaign!(campaign.id)
    assert archived.status == :archived
    assert Enum.any?(archived.sessions, &(&1.id == session.id))
    assert has_element?(view, "#campaign-#{campaign.id} button[phx-click=restore]")

    restored_html =
      view |> element("#campaign-#{campaign.id} button[phx-click=restore]") |> render_click()

    assert restored_html =~ "Active"
    assert Campaigns.get_campaign!(campaign.id).status == :active
  end

  test "a resumed session stays scoped to its campaign", %{conn: conn} do
    campaign = campaign_fixture(%{title: "The Glass Observatory"})
    [session] = campaign.sessions

    {:ok, _view, html} = open_session(conn, campaign, session)
    assert html =~ campaign.title
    assert html =~ session.title
    assert html =~ campaign.player_character_name
    assert html =~ "Campaign story"
    assert html =~ "What do you do or say?"
  end

  test "invalid campaign setup shows errors and saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    html = view |> form("#campaign-form", campaign: %{title: "x"}) |> render_submit()
    html_text = html |> Floki.parse_document!() |> Floki.text()
    assert html_text =~ "can't be blank"
    assert Campaigns.list_campaigns() == []
  end

  defp submit_wizard_step(view, attrs, direction) do
    view
    |> form("#campaign-form", campaign: attrs)
    |> put_submitter("button[name=direction][value=#{direction}]")
    |> render_submit()
  end

  defp open_session(conn, campaign, session) do
    result = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert wait_until(fn -> is_nil(Play.public_current_turn(campaign.id)) end),
           "opening scene did not finish; current turn: #{inspect(Play.public_current_turn(campaign.id))}"

    result
  end

  defp wait_until(fun, attempts \\ 120)
  defp wait_until(fun, 0), do: fun.()

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp test_opening_scene_response(request) do
    context =
      request.input
      |> Enum.find(&Map.has_key?(&1, :content))
      |> Map.fetch!(:content)
      |> Jason.decode!()

    current_location = get_in(context, ["world", "public", "location"])

    location_changes =
      if is_binary(current_location) and String.trim(current_location) != "" do
        []
      else
        [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "campaign-live-opening-place",
              "name" => "The Opening Scene",
              "visibility" => "public"
            },
            "reason" => "The test GM establishes the opening location."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "campaign-live-opening-place",
            "reason" => "The player starts in the opening scene."
          }
        ]
      end

    {:ok,
     %{
       narration: "The scene takes shape, and a clear choice is yours.",
       memory_update: %{public_summary: "", gm_private_summary: ""},
       location_changes: location_changes
     }}
  end

  defp decode_request(request) do
    request.input
    |> Enum.find(&Map.has_key?(&1, :content))
    |> Map.fetch!(:content)
    |> Jason.decode!()
  end
end
