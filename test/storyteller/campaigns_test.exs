defmodule Storyteller.CampaignsTest do
  use Storyteller.DataCase, async: true

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.{Campaign, Session}

  test "creating a campaign atomically creates its first resumable session" do
    attrs = valid_campaign_attrs()

    assert {:ok, campaign} = Campaigns.create_campaign(attrs)
    assert campaign.title == attrs.title

    assert [%Session{title: "Session 1", status: :active, campaign_id: campaign_id}] =
             campaign.sessions

    assert campaign_id == campaign.id

    assert [%Campaign{id: id, sessions: [%Session{title: "Session 1"}]}] =
             Campaigns.list_campaigns()

    assert id == campaign.id
  end

  test "rejects incomplete campaign setup without persisting a partial campaign" do
    assert {:error, changeset} = Campaigns.create_campaign(%{title: "Only a title"})
    assert %{premise: ["can't be blank"], setting: ["can't be blank"]} = errors_on(changeset)
    assert Campaigns.list_campaigns() == []
  end

  test "campaigns keep their setup and sessions isolated" do
    first =
      campaign_fixture(%{
        title: "The Northern Signal",
        premise: "A light blinks from an empty lighthouse."
      })

    second =
      campaign_fixture(%{
        title: "The Copper Archive",
        premise: "A cataloguer finds a missing atlas."
      })

    first_session = hd(first.sessions)
    second_session = hd(second.sessions)

    assert first.id != second.id
    assert Campaigns.get_session(first.id, first_session.id).campaign_id == first.id
    assert Campaigns.get_session(first.id, second_session.id) == nil

    first_record = Enum.find(Campaigns.list_campaigns(), &(&1.id == first.id))
    second_record = Enum.find(Campaigns.list_campaigns(), &(&1.id == second.id))
    assert first_record.premise == "A light blinks from an empty lighthouse."
    assert first_record.sessions == [first_session]
    assert second_record.premise == "A cataloguer finds a missing atlas."
    assert second_record.sessions == [second_session]
  end

  test "starting a session completes the previous one and keeps exactly one active" do
    campaign = campaign_fixture()
    [first] = campaign.sessions

    assert {:ok, second} = Campaigns.start_session(campaign, %{"title" => "The Second Watch"})
    assert second.title == "The Second Watch"
    assert second.status == :active

    refreshed = Campaigns.get_campaign!(campaign.id)
    assert Enum.find(refreshed.sessions, &(&1.id == first.id)).status == :completed
    assert Enum.find(refreshed.sessions, &(&1.id == first.id)).ended_at
    assert Enum.find(refreshed.sessions, &(&1.id == second.id)).status == :active
    assert Enum.count(refreshed.sessions, &(&1.status == :active)) == 1
  end

  test "a rejected next session rolls back completion of the current session" do
    campaign = campaign_fixture()
    [first] = campaign.sessions

    assert {:error, changeset} =
             Campaigns.start_session(campaign, %{title: String.duplicate("x", 101)})

    assert errors_on(changeset).title == ["should be at most 100 character(s)"]

    assert [%Session{id: first_id, status: :active, ended_at: nil}] =
             Campaigns.get_campaign!(campaign.id).sessions

    assert first_id == first.id
  end

  test "archiving completes its active session and prevents new sessions until restored" do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    assert {:ok, archived} = Campaigns.archive_campaign(campaign)
    assert archived.status == :archived

    assert [%Session{id: id, status: :completed, ended_at: ended_at}] =
             Campaigns.get_campaign!(campaign.id).sessions

    assert id == session.id
    assert ended_at
    assert {:error, :campaign_archived} = Campaigns.start_session(archived)

    assert {:ok, restored} = Campaigns.restore_campaign(archived)
    assert restored.status == :active
    assert {:ok, new_session} = Campaigns.start_session(restored)
    assert new_session.title == "Session 2"
  end

  test "narration language must be one of the supported campaign choices" do
    attrs = Map.put(valid_campaign_attrs(), :narration_language, "Klingon")

    assert {:error, changeset} = Campaigns.create_campaign(attrs)
    assert errors_on(changeset).narration_language == ["is invalid"]
    assert Campaigns.list_campaigns() == []
  end
end
