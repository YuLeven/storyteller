defmodule Storyteller.Play.StoryMemoryCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Play
  alias Storyteller.Play.{CanonCorrection, CanonCorrections, ContinuityEntry, Event, State, Turn}
  alias Storyteller.Repo

  test "public story memory can be preserved, corrected, and retracted outside the fiction" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    event_count_before =
      Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count)

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert options.player_memory_count == 0
    assert options.player_memory_limit == 8

    assert {:ok, created} =
             memory_correction(campaign, session, options.revision, "add", nil, %{
               "kind" => "commitment",
               "title" => "Lyra's promise",
               "details" => "Lyra promised to bring the eastern star chart after the watch.",
               "visibility" => "gm_private"
             })

    entry = Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Lyra's promise")
    assert entry.kind == :commitment
    assert entry.visibility == :public
    assert is_nil(entry.introduced_by_event_id)
    assert is_nil(entry.source_event_id)
    assert created.revision == options.revision + 1

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert [%{entry_id: entry_id, title: "Lyra's promise"}] = projection.continuity_entries
    assert entry_id == entry.entry_id

    assert {:ok, updated} =
             memory_correction(campaign, session, created.revision, "update", entry.entry_id, %{
               "kind" => "commitment",
               "title" => "Lyra's corrected promise",
               "details" => "Lyra will bring the chart before dawn."
             })

    entry = Repo.get!(ContinuityEntry, entry.id)
    assert entry.title == "Lyra's corrected promise"
    assert entry.details == "Lyra will bring the chart before dawn."
    assert is_nil(entry.introduced_by_event_id)
    assert is_nil(entry.source_event_id)

    assert {:ok, retracted} =
             memory_correction(
               campaign,
               session,
               updated.revision,
               "retract",
               entry.entry_id,
               %{}
             )

    assert Repo.get!(ContinuityEntry, entry.id).status == :retracted
    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.continuity_entries == []

    corrections =
      Repo.all(
        from correction in CanonCorrection,
          where: correction.campaign_id == ^campaign.id,
          order_by: [asc: correction.sequence]
      )

    assert Enum.map(corrections, & &1.kind) == ["memory", "memory", "memory"]

    assert Enum.map(corrections, & &1.expected_revision) == [
             options.revision,
             created.revision,
             updated.revision
           ]

    assert hd(corrections).before_state == %{"entry" => nil}
    assert hd(corrections).after_state["entry"]["visibility"] == "public"
    assert Enum.at(corrections, 1).before_state["entry"]["title"] == "Lyra's promise"
    assert List.last(corrections).after_state["entry"]["status"] == "retracted"

    assert Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count) ==
             event_count_before

    state_after = Repo.get_by!(State, campaign_id: campaign.id)
    assert state_after.public_state == state_before.public_state
    assert state_after.elapsed_world_minutes == state_before.elapsed_world_minutes
    assert retracted.revision == updated.revision + 1
  end

  test "story memory corrections reject stale and in-flight writes without changing canon" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, created} =
             memory_correction(campaign, session, state.revision, "add", nil, %{
               "kind" => "fact",
               "title" => "The silver bell",
               "details" => "The bell rings twice before sunrise."
             })

    entry = Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "The silver bell")

    assert {:error, :stale_correction} =
             memory_correction(campaign, session, state.revision, "update", entry.entry_id, %{
               "kind" => "fact",
               "title" => "Stale rewrite",
               "details" => "This stale version must not replace the saved note."
             })

    assert {:ok, %Turn{status: :pending}} =
             Play.submit_turn(campaign.id, session.id, "memory-pending-turn", "I wait quietly.")

    state_before_blocked_write = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:error, :turn_in_progress} =
             memory_correction(
               campaign,
               session,
               created.revision,
               "update",
               entry.entry_id,
               %{
                 "kind" => "fact",
                 "title" => "Blocked rewrite",
                 "details" => "The pending GM response must keep its original context."
               }
             )

    assert Repo.get!(ContinuityEntry, entry.id).title == "The silver bell"

    assert Repo.get_by!(State, campaign_id: campaign.id).revision ==
             state_before_blocked_write.revision

    assert Repo.get_by!(State, campaign_id: campaign.id).public_state ==
             state_before_blocked_write.public_state
  end

  test "player-added active memories are capped transactionally at eight" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    revision = Repo.get_by!(State, campaign_id: campaign.id).revision

    revision =
      Enum.reduce(1..8, revision, fn number, current_revision ->
        assert {:ok, result} =
                 memory_correction(campaign, session, current_revision, "add", nil, %{
                   "kind" => "fact",
                   "title" => "Remembered detail #{number}",
                   "details" => String.duplicate("A carefully bounded public story note. ", 6)
                 })

        result.revision
      end)

    assert {:error, :memory_limit_reached} =
             memory_correction(campaign, session, revision, "add", nil, %{
               "kind" => "fact",
               "title" => "Ninth note",
               "details" => "This must not push the canonical notes over their limit."
             })

    assert Repo.aggregate(
             from(entry in ContinuityEntry,
               where:
                 entry.campaign_id == ^campaign.id and entry.visibility == :public and
                   entry.status == :active and is_nil(entry.introduced_by_event_id)
             ),
             :count
           ) == 8

    assert Repo.get_by!(State, campaign_id: campaign.id).revision == revision
  end

  test "GM proposals cannot silently rewrite or retract a player-kept continuity note" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _created} =
             memory_correction(campaign, session, state.revision, "add", nil, %{
               "kind" => "fact",
               "title" => "The bodega road",
               "details" => "The trip from the Finca to the bodega takes forty minutes."
             })

    entry = Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "The bodega road")

    attempted_rewrite =
      proposal(%{
        "continuity_changes" => [
          %{
            "type" => "update",
            "entry_id" => entry.entry_id,
            "details" => "The bodega is just beside the Finca.",
            "reason" => "The GM attempts to shorten the journey without a world change."
          }
        ]
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "rewrite-player-kept-memory",
               "I ask where the bodega is.",
               provider: fn _request -> {:ok, Jason.encode!(attempted_rewrite)} end
             )

    assert Repo.get!(ContinuityEntry, entry.id).details ==
             "The trip from the Finca to the bodega takes forty minutes."
  end

  test "private GM memory cannot be corrected or shown, while public notes survive a later empty proposal" do
    campaign = campaign_fixture()
    first_session = hd(campaign.sessions)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "seed-private-memory",
               "I ask what the keeper is hiding.",
               provider: fn _request ->
                 {:ok,
                  Jason.encode!(
                    proposal(%{
                      "continuity_changes" => [
                        %{
                          "type" => "create",
                          "entry" => %{
                            "entry_id" => "hidden-chart-secret",
                            "kind" => "fact",
                            "title" => "Altered chart",
                            "details" => "The keeper secretly changed Lyra's star chart.",
                            "visibility" => "gm_private"
                          },
                          "reason" => "The GM records a concealed motive."
                        }
                      ]
                    })
                  )}
               end
             )

    hidden_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "hidden-chart-secret")

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:error, :not_found} =
             memory_correction(
               campaign,
               first_session,
               state.revision,
               "update",
               hidden_entry.entry_id,
               %{
                 "kind" => "fact",
                 "title" => "Rewrite secret",
                 "details" => "The player must not be allowed to rewrite a GM-private note."
               }
             )

    assert Repo.get!(ContinuityEntry, hidden_entry.id).details ==
             "The keeper secretly changed Lyra's star chart."

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Jason.encode!(projection) =~ "secretly changed"
    assert {:ok, options} = CanonCorrections.options(campaign.id, first_session.id)
    assert options.player_memory_count == 0

    assert {:ok, created} =
             memory_correction(campaign, first_session, state.revision, "add", nil, %{
               "kind" => "commitment",
               "title" => "Lyra's dawn delivery",
               "details" => "Lyra promised to bring the eastern star chart before dawn."
             })

    public_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Lyra's dawn delivery")

    assert {:ok, _unrelated_created} =
             memory_correction(campaign, first_session, created.revision, "add", nil, %{
               "kind" => "fact",
               "title" => "Finca pruning plan",
               "details" => "The western row will be pruned at the end of the month."
             })

    unrelated_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Finca pruning plan")

    assert Repo.get_by!(State, campaign_id: campaign.id).revision == created.revision + 1

    {:ok, next_session} = Campaigns.start_session(campaign)
    captured = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "continue-without-memory-update",
               "What was Lyra supposed to bring?",
               provider: fn request ->
                 context = decode_request(request)
                 Agent.update(captured, fn _ -> {context, request.local_context_metrics} end)
                 {:ok, Jason.encode!(proposal())}
               end
             )

    {context, metrics} = Agent.get(captured, & &1)

    assert metrics.conservative_input_token_upper_bound <= 24_000
    assert metrics.omissions == [:continuity_memory_details]

    assert Enum.any?(context["continuity"]["public"], fn entry ->
             entry["entry_id"] == public_entry.entry_id and
               entry["details"] == "Lyra promised to bring the eastern star chart before dawn." and
               entry["player_managed"]
           end)

    assert Enum.any?(context["continuity"]["public"], fn entry ->
             entry["entry_id"] == unrelated_entry.entry_id and
               entry["player_managed"] and not Map.has_key?(entry, "title") and
               not Map.has_key?(entry, "details")
           end)

    assert context["context_completeness"]["continuity_memory_details_omitted"]

    refute Jason.encode!(context["continuity"]["public"]) =~ "secretly changed"

    assert Enum.any?(context["continuity"]["gm_private"], fn entry ->
             entry["entry_id"] == hidden_entry.entry_id and
               entry["details"] == "The keeper secretly changed Lyra's star chart."
           end)

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert Enum.any?(projection.continuity_entries, &(&1.entry_id == public_entry.entry_id))

    assert Enum.any?(projection.continuity_entries, fn entry ->
             entry.entry_id == unrelated_entry.entry_id and
               entry.details == "The western row will be pruned at the end of the month."
           end)

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             state.elapsed_world_minutes

    assert Repo.all(from event in Event, where: event.campaign_id == ^campaign.id)
           |> Enum.reject(&(&1.visibility == :gm_private))
           |> Enum.all?(&(&1.event_type != :state_change))
  end

  test "retrieves a seasonal commitment from paraphrased questions in each supported language" do
    campaign = campaign_fixture()
    first_session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, relevant} =
             memory_correction(campaign, first_session, state.revision, "add", nil, %{
               "kind" => "commitment",
               "title" => "Autumn tasting reserve",
               "details" => "Keep six bottles aside for the autumn tasting."
             })

    relevant_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Autumn tasting reserve")

    assert {:ok, toll} =
             memory_correction(campaign, first_session, relevant.revision, "add", nil, %{
               "kind" => "fact",
               "title" => "Bridge toll agreement",
               "details" => "The bridge toll is waived until summer."
             })

    unrelated_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Bridge toll agreement")

    assert {:ok, same_season_revision} =
             memory_correction(campaign, first_session, toll.revision, "add", nil, %{
               "kind" => "fact",
               "title" => "Autumn roof repair",
               "details" => "Autumn rain delayed repairs to the north gate roof."
             })

    same_season_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Autumn roof repair")

    assert {:ok, _same_season_event_but_unrelated} =
             memory_correction(
               campaign,
               first_session,
               same_season_revision.revision,
               "add",
               nil,
               %{
                 "kind" => "fact",
                 "title" => "Autumn fundraiser event",
                 "details" => "The town's autumn fundraiser event paid for the north gate roof."
               }
             )

    same_season_event_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, title: "Autumn fundraiser event")

    {:ok, later_session} = Campaigns.start_session(campaign)
    captured = Agent.start_link(fn -> [] end) |> elem(1)

    narrow_questions = [
      "What quantity did we earmark for the fall event?",
      "¿Qué cantidad reservamos para el evento de otoño?",
      "Quelle quantité avons-nous réservée pour l'événement d'automne ?"
    ]

    broad_questions = [
      "Tell me about the fall event.",
      "Cuéntame sobre el evento de otoño.",
      "Parle-moi de l'événement d'automne."
    ]

    queries =
      Enum.map(narrow_questions, &{&1, [relevant_entry.entry_id]}) ++
        Enum.map(
          broad_questions,
          &{&1, [relevant_entry.entry_id, same_season_event_entry.entry_id]}
        )

    queries
    |> Enum.with_index()
    |> Enum.each(fn {{question, expected_entry_ids}, index} ->
      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 later_session.id,
                 "seasonal-memory-recall-#{index}",
                 question,
                 provider: fn request ->
                   captured_request = %{
                     context: decode_request(request),
                     metrics: request.local_context_metrics,
                     expected_entry_ids: expected_entry_ids
                   }

                   Agent.update(captured, &[captured_request | &1])
                   {:ok, Jason.encode!(proposal())}
                 end
               )
    end)

    requests = Agent.get(captured, & &1)
    assert length(requests) == length(queries)

    Enum.each(requests, fn %{context: context, metrics: metrics, expected_entry_ids: expected_ids} ->
      assert metrics.conservative_input_token_upper_bound <= 24_000

      detailed_entry_ids =
        context["continuity"]["public"]
        |> Enum.filter(&Map.has_key?(&1, "details"))
        |> Enum.map(& &1["entry_id"])
        |> MapSet.new()

      assert detailed_entry_ids == MapSet.new(expected_ids)

      assert Enum.any?(context["continuity"]["public"], fn entry ->
               entry["entry_id"] == relevant_entry.entry_id and
                 entry["details"] == "Keep six bottles aside for the autumn tasting." and
                 entry["player_managed"]
             end)

      refute Enum.any?(context["continuity"]["public"], fn entry ->
               entry["entry_id"] == unrelated_entry.entry_id and
                 (Map.has_key?(entry, "title") or Map.has_key?(entry, "details"))
             end)

      refute Enum.any?(context["continuity"]["public"], fn entry ->
               entry["entry_id"] == same_season_entry.entry_id and
                 (Map.has_key?(entry, "title") or Map.has_key?(entry, "details"))
             end)

      if Enum.member?(expected_ids, same_season_event_entry.entry_id) do
        assert Enum.any?(context["continuity"]["public"], fn entry ->
                 entry["entry_id"] == same_season_event_entry.entry_id and
                   entry["details"] ==
                     "The town's autumn fundraiser event paid for the north gate roof."
               end)
      else
        refute Enum.any?(context["continuity"]["public"], fn entry ->
                 entry["entry_id"] == same_season_event_entry.entry_id and
                   (Map.has_key?(entry, "title") or Map.has_key?(entry, "details"))
               end)
      end

      assert context["context_completeness"]["continuity_memory_details_omitted"]
    end)
  end

  defp memory_correction(campaign, session, revision, action, target_id, values) do
    CanonCorrections.correct(campaign.id, session.id, %{
      "kind" => "memory",
      "target_id" => target_id,
      "expected_revision" => revision,
      "reason" => "The player preserves a durable public story detail.",
      "values" => Map.put(values, "action", action)
    })
  end

  defp proposal(overrides \\ %{}) do
    Map.merge(
      %{
        "narration" => "The observatory settles into a quiet watch.",
        "dialogue" => [],
        "activities" => [],
        "public_changes" => %{},
        "private_changes" => %{},
        "panel_changes" => [],
        "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
        "character_updates" => [],
        "character_creations" => [],
        "inventory_changes" => [],
        "location_changes" => [],
        "travel_changes" => [],
        "objective_changes" => [],
        "continuity_changes" => [],
        "time_advance_minutes" => 0,
        "roll_request" => nil
      },
      overrides
    )
  end

  defp decode_request(request) do
    request.input
    |> hd()
    |> Map.fetch!(:content)
    |> hd()
    |> Map.fetch!(:text)
    |> Jason.decode!()
  end
end
