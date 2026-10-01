defmodule Storyteller.Play.WorldLabelCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Play
  alias Storyteller.Play.{CanonCorrection, CanonCorrections, Event, State, Turn}
  alias Storyteller.Repo

  test "date and time corrections re-anchor the current elapsed clock without editing history" do
    campaign = campaign_fixture(world_starting_values())
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        elapsed_world_minutes: 120,
        elapsed_world_anchor_minutes: 30,
        elapsed_world_anchor: %{"date" => "Earlier date", "time" => "Earlier watch"}
      })
    )

    timeline_before = Play.public_timeline(campaign.id)
    state_before = Repo.get_by!(State, campaign_id: campaign.id)
    {:ok, options} = CanonCorrections.options(campaign.id, session.id)

    assert options.world_labels == [
             %{key: "date", label: "Date", value: "14 October 1567"},
             %{key: "time", label: "Time", value: "First watch"},
             %{key: "weather", label: "Weather", value: "Low fog"}
           ]

    assert {:ok, %{revision: date_revision}} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "world",
               target_id: "date",
               expected_revision: options.revision,
               values: %{"value" => "15 October 1567"},
               reason: "The campaign notes give this date."
             })

    assert {:ok, options_after_date} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, %{revision: revision}} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "world",
               target_id: "time",
               expected_revision: options_after_date.revision,
               values: %{"value" => "Second watch"},
               reason: "The time entry was carried over from an earlier scene."
             })

    state_after = Repo.get_by!(State, campaign_id: campaign.id)

    corrections =
      Repo.all(
        from c in CanonCorrection,
          where: c.campaign_id == ^campaign.id,
          order_by: [asc: c.sequence]
      )

    assert date_revision == state_before.revision + 1
    assert revision == state_before.revision + 2
    assert state_after.revision == revision
    assert state_after.public_state["date"] == "15 October 1567"
    assert state_after.public_state["time"] == "Second watch"
    assert state_after.elapsed_world_minutes == 120
    assert state_after.elapsed_world_anchor_minutes == 120

    assert state_after.elapsed_world_anchor == %{
             "date" => "15 October 1567",
             "time" => "Second watch"
           }

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["date"] == "15 October 1567"
    assert projection.world["time"] == "Second watch"

    assert Enum.map(corrections, & &1.target_id) == ["date", "time"]
    assert hd(corrections).kind == "world"

    assert hd(corrections).before_state == %{
             "key" => "date",
             "label" => "Date",
             "value" => "14 October 1567"
           }

    assert hd(corrections).after_state == %{
             "key" => "date",
             "label" => "Date",
             "value" => "15 October 1567"
           }

    assert List.last(corrections).before_state == %{
             "key" => "time",
             "label" => "Time",
             "value" => "First watch"
           }

    assert List.last(corrections).after_state == %{
             "key" => "time",
             "label" => "Time",
             "value" => "Second watch"
           }

    assert Play.public_timeline(campaign.id) == timeline_before
    assert state_after.event_sequence == state_before.event_sequence

    assert Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count) ==
             0
  end

  test "weather correction leaves elapsed clock values alone and appears in the next-session GM context" do
    campaign = campaign_fixture(world_starting_values())
    first_session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        elapsed_world_minutes: 240,
        elapsed_world_anchor_minutes: 90,
        elapsed_world_anchor: %{"date" => "14 October 1567", "time" => "First watch"}
      })
    )

    {:ok, options} = CanonCorrections.options(campaign.id, first_session.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(campaign.id, first_session.id, %{
               kind: "world",
               target_id: "weather",
               expected_revision: options.revision,
               values: %{"value" => "Clear skies"},
               reason: "The weather entry was a transcription error."
             })

    corrected = Repo.get_by!(State, campaign_id: campaign.id)

    assert corrected.public_state["weather"] == "Clear skies"
    assert corrected.elapsed_world_minutes == 240
    assert corrected.elapsed_world_anchor_minutes == 90

    assert corrected.elapsed_world_anchor == %{
             "date" => "14 October 1567",
             "time" => "First watch"
           }

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["weather"] == "Clear skies"

    assert {:ok, next_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
    fake_provider = fn _request -> {:ok, fake_response()} end

    assert {:ok, %Turn{status: :completed} = turn} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "world-label-context",
               "Look outside.",
               provider: fake_provider,
               model: "world-correction-test"
             )

    assert {:ok, context} = Play.model_context(turn.id)
    assert context.world.public["weather"] == "Clear skies"
    assert context.world.public["date"] == "14 October 1567"
    assert context.elapsed_world_clock.total_minutes == 240
    assert context.elapsed_world_clock.anchor_minutes == 90
  end

  test "stale and in-flight corrections roll back without changing state or audit" do
    campaign = campaign_fixture(world_starting_values())
    session = hd(campaign.sessions)
    {:ok, options} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(
               campaign.id,
               session.id,
               correction(options.revision, "date", "15 October 1567")
             )

    corrected = Repo.get_by!(State, campaign_id: campaign.id)

    corrections_before =
      Repo.aggregate(from(c in CanonCorrection, where: c.campaign_id == ^campaign.id), :count)

    assert {:error, :stale_correction} =
             CanonCorrections.correct(
               campaign.id,
               session.id,
               correction(options.revision, "weather", "Clear skies")
             )

    assert Repo.get_by!(State, campaign_id: campaign.id) == corrected

    assert Repo.aggregate(
             from(c in CanonCorrection, where: c.campaign_id == ^campaign.id),
             :count
           ) == corrections_before

    assert {:ok, %Turn{status: :pending}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "pending-world-correction",
               "Wait a moment."
             )

    state_before_in_flight = Repo.get_by!(State, campaign_id: campaign.id)
    timeline_before_in_flight = Play.public_timeline(campaign.id)

    assert {:error, :turn_in_progress} =
             CanonCorrections.correct(
               campaign.id,
               session.id,
               correction(state_before_in_flight.revision, "weather", "Clear skies")
             )

    assert Repo.get_by!(State, campaign_id: campaign.id) == state_before_in_flight
    assert Play.public_timeline(campaign.id) == timeline_before_in_flight

    assert Repo.aggregate(
             from(c in CanonCorrection, where: c.campaign_id == ^campaign.id),
             :count
           ) == corrections_before
  end

  test "options and audit follow the public alias resolution and correction clears conflicting aliases" do
    campaign = campaign_fixture(world_starting_values())
    session = hd(campaign.sessions)

    assert {:ok, %Turn{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "legacy-time-label",
               "The morning advances.",
               provider: fn _request ->
                 {:ok, fake_response(%{"public_changes" => %{"world_time" => "Midmorning"}})}
               end,
               model: "world-correction-test"
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state:
          Map.merge(state.public_state, %{
            "time" => "First watch",
            "world_time" => "Stale legacy value"
          })
      })
    )

    latest_state_change =
      Repo.one!(
        from event in Event,
          where:
            event.campaign_id == ^campaign.id and event.event_type == :state_change and
              event.visibility == :public,
          order_by: [desc: event.sequence],
          limit: 1
      )

    Repo.update!(
      Event.changeset(latest_state_change, %{
        payload: %{"changes" => %{"world_time" => "Midmorning"}}
      })
    )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["time"] == "Midmorning"
    {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.find(options.world_labels, &(&1.key == "time")).value == "Midmorning"

    timeline_before = Play.public_timeline(campaign.id)
    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "world",
               target_id: "time",
               expected_revision: options.revision,
               values: %{"value" => "Second watch"},
               reason: "The established time label is Second watch."
             })

    corrected = Repo.get_by!(State, campaign_id: campaign.id)
    [audit] = Repo.all(from c in CanonCorrection, where: c.campaign_id == ^campaign.id)

    assert corrected.public_state["time"] == "Second watch"
    refute Map.has_key?(corrected.public_state, "world_time")
    assert audit.before_state == %{"key" => "time", "label" => "Time", "value" => "Midmorning"}
    assert Play.public_timeline(campaign.id) == timeline_before
    assert corrected.event_sequence == state_before.event_sequence
  end

  defp correction(revision, target_id, value) do
    %{
      kind: "world",
      target_id: target_id,
      expected_revision: revision,
      values: %{"value" => value},
      reason: "Correct the public world note."
    }
  end

  defp world_starting_values do
    %{
      starting_date: "14 October 1567",
      world_time: "First watch",
      weather: "Low fog"
    }
  end

  defp fake_response(overrides \\ %{}) do
    Map.merge(
      %{
        "narration" => "A clear sky stretches above the observatory.",
        "dialogue" => [],
        "activities" => [],
        "public_changes" => %{},
        "private_changes" => %{},
        "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
        "panel_changes" => [],
        "character_updates" => [],
        "character_creations" => [],
        "inventory_changes" => [],
        "location_changes" => [],
        "objective_changes" => [],
        "continuity_changes" => [],
        "time_advance_minutes" => 0,
        "roll_request" => nil
      },
      overrides
    )
    |> Jason.encode!()
  end
end
