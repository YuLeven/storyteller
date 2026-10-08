defmodule Storyteller.Play.FirstAppearanceTest do
  use Storyteller.DataCase

  import Storyteller.CampaignFixtures

  alias Storyteller.Play
  alias Storyteller.Play.{Event, State, Turn}

  test "a present setup NPC is naturally introduced from public facts before speaking" do
    {campaign, session} = setup_scene("The First Appearance Tea House")
    captured = Agent.start_link(fn -> nil end) |> elem(1)
    public_detail = "A soot-smudged keeper with rosemary on his sleeves."
    private_detail = "Secretly carrying the sealed letter."

    provider = fn request ->
      context = decode_request(request)
      npc = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:tomas"))
      Agent.update(captured, fn _ -> %{context: context, instructions: request.instructions} end)

      narration =
        if npc["first_story_appearance"] do
          "Tomas, soot-smudged with rosemary on his sleeves, is sorting the tea tins."
        else
          "The tea tins settle into a quiet row."
        end

      {:ok,
       Jason.encode!(
         proposal(%{
           "narration" => narration,
           "dialogue" => [%{"speaker_id" => "npc:tomas", "text" => "The kettle is nearly ready."}]
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "first-appearance", "I look around.",
               provider: provider,
               model: "test-model"
             )

    %{context: context, instructions: instructions} = Agent.get(captured, & &1)
    instructions = String.replace(instructions, ~r/\s+/, " ")
    npc = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:tomas"))

    assert npc["current_place_id"] ==
             Enum.find(context["characters"], &(&1["speaker_id"] == "player"))["current_place_id"]

    assert npc["first_story_appearance"]
    assert npc["visible_facts"]["description"] == public_detail
    assert npc["gm_private_facts"]["secret"] == private_detail
    assert instructions =~ "first_story_appearance=true"
    assert instructions =~ "a relevant visible fact"
    assert instructions =~ "false means don't reintroduce"
    assert instructions =~ "When history_omitted"
    assert instructions =~ "invent no missing events; preserve uncertainty"

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    story_events = Enum.filter(timeline, &(&1.event_type in [:gm_narration, :npc_dialogue]))
    assert Enum.map(story_events, & &1.event_type) == [:gm_narration, :npc_dialogue]

    narration = hd(story_events).payload["text"]
    assert narration =~ "Tomas"
    assert narration =~ "rosemary"
    refute narration =~ "NEW CHARACTER"
    refute narration =~ private_detail
  end

  test "a public first mention beyond retained history prevents re-introduction" do
    {campaign, session} = setup_scene("The Durable Appearance Tea House")
    marker = "Tomas lifts the chipped blue kettle from the warmer."

    intro_provider = fn request ->
      context = decode_request(request)
      npc = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:tomas"))
      assert npc["first_story_appearance"]

      {:ok, Jason.encode!(proposal(%{"narration" => marker, "dialogue" => []}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "record-old-appearance", "I enter.",
               provider: intro_provider,
               model: "test-model"
             )

    seed_turn =
      Repo.get_by!(Turn, campaign_id: campaign.id, idempotency_key: "record-old-appearance")

    state = Repo.get_by!(State, campaign_id: campaign.id)
    first_sequence = state.event_sequence + 1
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    old_place_events =
      Enum.map(1..81, fn offset ->
        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: seed_turn.id,
          sequence: first_sequence + offset - 1,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "The Tea House shutters tremble in the evening breeze."},
          inserted_at: now
        }
      end)

    assert {81, nil} = Repo.insert_all(Event, old_place_events)
    last_sequence = first_sequence + 80
    Repo.update!(State.changeset(state, %{event_sequence: last_sequence}))

    captured = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      npc = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:tomas"))
      Agent.update(captured, fn _ -> context end)

      narration =
        if npc["first_story_appearance"] do
          "Tomas, the new face by the blue kettle, takes a step closer."
        else
          "The tea house keeps its calm as the kettle begins to sing."
        end

      {:ok,
       Jason.encode!(
         proposal(%{
           "narration" => narration,
           "dialogue" => [%{"speaker_id" => "npc:tomas", "text" => "It should be ready soon."}]
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "established-appearance",
               "What does Tomas say?",
               provider: provider,
               model: "test-model"
             )

    context = Agent.get(captured, & &1)
    npc = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:tomas"))
    refute npc["first_story_appearance"]

    refute Enum.any?(context["history"], fn event ->
             get_in(event, ["payload", "text"]) == marker
           end)

    assert {:ok, timeline} = Play.public_timeline(campaign.id)

    latest_turn =
      Repo.get_by!(Turn, campaign_id: campaign.id, idempotency_key: "established-appearance")

    latest_story_events =
      Enum.filter(timeline, fn event ->
        event.turn_id == latest_turn.id and event.event_type in [:gm_narration, :npc_dialogue]
      end)

    [latest_narration | _] = latest_story_events

    assert latest_narration.payload["text"] ==
             "The tea house keeps its calm as the kettle begins to sing."

    refute latest_narration.payload["text"] =~ "new face"
  end

  defp setup_scene(title) do
    campaign = campaign_fixture(%{title: title})
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)
    place_name = "The Tea House"

    Repo.update!(
      State.changeset(state, %{
        public_state: %{
          "weather" => "Clear",
          "location" => place_name,
          "world_time" => "First watch"
        },
        elapsed_world_anchor: %{"time" => "First watch"}
      })
    )

    assert {:ok, _state} =
             Play.initialize_campaign(campaign, %{
               characters: [
                 %{
                   speaker_id: "npc:tomas",
                   name: "Tomas",
                   initial_location: place_name,
                   visible_facts: %{
                     "description" => "A soot-smudged keeper with rosemary on his sleeves."
                   },
                   gm_private_facts: %{"secret" => "Secretly carrying the sealed letter."}
                 }
               ]
             })

    {campaign, session}
  end

  defp proposal(overrides) do
    Map.merge(
      %{
        "narration" => "",
        "dialogue" => [],
        "activities" => [],
        "remote_messages" => [],
        "public_changes" => %{},
        "private_changes" => %{},
        "panel_changes" => [],
        "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
        "character_updates" => [],
        "character_creations" => [],
        "location_changes" => [],
        "travel_changes" => [],
        "inventory_changes" => [],
        "objective_changes" => [],
        "continuity_changes" => [],
        "communication_path_changes" => [],
        "time_advance_minutes" => 0,
        "roll_request" => nil
      },
      overrides
    )
  end

  defp decode_request(request) do
    request.input
    |> Enum.find(&Map.has_key?(&1, :content))
    |> Map.fetch!(:content)
    |> Jason.decode!()
  end
end
