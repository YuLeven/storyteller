defmodule Storyteller.Play.RemoteMessageTest do
  use Storyteller.DataCase

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Play
  alias Storyteller.Play.{Character, Event, Place, PlaceConnection, State}

  test "establishes a path in a validated scene, then delivers a distinct remote message" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions
    harbor = Repo.get_by!(Place, campaign_id: campaign.id, name: "Harbor")
    island = Repo.get_by!(Place, campaign_id: campaign.id, name: "North Island")

    assert {:ok, %{status: :completed}} =
             submit(campaign, session, "establish-lyra-letter", "I speak with Lyra.",
               dialogue: [
                 %{speaker_id: "npc:lyra", text: "Leave a letter with the Harbor office clerk."}
               ],
               communication_path_changes: [
                 %{
                   type: "establish",
                   path_id: "lyra-letter",
                   speaker_id: "npc:lyra",
                   channel: "Letter",
                   endpoint: "Harbor office clerk",
                   basis_text: "Leave a letter with the Harbor office clerk.",
                   reason: "Lyra offers a public way to reach her."
                 }
               ]
             )

    state_after_path = Repo.get_by!(State, campaign_id: campaign.id)

    assert [%{"path_id" => "lyra-letter", "sender_id" => "npc:lyra", "status" => "active"}] =
             state_after_path.public_state["communication_paths"]

    assert Repo.get_by!(Event,
             campaign_id: campaign.id,
             event_type: :npc_dialogue,
             speaker_id: "npc:lyra"
           ).payload["text"] == "Leave a letter with the Harbor office clerk."

    path_audit = Repo.get_by!(Event, campaign_id: campaign.id, event_type: :state_change)
    assert path_audit.visibility == :public
    assert path_audit.payload["subject"] == "communication_paths"

    assert [
             %{
               "operation" => "establish",
               "path_id" => "lyra-letter",
               "before" => nil,
               "after" => %{
                 "channel" => "Letter",
                 "endpoint" => "Harbor office clerk",
                 "status" => "active"
               },
               "reason" => "Lyra offers a public way to reach her."
             }
           ] = path_audit.payload["changes"]

    Repo.insert!(
      PlaceConnection.changeset(%PlaceConnection{}, %{
        campaign_id: campaign.id,
        place_a_id: Enum.min([harbor.place_id, island.place_id]),
        place_b_id: Enum.max([harbor.place_id, island.place_id]),
        travel_minutes: 25,
        visibility: :public
      })
    )

    assert {:ok, %{status: :completed}} =
             submit(campaign, session, "lyra-travels-north", "Lyra sails to North Island.",
               location_changes: [
                 %{
                   type: "move_character",
                   speaker_id: "npc:lyra",
                   place_id: island.place_id,
                   reason: "Lyra sails north to meet a supplier."
                 }
               ]
             )

    player_before = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra_before = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    before_message = Repo.get_by!(State, campaign_id: campaign.id)
    connections_before = Repo.all_by(PlaceConnection, campaign_id: campaign.id)

    assert player_before.current_place_id == harbor.place_id
    assert lyra_before.current_place_id == island.place_id
    assert before_message.elapsed_world_minutes == 25

    assert {:ok, %{status: :completed}} =
             submit(campaign, session, "lyra-sends-letter", "Read the letter delivered for you.",
               remote_messages: [
                 %{
                   speaker_id: "npc:lyra",
                   path_id: "lyra-letter",
                   text: "The northern lights are clear tonight."
                 }
               ]
             )

    player_after = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra_after = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    after_message = Repo.get_by!(State, campaign_id: campaign.id)

    assert player_after.current_place_id == player_before.current_place_id
    assert lyra_after.current_place_id == lyra_before.current_place_id
    assert after_message.elapsed_world_minutes == before_message.elapsed_world_minutes

    assert Map.take(after_message.public_state, ~w(date time)) ==
             Map.take(before_message.public_state, ~w(date time))

    assert Repo.all_by(PlaceConnection, campaign_id: campaign.id) == connections_before

    remote_event =
      Repo.get_by!(Event,
        campaign_id: campaign.id,
        event_type: :remote_message,
        speaker_id: "npc:lyra"
      )

    assert remote_event.payload["path_id"] == "lyra-letter"
    assert remote_event.payload["text"] == "The northern lights are clear tonight."

    refute Repo.exists?(
             from event in Event,
               where:
                 event.campaign_id == ^campaign.id and event.turn_id == ^remote_event.turn_id and
                   event.event_type == :npc_dialogue and event.speaker_id == "npc:lyra"
           )

    assert {:ok, %{events: story_events}} = Play.public_story_timeline_page(campaign.id)

    [player_action, narration, message] =
      Enum.filter(story_events, &(&1.turn_id == remote_event.turn_id))

    assert Enum.map([player_action, narration, message], & &1.event_type) == [
             :player_action,
             :gm_narration,
             :remote_message
           ]

    assert message.payload["text"] == "The northern lights are clear tonight."

    assert {:ok, backup} = CampaignBackup.export(campaign.id)
    assert Jason.decode!(backup)["schema_version"] == 14
    assert {:ok, imported} = CampaignBackup.import(backup)
    imported_state = Repo.get_by!(State, campaign_id: imported.id)

    assert imported_state.public_state["communication_paths"] ==
             after_message.public_state["communication_paths"]

    assert Repo.get_by!(Event, campaign_id: imported.id, event_type: :remote_message).payload[
             "path_id"
           ] == "lyra-letter"
  end

  test "rejects remote messages when the path is missing, inactive, or belongs to another sender" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions
    state = Repo.get_by!(State, campaign_id: campaign.id)

    paths = [
      %{
        "path_id" => "lyra-letter",
        "sender_id" => "npc:lyra",
        "recipient_id" => "player",
        "channel" => "Letter",
        "endpoint" => "Harbor office",
        "status" => "active"
      },
      %{
        "path_id" => "lyra-old-channel",
        "sender_id" => "npc:lyra",
        "recipient_id" => "player",
        "channel" => "Letter",
        "endpoint" => "Closed Harbor office",
        "status" => "inactive"
      }
    ]

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "communication_paths", paths)
      })
    )

    for {key, message} <- [
          {"missing-path", %{speaker_id: "npc:lyra", path_id: "not-established", text: "Hello."}},
          {"inactive-path",
           %{speaker_id: "npc:lyra", path_id: "lyra-old-channel", text: "Hello."}},
          {"mismatched-path", %{speaker_id: "npc:orin", path_id: "lyra-letter", text: "Hello."}}
        ] do
      assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
               submit(campaign, session, key, "A message arrives.", remote_messages: [message])
    end

    refute Repo.exists?(
             from event in Event,
               where: event.campaign_id == ^campaign.id and event.event_type == :remote_message
           )
  end

  test "only active public sender paths are included in bounded GM context" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions
    state = Repo.get_by!(State, campaign_id: campaign.id)
    captured = Agent.start_link(fn -> nil end) |> elem(1)

    lyra_path = %{
      "path_id" => "lyra-letter",
      "sender_id" => "npc:lyra",
      "recipient_id" => "player",
      "channel" => "Letter",
      "endpoint" => "Public harbor office",
      "status" => "active"
    }

    unrelated_paths =
      for index <- 1..40 do
        %{
          "path_id" => "unrelated-route-#{index}",
          "sender_id" => "npc:unrelated-#{index}",
          "recipient_id" => "player",
          "channel" => "Courier pigeon",
          "endpoint" => "Remote post #{index}",
          "status" => "active"
        }
      end

    paths =
      [lyra_path] ++
        unrelated_paths ++
        [
          %{
            "path_id" => "lyra-old-channel",
            "sender_id" => "npc:lyra",
            "recipient_id" => "player",
            "channel" => "Letter",
            "endpoint" => "Private sealed archive",
            "status" => "inactive"
          }
        ]

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "communication_paths", paths)
      })
    )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "bounded-path-context",
               "Deliver a letter from Lyra through the public harbor office path.",
               provider: fn request ->
                 context = decode_request(request)
                 Agent.update(captured, fn _ -> {context, request.local_context_metrics} end)
                 {:ok, Jason.encode!(base_proposal())}
               end,
               model: "remote-message-context-test"
             )

    {context, metrics} = Agent.get(captured, & &1)

    assert Enum.any?(context["communication_paths"], fn path ->
             path["path_id"] == "lyra-letter" and
               path["endpoint"] == "Public harbor office"
           end)

    assert length(context["communication_paths"]) == 12
    refute Jason.encode!(context) =~ "Private sealed archive"
    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert metrics.section_bytes.section_communication_paths_bytes > 0
    assert metrics.section_bytes.section_communication_paths_bytes <= 6_000
  end

  test "rejects an attempted path that is not established by an in-scene NPC utterance" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "path-without-dialogue", "I think Lyra can be reached.",
               communication_path_changes: [
                 %{
                   type: "establish",
                   path_id: "invented-channel",
                   speaker_id: "npc:lyra",
                   channel: "Letter",
                   endpoint: "The harbor office",
                   basis_text: "Leave a letter at the harbor office.",
                   reason: "The GM wants Lyra to send a letter."
                 }
               ]
             )

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "path-with-substring-endpoint", "I speak with Lyra.",
               dialogue: [%{speaker_id: "npc:lyra", text: "The Harbor officer handles letters."}],
               communication_path_changes: [
                 %{
                   type: "establish",
                   path_id: "substring-endpoint",
                   speaker_id: "npc:lyra",
                   channel: "Letter",
                   endpoint: "Harbor office",
                   basis_text: "The Harbor officer handles letters.",
                   reason: "The GM wants a remote channel."
                 }
               ]
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)
    refute Map.has_key?(state.public_state, "communication_paths")

    unvalidated_path = %{
      "path_id" => "unvalidated-letter",
      "sender_id" => "npc:lyra",
      "recipient_id" => "player",
      "channel" => "Letter",
      "endpoint" => "Harbor office clerk",
      "status" => "active"
    }

    for {key, field} <- [
          {"direct-public-ledger-seed", "communication_paths"},
          {"normalized-public-ledger-alias", "Communication-Paths"}
        ] do
      assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
               submit(campaign, session, key, "Lyra can be reached by letter.",
                 public_changes: %{field => [unvalidated_path]}
               )
    end

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "deliver-over-unvalidated-route", "Read Lyra's letter.",
               remote_messages: [
                 %{
                   speaker_id: "npc:lyra",
                   path_id: "unvalidated-letter",
                   text: "The island is quiet tonight."
                 }
               ]
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)
    refute Map.has_key?(state.public_state, "communication_paths")

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "path-with-hidden-endpoint", "I speak with Lyra.",
               dialogue: [%{speaker_id: "npc:lyra", text: "You can reach me by letter."}],
               communication_path_changes: [
                 %{
                   type: "establish",
                   path_id: "hidden-endpoint",
                   speaker_id: "npc:lyra",
                   channel: "Letter",
                   endpoint: "Harbor office clerk",
                   basis_text: "You can reach me by letter.",
                   reason: "The GM wants a remote channel."
                 }
               ]
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)
    refute Map.has_key?(state.public_state, "communication_paths")
  end

  test "a remote delivery cannot move anyone or advance time or travel" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions
    harbor = Repo.get_by!(Place, campaign_id: campaign.id, name: "Harbor")
    island = Repo.get_by!(Place, campaign_id: campaign.id, name: "North Island")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.insert!(
      PlaceConnection.changeset(%PlaceConnection{}, %{
        campaign_id: campaign.id,
        place_a_id: Enum.min([harbor.place_id, island.place_id]),
        place_b_id: Enum.max([harbor.place_id, island.place_id]),
        travel_minutes: 25,
        visibility: :public
      })
    )

    path = %{
      "path_id" => "lyra-letter",
      "sender_id" => "npc:lyra",
      "recipient_id" => "player",
      "channel" => "Letter",
      "endpoint" => "Harbor office",
      "status" => "active"
    }

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "communication_paths", [path])
      })
    )

    lyra_before = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "message-with-movement", "A message arrives.",
               remote_messages: [
                 %{speaker_id: "npc:lyra", path_id: "lyra-letter", text: "Meet me soon."}
               ],
               location_changes: [
                 %{
                   type: "move_character",
                   speaker_id: "npc:lyra",
                   place_id: island.place_id,
                   reason: "Lyra sails to North Island."
                 }
               ]
             )

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             submit(campaign, session, "message-with-time", "A message arrives.",
               remote_messages: [
                 %{speaker_id: "npc:lyra", path_id: "lyra-letter", text: "Meet me soon."}
               ],
               time_advance_minutes: 60
             )

    lyra_after = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    state_after = Repo.get_by!(State, campaign_id: campaign.id)
    assert lyra_after.current_place_id == lyra_before.current_place_id
    assert state_after.elapsed_world_minutes == state.elapsed_world_minutes

    refute Repo.exists?(
             from event in Event,
               where: event.campaign_id == ^campaign.id and event.event_type == :remote_message
           )
  end

  test "path deactivation records public before and after canon outside the story timeline" do
    campaign = campaign_with_remote_characters()
    [session] = campaign.sessions
    state = Repo.get_by!(State, campaign_id: campaign.id)

    path = %{
      "path_id" => "lyra-letter",
      "sender_id" => "npc:lyra",
      "recipient_id" => "player",
      "channel" => "Letter",
      "endpoint" => "Harbor office clerk",
      "status" => "active"
    }

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "communication_paths", [path])
      })
    )

    assert {:ok, %{status: :completed}} =
             submit(
               campaign,
               session,
               "deactivate-lyra-letter",
               "I can no longer use that route.",
               communication_path_changes: [
                 %{
                   type: "deactivate",
                   path_id: "lyra-letter",
                   reason: "The Harbor office has closed."
                 }
               ]
             )

    state_after = Repo.get_by!(State, campaign_id: campaign.id)

    assert [inactive_path] = state_after.public_state["communication_paths"]
    assert inactive_path["status"] == "inactive"

    audit = Repo.get_by!(Event, campaign_id: campaign.id, event_type: :state_change)

    assert [
             %{
               "operation" => "deactivate",
               "path_id" => "lyra-letter",
               "before" => %{"status" => "active", "endpoint" => "Harbor office clerk"},
               "after" => %{"status" => "inactive", "endpoint" => "Harbor office clerk"},
               "reason" => "The Harbor office has closed."
             }
           ] = audit.payload["changes"]

    assert {:ok, %{events: story_events}} = Play.public_story_timeline_page(campaign.id)

    refute Enum.any?(
             story_events,
             &(&1.turn_id == audit.turn_id and &1.event_type == :state_change)
           )
  end

  defp decode_request(request) do
    request.input
    |> Enum.find(&Map.has_key?(&1, :content))
    |> Map.fetch!(:content)
    |> Jason.decode!()
  end

  defp campaign_with_remote_characters do
    campaign_fixture(%{
      starting_location: "Harbor",
      starting_date: "The 2nd day of thaw",
      world_time: "First watch",
      gm_characters: [
        %{speaker_id: "npc:lyra", name: "Lyra", starting_place: "Harbor"},
        %{speaker_id: "npc:orin", name: "Orin", starting_place: "North Island"}
      ]
    })
  end

  defp submit(campaign, session, key, input, overrides) do
    proposal = Map.merge(base_proposal(), Map.new(overrides))

    Play.submit_turn(campaign.id, session.id, key, input,
      provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
      model: "remote-message-test"
    )
  end

  defp base_proposal do
    %{
      narration: "The harbor settles into its evening rhythm.",
      dialogue: [],
      activities: [],
      remote_messages: [],
      communication_path_changes: [],
      public_changes: %{},
      private_changes: %{},
      panel_changes: [],
      character_updates: [],
      character_creations: [],
      inventory_changes: [],
      location_changes: [],
      travel_changes: [],
      objective_changes: [],
      continuity_changes: [],
      memory_update: %{public_summary: "", gm_private_summary: ""},
      time_advance_minutes: 0,
      roll_request: nil
    }
  end
end
