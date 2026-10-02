defmodule Storyteller.CampaignBackupTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.AuthoringCorrection
  alias Storyteller.Auth.TokenStore
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play

  alias Storyteller.Play.{
    CanonCorrection,
    CanonCorrections,
    Character,
    ContinuityEntry,
    Event,
    Objective,
    Place,
    PlaceConnection,
    Roll,
    State,
    Turn
  }

  alias Storyteller.Repo

  test "round-trips complete multi-session canon and remaps internal provenance IDs" do
    campaign =
      campaign_fixture(%{
        player_character_name: "Mira Vale",
        starting_location: "Villa terrace",
        starting_date: "14 October 1567",
        world_time: "First watch",
        weather: "Low fog",
        gm_characters: [
          %{
            speaker_id: "npc:lyra",
            name: "Lyra",
            visible_facts: %{"role" => "keeper"},
            gm_private_facts: %{"motive" => "Protect the star chart."}
          }
        ],
        inventory: [
          %{name: "Cellar key", quantity: 1, category: "Key", description: "Worn brass."}
        ],
        panel_fields: [
          %{
            key: "wine_stock",
            panel: "Cellar",
            label: "Wine in store",
            value_type: "quantity",
            unit: "barrels",
            visibility: "public",
            initial_value: "8"
          },
          %{
            key: "hidden_reserve",
            panel: "GM notes",
            label: "Hidden reserve",
            value_type: "text",
            visibility: "gm_private",
            initial_value: "Three sealed bottles beneath the north stair."
          }
        ]
      })

    villa = Repo.get_by!(Place, campaign_id: campaign.id, name: "Villa terrace")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "backup-bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    [place_a_id, place_b_id] = Enum.sort([villa.place_id, bodega.place_id])

    Repo.insert!(
      PlaceConnection.changeset(%PlaceConnection{}, %{
        campaign_id: campaign.id,
        place_a_id: place_a_id,
        place_b_id: place_b_id,
        travel_minutes: 40,
        scene_relevance: "The road from the villa to the cellar.",
        visibility: :public
      })
    )

    assert {:ok, campaign_with_public_correction} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Clarify the backup campaign title.",
               "title" => "The Villa Ledger, Revised"
             })

    assert {:ok, _campaign_with_private_correction} =
             Campaigns.update_campaign_authoring(campaign_with_public_correction, %{
               "correction_reason" => "Record the GM-only cellar discovery.",
               "gm_character_setup" => %{
                 "npc:lyra" => %{"private_notes" => "A second ledger is under the stair."}
               }
             })

    campaign = Campaigns.get_campaign!(campaign.id)

    [first_session] = campaign.sessions

    assert {:ok, first_turn} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "backup-turn-one",
               "I ask Lyra about the harvest.",
               provider: fake_provider("Lyra studies the ledger before answering."),
               model: "backup-test"
             )

    assert first_turn.status == :completed

    assert {:ok, second_session} =
             Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{
               title: "The sealed cellar"
             })

    assert {:ok, second_turn} =
             Play.submit_turn(
               campaign.id,
               second_session.id,
               "backup-turn-two",
               "I check the stores.",
               provider: fake_provider("The cellar ledger balances to the last barrel."),
               model: "backup-test"
             )

    assert second_turn.status == :completed

    assert {:ok, correction_options} = CanonCorrections.options(campaign.id, second_session.id)

    assert {:ok, _resource_correction} =
             CanonCorrections.correct(campaign.id, second_session.id, %{
               "kind" => "resource",
               "target_id" => "wine_stock",
               "expected_revision" => correction_options.revision,
               "reason" => "A physical count found seven barrels.",
               "values" => %{"value" => "7"}
             })

    pending_turn =
      Repo.insert!(
        Turn.changeset(%Turn{}, %{
          campaign_id: campaign.id,
          session_id: second_session.id,
          idempotency_key: "backup-pending-turn",
          request_hash:
            :crypto.hash(:sha256, "#{second_session.id}\0I am still waiting for this turn.")
            |> Base.encode16(case: :lower),
          player_input: "I am still waiting for this turn.",
          status: :pending,
          resolution_phase: :initial,
          attempts: 0
        })
      )

    private_place =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "sealed-cellar",
          name: "Sealed cellar",
          description: "A room kept from the player's view.",
          visibility: :gm_private,
          facts: %{"entry" => "Behind the north stair."}
        })
      )

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: private_place.place_id}))

    state = Repo.get_by!(State, campaign_id: campaign.id)

    private_item = %{
      "id" => "lyras-hidden-key",
      "name" => "Black iron key",
      "quantity" => 1,
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{"engraving" => "V-17"}
    }

    Repo.update!(
      State.changeset(state, %{
        gm_private_state:
          state.gm_private_state
          |> Map.put("inventory", [private_item])
          |> Map.put("history_clue", "A second ledger is hidden below the stair.")
      })
    )

    Repo.insert!(
      Objective.changeset(%Objective{}, %{
        campaign_id: campaign.id,
        objective_id: "find-the-second-ledger",
        title: "Find the second ledger",
        details: "It records who removed the bottles.",
        status: :open,
        visibility: :gm_private
      })
    )

    narration_events =
      Repo.all(
        from(event in Event,
          where: event.campaign_id == ^campaign.id and event.event_type == :gm_narration,
          order_by: [asc: event.sequence]
        )
      )

    [first_narration, second_narration] = narration_events

    private_entry = %{
      campaign_id: campaign.id,
      entry_id: "lyra-secret-commitment",
      kind: :commitment,
      title: "Lyra's hidden promise",
      details: "She promised to return the black iron key before dawn.",
      status: :active,
      visibility: :gm_private,
      introduced_by_event_id: first_narration.id,
      source_event_id: first_narration.id
    }

    public_entry = %{
      campaign_id: campaign.id,
      entry_id: "harvest-ledger-promise",
      kind: :commitment,
      title: "The harvest ledger promise",
      details: "The totals must be checked before the next market day.",
      status: :resolved,
      visibility: :public,
      introduced_by_event_id: first_narration.id,
      source_event_id: second_narration.id
    }

    Repo.insert!(ContinuityEntry.changeset(%ContinuityEntry{}, private_entry))
    Repo.insert!(ContinuityEntry.changeset(%ContinuityEntry{}, public_entry))

    authorized_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.insert!(
      Roll.changeset(%Roll{}, %{
        turn_id: second_turn.id,
        kind: :player_click,
        result: 17,
        authorized_at: authorized_at
      })
    )

    previous_token_store = Application.get_env(:storyteller, TokenStore, :not_configured)

    credential_path =
      Path.join(System.tmp_dir!(), "storyteller-token-sentinel-#{Ecto.UUID.generate()}.json")

    token_sentinel = "OAUTH-CREDENTIAL-SENTINEL-#{Ecto.UUID.generate()}"
    File.write!(credential_path, Jason.encode!(%{"access_token" => token_sentinel}))
    Application.put_env(:storyteller, TokenStore, path: credential_path)

    on_exit(fn ->
      File.rm(credential_path)

      case previous_token_store do
        :not_configured -> Application.delete_env(:storyteller, TokenStore)
        value -> Application.put_env(:storyteller, TokenStore, value)
      end
    end)

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    refute backup_json =~ token_sentinel
    refute backup_json =~ "access_token"

    document = Jason.decode!(backup_json)
    assert document["data_classification"] == "sensitive_gm_private_campaign_data"
    assert document["schema_version"] == 11
    assert length(document["canon_corrections"]) == 1
    assert hd(document["canon_corrections"])["after_state"]["value"] == 7
    assert document["campaign"]["title"] == campaign.title
    assert document["campaign"]["player_character_name"] == "Mira Vale"
    assert document["campaign"]["player_character"] == campaign.player_character
    assert length(document["authoring_corrections"]) == 2
    assert Enum.any?(document["authoring_corrections"], & &1["contains_private_changes"])
    assert document["state"]["gm_private_state"]["history_clue"]

    exported_player = Enum.find(document["characters"], &(&1["speaker_id"] == "player"))
    assert exported_player["name"] == "Mira Vale"
    assert exported_player["visible_facts"]["description"] == campaign.player_character

    assert Enum.any?(
             document["characters"],
             &(&1["gm_private_facts"]["motive"] == "Protect the star chart.")
           )

    assert Enum.any?(document["places"], &(&1["visibility"] == "gm_private"))
    assert length(document["place_connections"]) == 1
    assert hd(document["place_connections"])["travel_minutes"] == 40
    assert Enum.any?(document["panels"], &(&1["visibility"] == "gm_private"))
    assert Enum.any?(document["objectives"], &(&1["visibility"] == "gm_private"))
    assert Enum.any?(document["continuity_entries"], &(&1["visibility"] == "gm_private"))
    assert Enum.any?(document["rolls"], &(&1["result"] == 17))
    assert Enum.any?(document["events"], &(&1["game_time"]["date"] == "14 October 1567"))

    original_state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, imported} = CampaignBackup.import(backup_json)
    refute imported.id == campaign.id

    imported_campaign = Campaigns.get_campaign!(imported.id)
    assert imported_campaign.title == campaign.title
    assert imported_campaign.player_character_name == "Mira Vale"
    assert imported_campaign.player_character == campaign.player_character

    imported_corrections =
      Repo.all(
        from(correction in AuthoringCorrection,
          where: correction.campaign_id == ^imported.id,
          order_by: [asc: correction.sequence]
        )
      )

    assert Enum.map(
             imported_corrections,
             &{&1.sequence, &1.reason, &1.before_state, &1.after_state}
           ) ==
             Enum.map(document["authoring_corrections"], fn correction ->
               {correction["sequence"], correction["reason"], correction["before_state"],
                correction["after_state"]}
             end)

    assert Enum.map(imported_corrections, & &1.contains_private_changes) == [false, true]

    imported_canon_corrections =
      Repo.all(
        from(correction in CanonCorrection,
          where: correction.campaign_id == ^imported.id,
          order_by: [asc: correction.sequence]
        )
      )

    assert Enum.map(imported_canon_corrections, &{&1.sequence, &1.kind, &1.reason}) ==
             Enum.map(document["canon_corrections"], fn correction ->
               {correction["sequence"], correction["kind"], correction["reason"]}
             end)

    imported_player = Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "player")
    assert imported_player.name == "Mira Vale"
    assert imported_player.visible_facts["description"] == campaign.player_character

    assert Enum.map(imported_campaign.sessions, &{&1.title, &1.status}) |> MapSet.new() ==
             MapSet.new([{"Session 1", :completed}, {"The sealed cellar", :active}])

    imported_state = Repo.get_by!(State, campaign_id: imported.id)
    assert imported_state.public_state == original_state.public_state
    assert imported_state.gm_private_state == original_state.gm_private_state
    assert imported_state.elapsed_world_minutes == original_state.elapsed_world_minutes

    assert imported_state.elapsed_world_anchor_minutes ==
             original_state.elapsed_world_anchor_minutes

    assert imported_state.elapsed_world_anchor == original_state.elapsed_world_anchor
    assert imported_state.public_history_summary == original_state.public_history_summary
    assert imported_state.gm_private_history_summary == original_state.gm_private_history_summary

    imported_turns = Repo.all(from(turn in Turn, where: turn.campaign_id == ^imported.id))

    assert Enum.map(imported_turns, & &1.player_input) |> MapSet.new() ==
             MapSet.new([
               "I ask Lyra about the harvest.",
               "I check the stores.",
               "I am still waiting for this turn."
             ])

    imported_pending_turn =
      Enum.find(imported_turns, &(&1.idempotency_key == "backup-pending-turn"))

    assert pending_turn.status == :pending
    assert imported_pending_turn.status == :failed
    assert imported_pending_turn.failure_code == "backup_interrupted"
    assert imported_pending_turn.resolution_started_at == nil

    first_imported_turn = Enum.find(imported_turns, &(&1.idempotency_key == "backup-turn-one"))

    first_imported_session =
      Repo.get!(Storyteller.Campaigns.Session, first_imported_turn.session_id)

    refute first_imported_session.id == first_session.id
    assert first_imported_turn.request_hash != first_turn.request_hash

    imported_events =
      Repo.all(
        from(event in Event,
          where: event.campaign_id == ^imported.id,
          order_by: [asc: event.sequence]
        )
      )

    assert Enum.map(imported_events, & &1.sequence) ==
             Enum.map(document["events"], & &1["sequence"])

    assert Enum.any?(imported_events, &(&1.visibility == :gm_private))
    assert Enum.any?(imported_events, &(&1.game_time["date"] == "14 October 1567"))

    imported_private_entry =
      Repo.get_by!(ContinuityEntry, campaign_id: imported.id, entry_id: "lyra-secret-commitment")

    introduced_event = Repo.get!(Event, imported_private_entry.introduced_by_event_id)
    source_event = Repo.get!(Event, imported_private_entry.source_event_id)
    assert introduced_event.sequence == first_narration.sequence
    assert source_event.sequence == first_narration.sequence
    refute introduced_event.id == first_narration.id

    assert Repo.get_by!(Roll,
             turn_id: Enum.find(imported_turns, &(&1.idempotency_key == "backup-turn-two")).id
           ).result == 17

    assert Repo.get_by!(PanelField, campaign_id: imported.id, key: "hidden_reserve").visibility ==
             :gm_private

    imported_character = Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "npc:lyra")
    assert imported_character.current_place_id == "sealed-cellar"

    assert Repo.get_by!(Place, campaign_id: imported.id, place_id: "sealed-cellar").visibility ==
             :gm_private

    imported_connection = Repo.get_by!(PlaceConnection, campaign_id: imported.id)
    assert imported_connection.travel_minutes == 40
    assert imported_connection.scene_relevance == "The road from the villa to the cellar."
  end

  test "round-trips active GM duties and preserves their authoring audit snapshot" do
    campaign =
      campaign_fixture(%{
        starting_location: "Finca",
        gm_characters: [%{speaker_id: "npc:keeper", name: "Keeper"}]
      })

    finca = Repo.get_by!(Place, campaign_id: campaign.id, name: "Finca")

    another_place =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "north-cellar",
          name: "North cellar",
          visibility: :public,
          facts: %{}
        })
      )

    keeper = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:keeper")

    Repo.update!(Character.changeset(keeper, %{current_place_id: finca.place_id}))

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "expected_revision" => state.revision,
               "correction_reason" => "Assign the keeper's cellar rounds.",
               "character_active_duties" => %{
                 "npc:keeper" => %{
                   "duty_name" => "Check the reserve casks",
                   "duty_duration_minutes" => "30"
                 }
               }
             })

    assert {:ok, json} = CampaignBackup.export(campaign.id)
    document = Jason.decode!(json)
    assert document["schema_version"] == 11

    exported_keeper = Enum.find(document["characters"], &(&1["speaker_id"] == "npc:keeper"))
    assert exported_keeper["duty_name"] == "Check the reserve casks"
    assert exported_keeper["duty_place_id"] == finca.place_id
    assert exported_keeper["duty_release_at_world_minute"] == 30

    [correction] = document["authoring_corrections"]
    assert correction["contains_private_changes"]

    assert correction["before_state"]["gm_characters"]["npc:keeper"]["active_duty"] == %{
             "name" => nil,
             "place_id" => nil,
             "release_at_world_minute" => nil
           }

    assert correction["after_state"]["gm_characters"]["npc:keeper"]["active_duty"] == %{
             "name" => "Check the reserve casks",
             "place_id" => finca.place_id,
             "release_at_world_minute" => "30"
           }

    imported_count = Repo.aggregate(Storyteller.Campaigns.Campaign, :count, :id)
    wrong_place = put_character(document, "npc:keeper", "duty_place_id", another_place.place_id)

    player = Enum.find(document["characters"], &(&1["speaker_id"] == "player"))

    player_duty =
      put_character(document, "player", "duty_name", "Count the harvest")
      |> put_character("player", "duty_place_id", player["current_place_id"])

    for invalid <- [wrong_place, player_duty] do
      assert {:error, :invalid_backup} = CampaignBackup.import(Jason.encode!(invalid))
      assert Repo.aggregate(Storyteller.Campaigns.Campaign, :count, :id) == imported_count
    end

    assert {:ok, imported} = CampaignBackup.import(json)
    imported_keeper = Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "npc:keeper")
    assert imported_keeper.duty_name == "Check the reserve casks"
    assert imported_keeper.duty_place_id == finca.place_id
    assert imported_keeper.duty_release_at_world_minute == 30

    imported_correction = Repo.get_by!(AuthoringCorrection, campaign_id: imported.id)
    assert imported_correction.before_state == correction["before_state"]
    assert imported_correction.after_state == correction["after_state"]
    assert imported_correction.contains_private_changes
    assert Campaigns.list_public_authoring_corrections(imported.id) == []
  end

  test "version eight backups import without active duties" do
    campaign =
      campaign_fixture(%{
        starting_location: "Finca",
        gm_characters: [%{speaker_id: "npc:keeper", name: "Keeper"}]
      })

    assert {:ok, json} = CampaignBackup.export(campaign.id)
    legacy = Jason.decode!(json) |> pre_active_duties(8)

    assert {:ok, imported} = CampaignBackup.import(Jason.encode!(legacy))

    imported_character =
      Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "npc:keeper")

    assert is_nil(imported_character.duty_name)
    assert is_nil(imported_character.duty_place_id)
  end

  test "version nine backups keep indefinite duties without fabricating a release threshold" do
    campaign =
      campaign_fixture(%{
        starting_location: "Finca",
        gm_characters: [
          %{
            speaker_id: "npc:keeper",
            name: "Keeper",
            starting_place: "Finca",
            active_duty_name: "Remain at the press"
          }
        ]
      })

    assert {:ok, json} = CampaignBackup.export(campaign.id)
    legacy = Jason.decode!(json) |> pre_active_duties(9)
    assert {:ok, imported} = CampaignBackup.import(Jason.encode!(legacy))

    imported_keeper = Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "npc:keeper")
    assert imported_keeper.duty_name == "Remain at the press"
    assert imported_keeper.duty_place_id == imported_keeper.current_place_id
    assert is_nil(imported_keeper.duty_release_at_world_minute)

    imported_state = Repo.get_by!(State, campaign_id: imported.id)
    assert Map.get(imported_state.public_state, "communication_paths", []) == []
  end

  test "rejects unknown versions, secret-bearing extra fields, and dangling references before writing" do
    campaign = campaign_fixture(%{starting_location: "The west terrace"})
    [session] = campaign.sessions

    assert {:ok, _turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "backup-validation-turn",
               "I look over the terrace.",
               provider: fake_provider("The terrace is quiet beneath the autumn mist."),
               model: "backup-test"
             )

    assert {:ok, json} = CampaignBackup.export(campaign.id)
    decoded = Jason.decode!(json)
    initial_count = Repo.aggregate(Storyteller.Campaigns.Campaign, :count, :id)

    [event | _] = decoded["events"]
    [place | remaining_places] = decoded["places"]
    [character | remaining_characters] = decoded["characters"]

    for invalid <- [
          Map.put(decoded, "schema_version", 12),
          Map.put(decoded, "canon_corrections", [%{"sequence" => 1}]),
          Map.put(decoded, "oauth_credentials", %{"access_token" => "must-not-import"}),
          put_in(decoded, ["events", Access.at(0), "turn_ref"], "turn-999"),
          put_in(decoded, ["campaign", "status"], "suspended"),
          Map.put(decoded, "places", [%{place | "visibility" => "hidden"} | remaining_places]),
          Map.put(decoded, "characters", [
            %{character | "speaker_id" => "bad speaker id"} | remaining_characters
          ])
        ] do
      assert {:error, :invalid_backup} = CampaignBackup.import(Jason.encode!(invalid))
      assert Repo.aggregate(Storyteller.Campaigns.Campaign, :count, :id) == initial_count
    end

    assert event["turn_ref"] != "turn-999"
  end

  test "rejects an oversized backup before attempting to decode it" do
    oversized = :binary.copy("x", 52_428_801)
    assert {:error, :invalid_backup} = CampaignBackup.import(oversized)
  end

  test "restores a campaign with more than 500 sessions" do
    campaign = campaign_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    sessions =
      for index <- 1..500 do
        %{
          campaign_id: campaign.id,
          title: "Archived session #{index}",
          status: :completed,
          ended_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    assert {500, nil} = Repo.insert_all(Storyteller.Campaigns.Session, sessions)
    assert {:ok, json} = CampaignBackup.export(campaign.id)
    assert length(Jason.decode!(json)["sessions"]) == 501

    assert {:ok, restored} = CampaignBackup.import(json)
    assert {:ok, restored_json} = CampaignBackup.export(restored.id)
    assert length(Jason.decode!(restored_json)["sessions"]) == 501
  end

  test "round-trips turn intent and GM-only voice guidance while accepting older version-one rows" do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "npc:keeper",
            name: "Keeper",
            voice_guidance: %{cadence: "Measured pauses", vocabulary: "Careful and formal"}
          }
        ]
      })

    [session] = campaign.sessions

    assert {:ok, turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "backup-question-intent",
               "What does the keeper know about the old road?",
               intent: :question,
               provider: fake_provider("The keeper knows the northern pass is clear.")
             )

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    document = Jason.decode!(backup_json)
    exported_turn = Enum.find(document["turns"], &(&1["idempotency_key"] == turn.idempotency_key))
    exported_character = Enum.find(document["characters"], &(&1["speaker_id"] == "npc:keeper"))

    assert exported_turn["intent"] == "question"

    assert exported_character["voice_guidance"] == %{
             "cadence" => "Measured pauses",
             "vocabulary" => "Careful and formal"
           }

    assert {:ok, imported} = CampaignBackup.import(backup_json)
    imported_turn = Play.get_turn(imported.id, turn.idempotency_key)

    imported_character =
      Repo.get_by!(Character, campaign_id: imported.id, speaker_id: "npc:keeper")

    assert imported_turn.intent == :question

    assert imported_character.voice_guidance == %{
             "cadence" => "Measured pauses",
             "vocabulary" => "Careful and formal"
           }

    legacy_characters =
      document
      |> pre_active_duties(1)
      |> Map.fetch!("characters")
      |> Enum.map(&Map.delete(&1, "voice_guidance"))

    legacy_document = %{
      %{
        pre_active_duties(document, 1)
        | "schema_version" => 1,
          "campaign" => Map.delete(document["campaign"], "player_character_name"),
          "state" => drop_elapsed_clock(document["state"])
      }
      | "turns" => Enum.map(document["turns"], &Map.drop(&1, ["intent", "failure_stage"])),
        "characters" => legacy_characters,
        "authoring_corrections" => nil
    }

    legacy_document = Map.delete(legacy_document, "authoring_corrections")
    legacy_document = Map.delete(legacy_document, "place_connections")
    legacy_document = Map.delete(legacy_document, "canon_corrections")

    assert {:ok, legacy_import} = CampaignBackup.import(Jason.encode!(legacy_document))
    assert Play.get_turn(legacy_import.id, turn.idempotency_key).intent == :action

    assert Repo.aggregate(
             from(connection in PlaceConnection,
               where: connection.campaign_id == ^legacy_import.id
             ),
             :count
           ) == 0

    assert Repo.get_by!(Character, campaign_id: legacy_import.id, speaker_id: "npc:keeper").voice_guidance ==
             %{}

    legacy_player = Repo.get_by!(Character, campaign_id: legacy_import.id, speaker_id: "player")
    legacy_campaign = Campaigns.get_campaign!(legacy_import.id)
    assert legacy_campaign.player_character_name == legacy_player.name
    assert legacy_campaign.player_character == campaign.player_character
    assert legacy_player.visible_facts["description"] == campaign.player_character

    assert Repo.aggregate(
             from(correction in AuthoringCorrection,
               where: correction.campaign_id == ^legacy_import.id
             ),
             :count,
             :id
           ) == 0
  end

  test "round-trips failure stages in version six and imports versions two through five" do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    raw_model_output = "RAW-MODEL-OUTPUT-SENTINEL"

    assert {:ok, failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "safe-failure-diagnostic",
               "Look at the gate.",
               provider: fn _request -> {:ok, raw_model_output} end,
               model: "test-model"
             )

    assert failed.status == :failed
    assert failed.failure_code == "invalid_response"
    assert failed.failure_stage == :response_decoding

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    refute backup_json =~ raw_model_output

    document = Jason.decode!(backup_json)
    assert document["schema_version"] == 11
    [exported_turn] = document["turns"]
    assert exported_turn["failure_code"] == "invalid_response"
    assert exported_turn["failure_stage"] == "response_decoding"

    assert {:ok, imported} = CampaignBackup.import(backup_json)
    imported_turn = Play.get_turn(imported.id, failed.idempotency_key)
    assert imported_turn.failure_stage == :response_decoding

    # Version five had the elapsed clock but no state-correction audit records.
    v5_document =
      document
      |> pre_active_duties(5)
      |> Map.drop(["canon_corrections"])

    assert {:ok, imported_v5} = CampaignBackup.import(Jason.encode!(v5_document))
    imported_v5_state = Repo.get_by!(State, campaign_id: imported_v5.id)
    assert imported_v5_state.elapsed_world_minutes == document["state"]["elapsed_world_minutes"]

    # Version four had connections and failure stages, but no elapsed clock or canon corrections.
    v4_document =
      document
      |> pre_active_duties(4)
      |> Map.put("state", drop_elapsed_clock(document["state"]))
      |> Map.drop(["canon_corrections"])

    assert {:ok, imported_v4} = CampaignBackup.import(Jason.encode!(v4_document))
    imported_v4_state = Repo.get_by!(State, campaign_id: imported_v4.id)
    assert imported_v4_state.elapsed_world_minutes == 0

    assert imported_v4_state.elapsed_world_anchor == %{}

    # Version three had failure stages but not the place graph or elapsed clock.
    v3_document =
      document
      |> pre_active_duties(3)
      |> Map.put("state", drop_elapsed_clock(document["state"]))
      |> Map.drop(["place_connections", "canon_corrections"])

    assert {:ok, imported_v3} = CampaignBackup.import(Jason.encode!(v3_document))

    assert Play.get_turn(imported_v3.id, failed.idempotency_key).failure_stage ==
             :response_decoding

    assert Repo.aggregate(
             from(connection in PlaceConnection, where: connection.campaign_id == ^imported_v3.id),
             :count
           ) == 0

    v2_document =
      document
      |> pre_active_duties(2)
      |> Map.put("state", drop_elapsed_clock(document["state"]))
      |> Map.put("turns", Enum.map(document["turns"], &Map.delete(&1, "failure_stage")))
      |> Map.drop(["place_connections", "canon_corrections"])

    assert {:ok, imported_v2} = CampaignBackup.import(Jason.encode!(v2_document))
    assert Play.get_turn(imported_v2.id, failed.idempotency_key).failure_stage == nil

    assert Repo.aggregate(
             from(connection in PlaceConnection, where: connection.campaign_id == ^imported_v2.id),
             :count
           ) == 0
  end

  defp pre_active_duties(document, version) do
    character_keys =
      if version >= 9,
        do: ["duty_release_at_world_minute"],
        else: ["duty_name", "duty_place_id", "duty_release_at_world_minute"]

    document
    |> Map.put("schema_version", version)
    |> Map.update!("characters", fn characters ->
      Enum.map(characters, &Map.drop(&1, character_keys))
    end)
    |> Map.update("authoring_corrections", [], fn corrections ->
      Enum.map(corrections, fn correction ->
        Enum.reduce(["before_state", "after_state"], correction, fn state_key, row ->
          Map.update!(row, state_key, fn state ->
            Map.update(state, "gm_characters", %{}, fn characters ->
              Enum.reduce(characters, %{}, fn {speaker_id, sections}, acc ->
                sections =
                  if version >= 9,
                    do:
                      Map.update(sections, "active_duty", nil, fn duty ->
                        Map.drop(duty, ["release_at_world_minute"])
                      end),
                    else: Map.delete(sections, "active_duty")

                if map_size(sections) == 0,
                  do: acc,
                  else: Map.put(acc, speaker_id, sections)
              end)
            end)
          end)
        end)
      end)
    end)
  end

  defp put_character(document, speaker_id, key, value) do
    Map.update!(document, "characters", fn characters ->
      Enum.map(characters, fn
        %{"speaker_id" => ^speaker_id} = character -> Map.put(character, key, value)
        character -> character
      end)
    end)
  end

  defp drop_elapsed_clock(state),
    do:
      Map.drop(state, [
        "elapsed_world_minutes",
        "elapsed_world_anchor_minutes",
        "elapsed_world_anchor"
      ])

  test "imports atomically and an enclosing rollback removes the new campaign and all children" do
    campaign = campaign_fixture()
    assert {:ok, json} = CampaignBackup.export(campaign.id)

    assert {:error, :backup_test_rollback} =
             Repo.transaction(fn ->
               assert {:ok, imported} = CampaignBackup.import(json)
               assert Repo.get(Storyteller.Campaigns.Campaign, imported.id)
               Repo.rollback(:backup_test_rollback)
             end)

    assert Repo.aggregate(Storyteller.Campaigns.Campaign, :count, :id) == 1
    assert Repo.aggregate(from(state in State), :count, :id) == 1
  end

  test "round-trips player-authored public memory without inventing event provenance" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "memory",
               "expected_revision" => state.revision,
               "reason" => "The player preserves an important promise.",
               "values" => %{
                 "action" => "add",
                 "kind" => "commitment",
                 "title" => "Lyra's promise",
                 "details" => "Lyra will bring the star chart before dawn."
               }
             })

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    backup = Jason.decode!(backup_json)
    assert hd(backup["canon_corrections"])["kind"] == "memory"
    memory = Enum.find(backup["continuity_entries"], &(&1["title"] == "Lyra's promise"))
    assert memory["visibility"] == "public"
    assert memory["introduced_event_sequence"] == nil
    assert memory["source_event_sequence"] == nil

    assert {:ok, imported} = CampaignBackup.import(backup_json)

    imported_memory =
      Repo.get_by!(ContinuityEntry, campaign_id: imported.id, entry_id: memory["entry_id"])

    assert imported_memory.visibility == :public
    assert is_nil(imported_memory.introduced_by_event_id)
    assert is_nil(imported_memory.source_event_id)
    assert imported_memory.details == "Lyra will bring the star chart before dawn."

    imported_correction = Repo.get_by!(CanonCorrection, campaign_id: imported.id)
    assert imported_correction.kind == "memory"
    assert imported_correction.before_state == %{"entry" => nil}
    assert imported_correction.after_state["entry"]["entry_id"] == memory["entry_id"]
  end

  test "keeps v6 backups importable while requiring v7 for player-authored memory" do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    assert {:ok, ordinary_backup} = CampaignBackup.export(campaign.id)
    v6_backup = ordinary_backup |> Jason.decode!() |> pre_active_duties(6)
    assert {:ok, _imported_v6} = CampaignBackup.import(Jason.encode!(v6_backup))

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "memory",
               "expected_revision" => state.revision,
               "reason" => "Keep the promise in the campaign record.",
               "values" => %{
                 "action" => "add",
                 "kind" => "commitment",
                 "title" => "A remembered promise",
                 "details" => "The keeper will return before dawn."
               }
             })

    assert {:ok, memory_backup} = CampaignBackup.export(campaign.id)
    invalid_v6 = memory_backup |> Jason.decode!() |> pre_active_duties(6)
    assert {:error, :invalid_backup} = CampaignBackup.import(Jason.encode!(invalid_v6))
  end

  test "imports v10 backups that predate communication paths and remote messages" do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    assert {:ok, _turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "legacy-communication-backup",
               "I wait here.",
               provider: fake_provider("The room remains quiet."),
               model: "backup-test"
             )

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    v10_backup = backup_json |> Jason.decode!() |> Map.put("schema_version", 10)

    refute Map.has_key?(v10_backup["state"]["public_state"], "communication_paths")
    refute Enum.any?(v10_backup["events"], &(&1["event_type"] == "remote_message"))
    assert {:ok, _imported} = CampaignBackup.import(Jason.encode!(v10_backup))

    forged_path = %{
      "path_id" => "legacy-path",
      "sender_id" => "unknown-npc",
      "recipient_id" => "player",
      "channel" => "Letter",
      "endpoint" => "Harbor office",
      "status" => "active"
    }

    legacy_with_path =
      put_in(v10_backup, ["state", "public_state", "communication_paths"], [forged_path])

    assert {:error, :invalid_backup} = CampaignBackup.import(Jason.encode!(legacy_with_path))

    legacy_with_remote_event =
      Map.update!(v10_backup, "events", fn [event | remaining] ->
        [%{event | "event_type" => "remote_message"} | remaining]
      end)

    assert {:error, :invalid_backup} =
             CampaignBackup.import(Jason.encode!(legacy_with_remote_event))
  end

  defp fake_provider(narration) do
    proposal = %{
      "narration" => narration,
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{"hidden_truth" => "The keeper protects the second ledger."},
      "panel_changes" => [],
      "memory_update" => %{
        "public_summary" => "The cellar accounts are being reviewed.",
        "gm_private_summary" => "The second ledger remains under the north stair."
      },
      "character_updates" => [],
      "location_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "continuity_changes" => [],
      "roll_request" => nil
    }

    fn _request -> {:ok, Jason.encode!(proposal)} end
  end
end
