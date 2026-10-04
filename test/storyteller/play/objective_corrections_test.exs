defmodule Storyteller.Play.ObjectiveCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.Play.{CanonCorrection, CanonCorrections, Event, Objective, State}
  alias Storyteller.Repo

  test "a player can correct a public objective with an audited out-of-story change" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)

    objective =
      Repo.insert!(
        Objective.changeset(%Objective{}, %{
          campaign_id: campaign.id,
          objective_id: "repair-observatory-roof",
          title: "Repair the observatory roof",
          details: "Seal the western seam before the next storm.",
          status: :open,
          visibility: :public
        })
      )

    hidden_objective =
      Repo.insert!(
        Objective.changeset(%Objective{}, %{
          campaign_id: campaign.id,
          objective_id: "hidden-keeper-plan",
          title: "Keeper's hidden plan",
          details: "A private objective that must not be player-editable.",
          status: :open,
          visibility: :gm_private
        })
      )

    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    events_before =
      Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count)

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert [%{objective_id: "repair-observatory-roof"}] = options.objectives
    refute inspect(options) =~ hidden_objective.title

    attrs = %{
      kind: "objective",
      target_id: objective.objective_id,
      expected_revision: options.revision,
      reason: "The roof was repaired last month; only the east gutter still needs work.",
      values: %{
        title: "Clear the observatory east gutter",
        details: "Remove leaves from the east gutter before the next rain.",
        status: "abandoned"
      }
    }

    assert {:error, :not_found} =
             CanonCorrections.correct(
               campaign.id,
               session.id,
               Map.put(attrs, :target_id, hidden_objective.objective_id)
             )

    assert {:ok, receipt} = CanonCorrections.correct(campaign.id, session.id, attrs)

    updated = Repo.get!(Objective, objective.id)
    assert updated.title == "Clear the observatory east gutter"
    assert updated.details == "Remove leaves from the east gutter before the next rain."
    assert updated.status == :abandoned
    assert updated.visibility == :public

    state_after = Repo.get_by!(State, campaign_id: campaign.id)
    assert state_after.revision == state_before.revision + 1
    assert state_after.elapsed_world_minutes == state_before.elapsed_world_minutes

    assert Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count) ==
             events_before

    assert {:ok, updated_options} = CanonCorrections.options(campaign.id, session.id)

    assert [%{title: "Clear the observatory east gutter", status: :abandoned}] =
             updated_options.objectives

    correction = Repo.get_by!(CanonCorrection, campaign_id: campaign.id, kind: "objective")
    assert correction.sequence == receipt.sequence
    assert correction.before_state["objective"]["status"] == "open"
    assert correction.after_state["objective"]["status"] == "abandoned"

    assert [listed_receipt] = CanonCorrections.list_receipts(campaign.id)
    assert listed_receipt.kind == "objective"
    assert listed_receipt.target_label == "Clear the observatory east gutter"
    assert listed_receipt.reason == attrs.reason

    Repo.update!(Objective.changeset(updated, %{visibility: :gm_private}))
    assert CanonCorrections.list_receipts(campaign.id) == []
  end
end
