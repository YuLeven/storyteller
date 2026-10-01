defmodule Storyteller.CampaignBackupWorldCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Play.{CanonCorrection, CanonCorrections, State}
  alias Storyteller.Repo

  test "version ten round-trips world correction audit and version seven remains importable" do
    campaign =
      campaign_fixture(%{
        starting_date: "14 October 1567",
        world_time: "First watch",
        weather: "Low fog"
      })

    session = hd(campaign.sessions)

    assert {:ok, before_correction} = CampaignBackup.export(campaign.id)

    v7_backup =
      before_correction
      |> Jason.decode!()
      |> Map.put("schema_version", 7)
      |> Map.update!("characters", fn characters ->
        Enum.map(
          characters,
          &Map.drop(&1, ["duty_name", "duty_place_id", "duty_release_at_world_minute"])
        )
      end)

    assert {:ok, imported_v7} = CampaignBackup.import(Jason.encode!(v7_backup))
    assert Repo.get_by!(State, campaign_id: imported_v7.id).public_state["weather"] == "Low fog"

    {:ok, options} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, _receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "world",
               target_id: "weather",
               expected_revision: options.revision,
               values: %{"value" => "Clear skies"},
               reason: "The weather label was copied incorrectly."
             })

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    backup = Jason.decode!(backup_json)
    assert backup["schema_version"] == 10

    assert [%{"kind" => "world", "target_id" => "weather"} = exported_correction] =
             backup["canon_corrections"]

    assert exported_correction["before_state"] == %{
             "key" => "weather",
             "label" => "Weather",
             "value" => "Low fog"
           }

    assert exported_correction["after_state"] == %{
             "key" => "weather",
             "label" => "Weather",
             "value" => "Clear skies"
           }

    assert {:ok, imported} = CampaignBackup.import(backup_json)
    assert Repo.get_by!(State, campaign_id: imported.id).public_state["weather"] == "Clear skies"

    imported_correction =
      Repo.get_by!(CanonCorrection,
        campaign_id: imported.id,
        kind: "world",
        target_id: "weather"
      )

    assert imported_correction.reason == "The weather label was copied incorrectly."
    assert imported_correction.before_state == exported_correction["before_state"]
    assert imported_correction.after_state == exported_correction["after_state"]

    legacy_world_correction = Map.put(v7_backup, "canon_corrections", [exported_correction])

    assert {:error, :invalid_backup} =
             CampaignBackup.import(Jason.encode!(legacy_world_correction))
  end
end
