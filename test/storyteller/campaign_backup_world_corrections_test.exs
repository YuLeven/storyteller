defmodule Storyteller.CampaignBackupWorldCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Play.{CanonCorrection, CanonCorrections, Objective, State}
  alias Storyteller.Repo

  test "version fourteen round-trips objective correction audit and version seven remains importable" do
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
      |> Map.update!("campaign", &Map.delete(&1, "integrations"))
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

    objective =
      Repo.insert!(
        Objective.changeset(%Objective{}, %{
          campaign_id: campaign.id,
          objective_id: "seal-west-roof",
          title: "Seal the west roof",
          details: "Patch the storm damage before winter.",
          status: :open,
          visibility: :public
        })
      )

    {:ok, objective_options} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, _objective_receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "objective",
               target_id: objective.objective_id,
               expected_revision: objective_options.revision,
               reason: "The west roof was fixed; record the remaining work accurately.",
               values: %{
                 title: "Clear the north gutter",
                 details: "Remove leaves from the north gutter before the next rain.",
                 status: "abandoned"
               }
             })

    assert {:ok, backup_json} = CampaignBackup.export(campaign.id)
    backup = Jason.decode!(backup_json)
    assert backup["schema_version"] == 14

    assert [
             %{"kind" => "world", "target_id" => "weather"} = exported_correction,
             %{"kind" => "objective", "target_id" => "seal-west-roof"} = exported_objective
           ] =
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

    imported_objective =
      Repo.get_by!(Objective, campaign_id: imported.id, objective_id: "seal-west-roof")

    assert imported_objective.title == "Clear the north gutter"
    assert imported_objective.status == :abandoned

    imported_objective_correction =
      Repo.get_by!(CanonCorrection,
        campaign_id: imported.id,
        kind: "objective",
        target_id: "seal-west-roof"
      )

    assert imported_objective_correction.before_state == exported_objective["before_state"]
    assert imported_objective_correction.after_state == exported_objective["after_state"]

    legacy_world_correction = Map.put(v7_backup, "canon_corrections", [exported_correction])

    assert {:error, :invalid_backup} =
             CampaignBackup.import(Jason.encode!(legacy_world_correction))
  end
end
