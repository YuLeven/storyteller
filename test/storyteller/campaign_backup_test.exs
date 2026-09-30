defmodule Storyteller.CampaignBackupTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Campaigns
  alias Storyteller.Auth.TokenStore
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Play.{Character, ContinuityEntry, Event, Objective, Place, Roll, State, Turn}
  alias Storyteller.Repo

  test "round-trips complete multi-session canon and remaps internal provenance IDs" do
    campaign =
      campaign_fixture(%{
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
    assert document["schema_version"] == 1
    assert document["campaign"]["title"] == campaign.title
    assert document["state"]["gm_private_state"]["history_clue"]

    assert Enum.any?(
             document["characters"],
             &(&1["gm_private_facts"]["motive"] == "Protect the star chart.")
           )

    assert Enum.any?(document["places"], &(&1["visibility"] == "gm_private"))
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

    assert Enum.map(imported_campaign.sessions, &{&1.title, &1.status}) |> MapSet.new() ==
             MapSet.new([{"Session 1", :completed}, {"The sealed cellar", :active}])

    imported_state = Repo.get_by!(State, campaign_id: imported.id)
    assert imported_state.public_state == original_state.public_state
    assert imported_state.gm_private_state == original_state.gm_private_state
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
          Map.put(decoded, "schema_version", 2),
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
