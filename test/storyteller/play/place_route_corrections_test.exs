defmodule Storyteller.Play.PlaceRouteCorrectionsTest do
  use Storyteller.DataCase, async: false

  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.CampaignBackup
  alias Storyteller.Play.{CanonCorrection, CanonCorrections, Event, Place, PlaceConnection, State}
  alias Storyteller.Repo

  test "players can correct public place and route details without adding fictional events" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)

    observatory = insert_place!(campaign.id, "observatory", "The Observatory", :public)
    road = insert_place!(campaign.id, "north-road", "The North Road", :public)
    hidden = insert_place!(campaign.id, "sealed-archive", "Sealed Archive", :gm_private)

    public_route = insert_route!(campaign.id, observatory.place_id, road.place_id, :public)

    _private_route =
      insert_route!(campaign.id, observatory.place_id, hidden.place_id, :gm_private)

    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.map(options.places, & &1.name) == ["The North Road", "The Observatory"]
    refute Enum.any?(options.places, &(&1.id == hidden.place_id))

    assert [route_option] = options.travel_connections
    assert route_option.place_a_id == public_route.place_a_id
    assert route_option.place_b_id == public_route.place_b_id
    refute inspect(options) =~ "Sealed Archive"

    assert {:error, :not_found} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "place",
               target_id: hidden.place_id,
               expected_revision: options.revision,
               reason: "A hidden place must not be editable here.",
               values: %{"name" => "Sealed Archive", "description" => "", "facts" => "{}"}
             })

    assert Repo.get_by!(State, campaign_id: campaign.id) == state_before

    assert {:ok, place_receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "place",
               target_id: observatory.place_id,
               expected_revision: options.revision,
               reason: "The observatory notes have the corrected entrance description.",
               values: %{
                 "name" => "The Glass Observatory",
                 "description" => "A basalt tower above the northern inlet.",
                 "facts" => Jason.encode!(%{"entrance" => "east stair", "roof" => "sealed"})
               }
             })

    assert place_receipt.revision == options.revision + 1

    updated_place = Repo.get_by!(Place, campaign_id: campaign.id, place_id: observatory.place_id)
    assert updated_place.name == "The Glass Observatory"
    assert updated_place.description == "A basalt tower above the northern inlet."
    assert updated_place.facts == %{"entrance" => "east stair", "roof" => "sealed"}

    assert {:ok, refreshed} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, route_receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "travel_connection",
               target_id: route_option.id,
               expected_revision: refreshed.revision,
               reason: "The route log confirms the measured journey time.",
               values: %{
                 "travel_minutes" => "55",
                 "scene_relevance" => "A steep path; messengers need most of an hour."
               }
             })

    assert route_receipt.revision == refreshed.revision + 1

    updated_route =
      Repo.get_by!(PlaceConnection,
        campaign_id: campaign.id,
        place_a_id: public_route.place_a_id,
        place_b_id: public_route.place_b_id
      )

    assert updated_route.travel_minutes == 55
    assert updated_route.scene_relevance == "A steep path; messengers need most of an hour."

    state_after = Repo.get_by!(State, campaign_id: campaign.id)
    assert state_after.revision == state_before.revision + 2
    assert state_after.event_sequence == state_before.event_sequence
    assert state_after.elapsed_world_minutes == state_before.elapsed_world_minutes
    assert state_after.public_state == state_before.public_state

    assert Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count) ==
             0

    assert Enum.map(CanonCorrections.list_receipts(campaign.id), & &1.kind) == [
             "travel_connection",
             "place"
           ]

    Repo.update!(Place.changeset(road, %{visibility: :gm_private}))
    assert Enum.map(CanonCorrections.list_receipts(campaign.id), & &1.kind) == ["place"]

    Repo.update!(Place.changeset(updated_place, %{visibility: :gm_private}))
    assert CanonCorrections.list_receipts(campaign.id) == []
  end

  test "public place and route corrections survive a campaign backup round trip" do
    campaign = campaign_fixture()
    session = hd(campaign.sessions)
    place_a = insert_place!(campaign.id, "island-dock", "Island Dock", :public)
    place_b = insert_place!(campaign.id, "observatory", "Observatory", :public)
    route = insert_route!(campaign.id, place_a.place_id, place_b.place_id, :public)
    {:ok, options} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, place_result} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "place",
               target_id: place_a.place_id,
               expected_revision: options.revision,
               reason: "Use the name from the island survey.",
               values: %{
                 "name" => "West Island Dock",
                 "description" => "A weathered pier.",
                 "facts" => "{}"
               }
             })

    {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    route_id = Enum.find(options.travel_connections, &(&1.place_a_id == route.place_a_id)).id

    assert {:ok, _route_result} =
             CanonCorrections.correct(campaign.id, session.id, %{
               kind: "travel_connection",
               target_id: route_id,
               expected_revision: place_result.revision,
               reason: "The route survey measured the walk.",
               values: %{"travel_minutes" => "18", "scene_relevance" => "Along the old seawall."}
             })

    assert {:ok, json} = CampaignBackup.export(campaign.id)
    assert Jason.decode!(json)["schema_version"] == 13

    assert {:ok, imported} = CampaignBackup.import(json)

    imported_corrections =
      Repo.all(
        from correction in CanonCorrection,
          where: correction.campaign_id == ^imported.id,
          order_by: [asc: correction.sequence]
      )

    assert Enum.map(imported_corrections, & &1.kind) == ["place", "travel_connection"]

    assert Repo.get_by!(Place, campaign_id: imported.id, place_id: place_a.place_id).name ==
             "West Island Dock"

    assert Repo.get_by!(PlaceConnection,
             campaign_id: imported.id,
             place_a_id: route.place_a_id,
             place_b_id: route.place_b_id
           ).travel_minutes == 18
  end

  defp insert_place!(campaign_id, place_id, name, visibility) do
    Repo.insert!(
      Place.changeset(%Place{}, %{
        campaign_id: campaign_id,
        place_id: place_id,
        name: name,
        visibility: visibility,
        facts: %{}
      })
    )
  end

  defp insert_route!(campaign_id, place_a_id, place_b_id, visibility) do
    [place_a_id, place_b_id] = Enum.sort([place_a_id, place_b_id])

    Repo.insert!(
      PlaceConnection.changeset(%PlaceConnection{}, %{
        campaign_id: campaign_id,
        place_a_id: place_a_id,
        place_b_id: place_b_id,
        travel_minutes: 40,
        scene_relevance: "A route between known locations.",
        visibility: visibility
      })
    )
  end
end
