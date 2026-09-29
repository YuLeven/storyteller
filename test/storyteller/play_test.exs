defmodule Storyteller.PlayTest do
  use Storyteller.DataCase

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Play.{Event, Roll, State, Turn}

  test "GM memory is persisted by visibility and only recent events are sent back to the model" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "bounded-memory",
               "Ask the keeper about her plans."
             )

    for sequence <- 1..90 do
      Repo.insert!(
        Event.changeset(%Event{}, %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: pending.id,
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "Earlier scene #{sequence}"}
        })
      )
    end

    state = Repo.get_by!(State, campaign_id: campaign.id)
    Repo.update!(State.changeset(state, %{event_sequence: 90}))

    context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(context_agent, fn _ -> context end)

      memory_update = %{
        "public_summary" => "The keeper is studying an unusual eastern star.",
        "gm_private_summary" => "The keeper suspects the observatory chart was altered."
      }

      {:ok, Jason.encode!(ordinary_proposal(%{"memory_update" => memory_update}))}
    end

    assert {:ok, %{status: :completed} = resolved} =
             Play.retry_turn(pending.id, provider: provider)

    context = Agent.get(context_agent, & &1)
    assert context["memory"]["public_summary"] == ""
    assert context["memory"]["gm_private_summary"] == ""
    assert length(context["history"]) == 40
    assert hd(context["history"])["sequence"] == 51
    assert List.last(context["history"])["sequence"] == 90

    assert {:ok, persisted_context} = Play.model_context(resolved.id)

    assert persisted_context.memory.public_summary ==
             "The keeper is studying an unusual eastern star."

    assert persisted_context.memory.gm_private_summary ==
             "The keeper suspects the observatory chart was altered."

    {:ok, timeline_before_invalid_memory} = Play.public_timeline(campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "oversized-memory",
               "Look again at the chart.",
               provider:
                 ordinary_provider(%{
                   "memory_update" => %{
                     "public_summary" => String.duplicate("x", 6_001),
                     "gm_private_summary" => ""
                   }
                 })
             )

    {:ok, timeline_after_invalid_memory} = Play.public_timeline(campaign.id)
    assert timeline_after_invalid_memory == timeline_before_invalid_memory

    {:ok, after_invalid_memory} = Play.model_context(resolved.id)
    assert after_invalid_memory.memory.public_summary == persisted_context.memory.public_summary

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Map.has_key?(projection, :memory)
    refute Map.has_key?(projection, :gm_private_history_summary)
  end

  test "public projections separate private world and character facts" do
    {campaign, session} = play_campaign("The Glass Observatory")

    request_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(request_context, fn _ -> context end)

      {:ok,
       Jason.encode!(ordinary_proposal(%{"public_changes" => %{"location" => "Upper dome"}}))}
    end

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, "action-1", "Ask the keeper what she saw.",
               provider: provider,
               model: "test-model"
             )

    assert turn.status == :completed

    assert {:ok, %{revision: 1, world: world, characters: characters}} =
             Play.public_projection(campaign.id)

    keeper = Enum.find(characters, &(&1.speaker_id == "npc:lyra"))
    player = Enum.find(characters, &(&1.speaker_id == "player"))

    assert world["location"] == "Upper dome"
    refute Map.has_key?(world, "gm_private")
    assert keeper.speaker_id == "npc:lyra"
    assert keeper.visible_facts["role"] == "keeper"
    assert keeper.visible_activity == "She checks the brass shutter."
    refute Map.has_key?(keeper, :gm_private_facts)
    assert player.speaker_id == "player"

    assert %{
             "world" => %{"gm_private" => %{"weather_cause" => "a distant pressure front"}},
             "characters" => [%{"gm_private_facts" => %{"motive" => "protect the chart"}} | _],
             "player_action" => "Ask the keeper what she saw."
           } =
             Agent.get(request_context, & &1)

    assert {:ok, public_events} = Play.public_timeline(campaign.id)

    assert Enum.all?(
             public_events,
             &(&1.event_type in [
                 :player_action,
                 :gm_narration,
                 :npc_dialogue,
                 :character_activity,
                 :state_change
               ])
           )

    assert Enum.map(public_events, & &1.position) == Enum.to_list(1..length(public_events))

    assert Enum.any?(
             public_events,
             &(&1.event_type == :npc_dialogue and &1.speaker_id == "npc:lyra")
           )
  end

  test "GM panel changes are typed, atomic, and private values stay out of public events" do
    {campaign, session} = play_campaign("The Glass Observatory")

    insert_panel_field!(campaign.id, %{
      key: "cash",
      panel: "Finances",
      label: "Available cash",
      value_type: :money,
      unit: "ARS",
      visibility: :public,
      value: %{"value" => "1000"}
    })

    insert_panel_field!(campaign.id, %{
      key: "keeper_secret",
      panel: "GM notes",
      label: "Hidden clue",
      value_type: :text,
      visibility: :gm_private,
      value: %{"value" => "unnoticed crack"}
    })

    context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(context_agent, fn _ -> context end)

      proposal =
        ordinary_proposal(%{
          "panel_changes" => %{"cash" => "1250.50", "keeper_secret" => "revealed later"}
        })

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "panel-update", "Review the accounts.",
               provider: provider,
               model: "test-model"
             )

    assert [%{"key" => "cash", "value" => "1000", "unit" => "ARS"}] =
             Agent.get(context_agent, fn context ->
               assert Enum.any?(context["panels"], &(&1["key"] == "keeper_secret"))
               Enum.filter(context["panels"], &(&1["key"] == "cash"))
             end)

    assert {:ok, %{panels: [panel]}} = Play.public_projection(campaign.id)
    assert panel.name == "Finances"
    assert [%{key: "cash", value: "1250.5"}] = panel.fields

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    public_panel_event = Enum.find(timeline, &Map.has_key?(&1.payload, "panel_changes"))
    assert public_panel_event.payload["panel_changes"] == %{"cash" => "1250.5"}
    refute Map.has_key?(public_panel_event.payload["panel_changes"], "keeper_secret")

    assert {:ok, private_field} = Panels.public_projection(campaign.id)

    refute Enum.any?(
             private_field.panels,
             &Enum.any?(&1.fields, fn field -> field.key == "keeper_secret" end)
           )

    invalid_provider =
      ordinary_provider(%{"panel_changes" => %{"cash" => "-10"}})

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "invalid-panel",
               "Spend beyond the balance.",
               provider: invalid_provider,
               model: "test-model"
             )

    assert {:ok, %{panels: [%{fields: [%{key: "cash", value: "1250.5"}]}]}} =
             Panels.public_projection(campaign.id)
  end

  test "campaign snapshots stay isolated and campaign history continues across sessions" do
    {first, first_session} = play_campaign("The Glass Observatory")
    {second, second_session} = play_campaign("The Copper Archive")

    complete_turn(
      first,
      first_session,
      "first",
      "Look at the map.",
      ordinary_provider(%{"public_changes" => %{"location" => "Dome"}})
    )

    complete_turn(
      second,
      second_session,
      "second",
      "Open the catalog.",
      ordinary_provider(%{"public_changes" => %{"location" => "Archive"}})
    )

    assert {:ok, next_session} = Campaigns.start_session(first)

    complete_turn(
      first,
      next_session,
      "third",
      "Ask about the missing page.",
      ordinary_provider()
    )

    assert {:ok, first_projection} = Play.public_projection(first.id)
    assert {:ok, second_projection} = Play.public_projection(second.id)
    assert first_projection.world["location"] == "Dome"
    assert second_projection.world["location"] == "Archive"

    assert {:ok, first_history} = Play.public_timeline(first.id)
    assert Enum.count(first_history, &(&1.event_type == :player_action)) == 2
    assert Enum.any?(first_history, &(&1.session_id == first_session.id))
    assert Enum.any?(first_history, &(&1.session_id == next_session.id))

    assert Enum.all?(
             Play.public_timeline(second.id) |> elem(1),
             &(&1.session_id == second_session.id)
           )

    assert Enum.map(first_history, & &1.position) == Enum.to_list(1..length(first_history))
  end

  test "idempotency replays a completed turn and rejects key reuse with different text" do
    {campaign, session} = play_campaign("The Glass Observatory")
    caller = self()

    provider = fn _request ->
      send(caller, :provider_called)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, first} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Wait by the telescope.",
               provider: provider,
               model: "test-model"
             )

    assert_receive :provider_called

    assert {:ok, replay} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Wait by the telescope.",
               provider: fn _ ->
                 flunk("a completed idempotent turn must not call the provider again")
               end
             )

    assert replay.id == first.id
    refute_receive :provider_called

    assert {:error, :idempotency_conflict} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Leave the room.")

    assert Repo.aggregate(Turn, :count) == 1

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "an ordinary action completes without asking for a D20" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, "ordinary", "Polish the lens.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert turn.status == :completed
    assert Repo.aggregate(Roll, :count) == 0

    assert {:error, :roll_not_authorized} =
             Play.click_player_d20(turn.id, roll_source: fn -> flunk("no roll was requested") end)
  end

  test "pending turns reconnect with the same record and can be resumed without duplicating input" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "resume", "Watch the eastern sky.")

    assert pending.status == :pending
    assert Play.get_turn(campaign.id, "resume").id == pending.id

    assert {:ok, same_pending} =
             Play.submit_turn(campaign.id, session.id, "resume", "Watch the eastern sky.",
               provider: fn _ ->
                 flunk("replayed pending submission does not start a second resolution")
               end
             )

    assert same_pending.id == pending.id
    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, resumed} =
             Play.retry_turn(pending.id, provider: ordinary_provider(), model: "test-model")

    assert resumed.id == pending.id
    assert resumed.status == :completed
    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_action)) == 1
  end

  test "only an explicit click authorizes one app-generated D20 and the result survives replay" do
    {campaign, session} = play_campaign("The Glass Observatory")
    caller = self()
    calls = :atomics.new(1, [])

    provider = fn request ->
      count = :atomics.add_get(calls, 1, 1)
      context = decode_request(request)

      proposal =
        if count == 1 do
          roll_proposal()
        else
          assert context["player_roll"]["result"] == 17
          ordinary_proposal(%{"public_changes" => %{"world_time" => "Second watch"}})
        end

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, waiting} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "climb",
               "Climb to the dome's narrow ledge.",
               provider: provider,
               model: "test-model"
             )

    assert waiting.status == :awaiting_roll
    assert waiting.roll_request["test"] == "Keep your balance on the ledge"
    assert Repo.aggregate(Roll, :count) == 0

    assert {:error, :turn_already_open} =
             Play.submit_turn(campaign.id, session.id, "too-soon", "Do something else.")

    assert {:error, :invalid_roll} =
             Play.click_player_d20(waiting.id, roll_source: fn -> 21 end)

    assert Repo.aggregate(Roll, :count) == 0

    source = fn ->
      send(caller, :roll_source_called)
      17
    end

    assert {:ok, %{turn: completed, roll: %Roll{result: 17}}} =
             Play.click_player_d20(waiting.id,
               roll_source: source,
               provider: provider,
               model: "test-model"
             )

    assert completed.status == :completed
    assert_receive :roll_source_called
    assert :atomics.get(calls, 1) == 2

    assert {:ok, %{turn: replay, roll: %Roll{result: 17}}} =
             Play.click_player_d20(waiting.id,
               roll_source: fn -> flunk("a replay must return the stored D20") end
             )

    assert replay.id == completed.id
    assert :atomics.get(calls, 1) == 2
    assert Repo.aggregate(Roll, :count) == 1

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_roll)) == 1
    assert Enum.find(timeline, &(&1.event_type == :player_roll)).payload["result"] == 17
  end

  test "provider timeout or malformed output leaves canonical state and timeline untouched, then retry succeeds" do
    for provider_error <- [{:error, :timeout}, {:ok, "not JSON"}] do
      {campaign, session} = play_campaign("The Glass Observatory")
      before = Play.public_projection(campaign.id)

      assert {:ok, failed} =
               Play.submit_turn(campaign.id, session.id, "retry-me", "Describe the sky.",
                 provider: fn _request -> provider_error end,
                 model: "test-model"
               )

      assert failed.status == :failed
      assert failed.player_input == "Describe the sky."
      assert {:ok, []} = Play.public_timeline(campaign.id)
      assert Play.public_projection(campaign.id) == before

      assert {:ok, retried} =
               Play.retry_turn(failed.id, provider: ordinary_provider(), model: "test-model")

      assert retried.status == :completed
      assert {:ok, events} = Play.public_timeline(campaign.id)
      assert Enum.count(events, &(&1.event_type == :player_action)) == 1
      assert Enum.at(events, 0).payload["text"] == "Describe the sky."
    end
  end

  test "a new action supersedes a failed turn while its explicit retry remains available before that choice" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, failed} =
             Play.submit_turn(campaign.id, session.id, "lost", "Check the window.",
               provider: fn _ -> {:error, :usage_unavailable} end
             )

    assert failed.status == :failed

    assert {:ok, completed} =
             Play.submit_turn(campaign.id, session.id, "new-action", "Ask for tea.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert completed.status == :completed
    assert Repo.get!(Turn, failed.id).status == :superseded
    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.count(events, &(&1.event_type == :player_action)) == 1
    assert Enum.at(events, 0).payload["text"] == "Ask for tea."
  end

  test "a reclaimed resolution attempt fences a late successful provider result" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "fence-success", "Watch the sky.")

    owner = self()

    old_provider = fn _request ->
      send(owner, {:old_provider_started, self()})

      receive do
        :return_old_result ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{"public_changes" => %{"location" => "Stale worker"}})
           )}
      end
    end

    old_worker =
      Task.async(fn ->
        Play.retry_turn(pending.id, provider: old_provider, model: "test-model")
      end)

    assert_receive {:old_provider_started, old_provider_pid}
    mark_resolution_stale!(pending.id)

    assert {:ok, current} =
             Play.retry_turn(pending.id,
               provider:
                 ordinary_provider(%{"public_changes" => %{"location" => "Fresh worker"}}),
               model: "test-model"
             )

    assert current.status == :completed
    send(old_provider_pid, :return_old_result)
    assert {:ok, late} = Task.await(old_worker, 5_000)
    assert late.status == :completed

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == "Fresh worker"

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "a reclaimed resolution attempt fences a late provider failure" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "fence-failure", "Watch the sky.")

    owner = self()

    old_provider = fn _request ->
      send(owner, {:old_provider_started, self()})

      receive do
        :return_old_failure -> {:error, :timeout}
      end
    end

    old_worker =
      Task.async(fn ->
        Play.retry_turn(pending.id, provider: old_provider, model: "test-model")
      end)

    assert_receive {:old_provider_started, old_provider_pid}
    mark_resolution_stale!(pending.id)

    assert {:ok, current} =
             Play.retry_turn(pending.id, provider: ordinary_provider(), model: "test-model")

    assert current.status == :completed
    send(old_provider_pid, :return_old_failure)
    assert {:ok, late} = Task.await(old_worker, 5_000)
    assert late.status == :completed
    assert late.failure_code == nil
    assert Repo.get!(Turn, pending.id).status == :completed

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "session rollover closes a pending provider turn and the next session can play" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "rollover-race", "Look through the lens.")

    owner = self()

    provider = fn _request ->
      send(owner, {:provider_started, self()})

      receive do
        :return_after_rollover ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{"public_changes" => %{"location" => "Must not commit"}})
           )}
      end
    end

    worker =
      Task.async(fn -> Play.retry_turn(pending.id, provider: provider, model: "test-model") end)

    assert_receive {:provider_started, provider_pid}

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    closed = Repo.get!(Turn, pending.id)
    assert closed.status == :failed
    assert closed.failure_code == "session_closed"

    send(provider_pid, :return_after_rollover)
    assert {:ok, late} = Task.await(worker, 5_000)
    assert late.status == :failed

    assert Play.public_projection(campaign.id)
           |> elem(1)
           |> Map.fetch!(:world)
           |> Map.fetch!("location") == nil

    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, next_turn} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "after-rollover",
               "Ask about the weather.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert next_turn.status == :completed
    assert Repo.get!(Turn, pending.id).status == :superseded
  end

  test "campaign archive closes an in-flight provider turn before it can commit" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "archive-race", "Open the dome.")

    owner = self()

    provider = fn _request ->
      send(owner, {:provider_started, self()})

      receive do
        :return_after_archive ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{"public_changes" => %{"location" => "Must not commit"}})
           )}
      end
    end

    worker =
      Task.async(fn -> Play.retry_turn(pending.id, provider: provider, model: "test-model") end)

    assert_receive {:provider_started, provider_pid}

    assert {:ok, archived} = Campaigns.archive_campaign(campaign)
    closed = Repo.get!(Turn, pending.id)
    assert closed.status == :failed
    assert closed.failure_code == "session_closed"

    send(provider_pid, :return_after_archive)
    assert {:ok, late} = Task.await(worker, 5_000)
    assert late.status == :failed

    assert Play.public_projection(campaign.id)
           |> elem(1)
           |> Map.fetch!(:world)
           |> Map.fetch!("location") == nil

    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:error, :campaign_unavailable} =
             Play.submit_turn(archived.id, session.id, "after-archive", "No action.")

    assert {:ok, restored} = Campaigns.restore_campaign(archived)
    assert {:ok, new_session} = Campaigns.start_session(restored)

    assert {:ok, resumed} =
             Play.submit_turn(restored.id, new_session.id, "after-restore", "Begin again.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert resumed.status == :completed
    assert Repo.get!(Turn, pending.id).status == :superseded
  end

  test "rejects unrecognized speakers and campaign/session mismatches" do
    {campaign, session} = play_campaign("The Glass Observatory")

    invalid_speaker =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "not-in-this-campaign", "text" => "I know you."}],
        "public_changes" => %{"location" => "Must not commit"}
      })

    assert {:ok, failed} =
             Play.submit_turn(campaign.id, session.id, "bad-speaker", "Listen.",
               provider: fn _ -> {:ok, Jason.encode!(invalid_speaker)} end
             )

    assert failed.status == :failed
    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == nil
    assert {:ok, []} = Play.public_timeline(campaign.id)

    other = campaign_fixture(%{title: "The Copper Archive"})
    other_session = hd(other.sessions)

    assert {:error, changeset} =
             Repo.insert(
               Turn.changeset(%Turn{}, %{
                 campaign_id: campaign.id,
                 session_id: other_session.id,
                 idempotency_key: "cross-campaign",
                 request_hash: String.duplicate("a", 64),
                 player_input: "This relation must be rejected.",
                 status: :completed,
                 resolution_phase: :initial,
                 attempts: 0
               })
             )

    assert Keyword.has_key?(changeset.errors, :session_id)
  end

  defp play_campaign(title) do
    campaign = campaign_fixture(%{title: title})
    session = hd(campaign.sessions)

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _state} =
             Repo.update(
               State.changeset(state, %{
                 public_state: %{
                   "weather" => "Clear",
                   "location" => nil,
                   "world_time" => "First watch"
                 },
                 gm_private_state: %{"weather_cause" => "a distant pressure front"}
               })
             )

    assert {:ok, _state} =
             Play.initialize_campaign(campaign, %{
               characters: [
                 %{
                   speaker_id: "npc:lyra",
                   name: "Lyra",
                   visible_facts: %{"role" => "keeper"},
                   gm_private_facts: %{"motive" => "protect the chart"},
                   visible_activity: nil
                 }
               ]
             })

    {campaign, session}
  end

  defp insert_panel_field!(campaign_id, attrs) do
    defaults = %{
      campaign_id: campaign_id,
      key: "resource",
      panel: "Resources",
      label: "Resource",
      value_type: :text,
      visibility: :public,
      value: %{"value" => ""},
      position: 0
    }

    Repo.insert!(PanelField.changeset(%PanelField{}, Map.merge(defaults, attrs)))
  end

  defp complete_turn(campaign, session, key, action, provider) do
    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, key, action,
               provider: provider,
               model: "test-model"
             )
  end

  defp ordinary_provider(overrides \\ %{}) do
    proposal = ordinary_proposal(overrides)
    fn _request -> {:ok, Jason.encode!(proposal)} end
  end

  defp ordinary_proposal(overrides \\ %{}) do
    Map.merge(
      %{
        "narration" => "The observatory settles into the quiet of the watch.",
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The eastern star moved once."}],
        "activities" => [%{"speaker_id" => "npc:lyra", "text" => "She checks the brass shutter."}],
        "public_changes" => %{},
        "private_changes" => %{"weather_cause" => "a distant pressure front"},
        "panel_changes" => %{},
        "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
        "character_updates" => [
          %{
            "speaker_id" => "npc:lyra",
            "visible_facts" => %{"last_spoke" => "The eastern star moved once."},
            "gm_private_facts" => %{"still_hidden" => true}
          }
        ],
        "roll_request" => nil
      },
      overrides
    )
  end

  defp roll_proposal do
    %{
      "narration" => "The narrow ledge is slick; keeping your balance will take focus.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => %{},
      "character_updates" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "roll_request" => %{
        "test" => "Keep your balance on the ledge",
        "difficulty" => "A demanding, uncertain climb",
        "target" => 14
      }
    }
  end

  defp decode_request(request) do
    text = request.input |> hd() |> Map.fetch!(:content) |> hd() |> Map.fetch!(:text)
    Jason.decode!(text)
  end

  defp mark_resolution_stale!(turn_id) do
    turn = Repo.get!(Turn, turn_id)

    stale_at =
      DateTime.utc_now() |> DateTime.add(-121, :second) |> DateTime.truncate(:microsecond)

    {:ok, _turn} = Repo.update(Turn.changeset(turn, %{resolution_started_at: stale_at}))
  end
end
