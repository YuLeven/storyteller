defmodule Storyteller.CampaignsTest do
  use Storyteller.DataCase, async: true

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.{Campaign, Session}
  alias Storyteller.Panels
  alias Storyteller.Panels.Field
  alias Storyteller.Play

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

  test "list-based setup persists distinct world date and time, stable GM speakers, and panels" do
    attrs =
      valid_campaign_attrs()
      |> Map.merge(%{
        starting_location: "North watchtower",
        starting_date: "The 14th day of thaw",
        world_time: "After moonrise",
        weather: "Cold rain",
        gm_characters: [
          %{
            speaker_id: "captain-ren",
            name: "Captain Ren",
            visible_facts: %{"description" => "A careful harbor officer."},
            gm_private_facts: %{"agenda" => "Quietly tracing the signal."}
          }
        ],
        panel_fields: [
          %{
            key: "healing_potions",
            panel: "Supplies",
            label: "Healing potions",
            value_type: "quantity",
            unit: "bottles",
            visibility: "public",
            initial_value: "3"
          },
          %{
            key: "signal_source",
            panel: "GM notes",
            label: "Signal source",
            value_type: "text",
            visibility: "gm_private",
            initial_value: "An abandoned relay."
          }
        ]
      })

    assert {:ok, campaign} = Campaigns.create_campaign(attrs)
    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == "North watchtower"
    assert projection.world["date"] == "The 14th day of thaw"
    assert projection.world["time"] == "After moonrise"
    assert projection.world["weather"] == "Cold rain"

    gm_character = Enum.find(projection.characters, &(&1.speaker_id == "captain-ren"))
    assert gm_character.name == "Captain Ren"
    assert gm_character.visible_facts["description"] == "A careful harbor officer."
    refute Map.has_key?(gm_character, :gm_private_facts)

    assert [%{key: "healing_potions", value: %{"value" => 3}} | _] =
             Panels.list_fields(campaign.id)

    assert {:ok, %{panels: [panel]}} = Panels.public_projection(campaign.id)
    assert panel.name == "Supplies"
    assert [%{key: "healing_potions", value: 3}] = panel.fields
    refute inspect(panel) =~ "abandoned relay"
  end

  test "campaign setup persists normalized player-owned public starting inventory" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:inventory, [
        %{
          name: "Cedarwood bottle",
          quantity: "3",
          unit: "bottles",
          category: "Wine",
          description: "A small batch from the east terrace."
        }
      ])

    assert {:ok, campaign} = Campaigns.create_campaign(attrs)
    assert {:ok, projection} = Play.public_projection(campaign.id)

    assert [
             %{
               "name" => "Cedarwood bottle",
               "quantity" => 3,
               "unit" => "bottles",
               "category" => "Wine",
               "description" => "A small batch from the east terrace.",
               "owner_id" => "player",
               "visibility" => "public"
             } = item
           ] = projection.inventory

    assert String.starts_with?(item["id"], "initial-")
    assert projection.world["location"] == nil
  end

  test "campaign setup rejects invalid and zero starting item quantities" do
    for quantity <- ["not-a-number", "1.5", "0", 0] do
      attrs =
        valid_campaign_attrs()
        |> Map.put(:inventory, [%{name: "Healing potion", quantity: quantity}])

      assert {:error, {:setup, "Starting item 1 needs a positive whole-number quantity."}} =
               Campaigns.create_campaign(attrs)
    end

    assert Campaigns.list_campaigns() == []
    assert Repo.all(Storyteller.Play.State) == []
  end

  test "formula-like panel values are rejected before any setup is persisted" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:panel_fields, [
        %{
          key: "unsafe_text",
          panel: "Notes",
          label: "Text",
          value_type: "text",
          visibility: "public",
          initial_value: "=execute()"
        }
      ])

    assert {:error, {:setup, _message}} = Campaigns.create_campaign(attrs)
    assert Campaigns.list_campaigns() == []
    assert Repo.all(Storyteller.Play.State) == []
    assert Repo.all(Storyteller.Play.Character) == []
    assert Repo.all(Field) == []
  end

  test "reserved or duplicate speaker IDs are rejected before campaign creation" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:gm_characters, [
        %{speaker_id: "captain", name: "Captain Ren"},
        %{speaker_id: "captain", name: "Captain Vale"}
      ])

    assert {:error, {:setup, "Each GM character needs a unique speaker ID."}} =
             Campaigns.create_campaign(attrs)

    assert Campaigns.list_campaigns() == []
    assert Repo.all(Storyteller.Play.State) == []
    assert Repo.all(Storyteller.Play.Character) == []
    assert Repo.all(Field) == []
  end
end
