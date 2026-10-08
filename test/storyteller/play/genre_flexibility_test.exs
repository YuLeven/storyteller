defmodule Storyteller.Play.GenreFlexibilityTest do
  use Storyteller.DataCase

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Play

  test "vineyard balances and dungeon inventory persist independently across sessions" do
    vineyard =
      campaign_fixture(%{
        title: "The Quiet Vineyard",
        setting: "A family-run vineyard outside Siena",
        starting_date: "14 October 1567",
        panel_fields: [
          %{
            key: "cash_on_hand",
            panel: "Finca",
            label: "Cash on hand",
            value_type: "money",
            unit: "florins",
            visibility: "public",
            initial_value: "42.50"
          },
          %{
            key: "wine_in_cellar",
            panel: "Bodega",
            label: "Wine in the cellar",
            value_type: "quantity",
            unit: "barrels",
            visibility: "public",
            initial_value: "18"
          }
        ]
      })

    dungeon =
      campaign_fixture(%{
        title: "The Sunken Archive",
        setting: "A flooded stone archive beneath the coast",
        starting_date: "The third evening of the thaw",
        inventory: [
          %{
            name: "Healing draught",
            quantity: 2,
            unit: "vials",
            owner_id: "player",
            category: "potion"
          },
          %{
            name: "Bronze key",
            quantity: 1,
            unit: "key",
            owner_id: "player",
            category: "tool"
          }
        ]
      })

    vineyard_session = hd(vineyard.sessions)
    dungeon_session = hd(dungeon.sessions)

    first_vineyard_context =
      submit_turn_and_capture(
        vineyard,
        vineyard_session,
        "vineyard-first",
        "Check the cellar ledger."
      )

    first_dungeon_context =
      submit_turn_and_capture(dungeon, dungeon_session, "dungeon-first", "Check my pack.")

    assert first_vineyard_context["campaign"]["title"] == "The Quiet Vineyard"
    assert first_vineyard_context["world"]["public"]["date"] == "14 October 1567"

    assert Map.new(first_vineyard_context["panels"], &{&1["key"], &1}) == %{
             "cash_on_hand" => %{
               "key" => "cash_on_hand",
               "panel" => "Finca",
               "label" => "Cash on hand",
               "type" => "money",
               "unit" => "florins",
               "visibility" => "public",
               "value" => "42.5"
             },
             "wine_in_cellar" => %{
               "key" => "wine_in_cellar",
               "panel" => "Bodega",
               "label" => "Wine in the cellar",
               "type" => "quantity",
               "unit" => "barrels",
               "visibility" => "public",
               "value" => 18
             }
           }

    assert first_vineyard_context["inventory"]["player_visible"] == []
    assert first_dungeon_context["panels"] == []

    assert Enum.map(first_dungeon_context["inventory"]["player_visible"], & &1["name"]) == [
             "Healing draught",
             "Bronze key"
           ]

    {:ok, next_vineyard_session} =
      Campaigns.start_session(Campaigns.get_campaign!(vineyard.id), %{title: "A later harvest"})

    {:ok, next_dungeon_session} =
      Campaigns.start_session(Campaigns.get_campaign!(dungeon.id), %{title: "Deeper below"})

    later_vineyard_context =
      submit_turn_and_capture(
        vineyard,
        next_vineyard_session,
        "vineyard-later",
        "Review the cellar ledger again."
      )

    later_dungeon_context =
      submit_turn_and_capture(
        dungeon,
        next_dungeon_session,
        "dungeon-later",
        "Check the contents of my pack again."
      )

    assert later_vineyard_context["campaign"]["title"] == "The Quiet Vineyard"
    assert later_vineyard_context["world"]["public"]["date"] == "14 October 1567"

    assert Enum.map(later_vineyard_context["panels"], & &1["key"]) == [
             "cash_on_hand",
             "wine_in_cellar"
           ]

    assert Enum.find(later_vineyard_context["panels"], &(&1["key"] == "cash_on_hand"))["value"] ==
             "42.5"

    assert Enum.find(later_vineyard_context["panels"], &(&1["key"] == "wine_in_cellar"))["value"] ==
             18

    assert later_dungeon_context["campaign"]["title"] == "The Sunken Archive"

    assert Enum.map(later_dungeon_context["inventory"]["player_visible"], & &1["name"]) == [
             "Healing draught",
             "Bronze key"
           ]

    refute Jason.encode!(later_vineyard_context) =~ "Healing draught"
    refute Jason.encode!(later_vineyard_context) =~ "Bronze key"
    refute Jason.encode!(later_dungeon_context) =~ "wine_in_cellar"
    refute Jason.encode!(later_dungeon_context) =~ "cash_on_hand"
  end

  test "historical calendar labels remain free-form GM context across sessions" do
    label = "14 October 1567, two days before the grape pressing"

    campaign =
      campaign_fixture(%{
        title: "Letters from Siena",
        setting: "Northern Italy during the autumn of 1567",
        starting_date: label
      })

    [first_session] = campaign.sessions

    first_context =
      submit_turn_and_capture(campaign, first_session, "history-first", "Read the dated letter.")

    assert first_context["world"]["public"]["date"] == label

    {:ok, next_session} =
      Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{title: "The next letter"})

    next_context =
      submit_turn_and_capture(campaign, next_session, "history-later", "Read the next letter.")

    assert next_context["world"]["public"]["date"] == label
    assert next_context["elapsed_world_clock"]["anchor"]["date"] == label
  end

  test "campaigns without genre resources can play without forced genre mechanics" do
    campaign =
      campaign_fixture(%{
        title: "A Quiet Conversation",
        premise: "Two siblings discuss a letter at home.",
        setting: "A contemporary family kitchen",
        tone: "Grounded and intimate"
      })

    [session] = campaign.sessions

    captured_request = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "unconfigured-genre", "Ask what happened.",
               provider: fn request ->
                 Agent.update(captured_request, fn _ -> request end)
                 {:ok, Jason.encode!(ordinary_proposal())}
               end,
               model: "test-model"
             )

    request = Agent.get(captured_request, & &1)
    context = decode_request(request)

    assert context["inventory"] == %{"player_visible" => [], "gm_private" => []}
    assert context["panels"] == []

    assert request.instructions
           |> String.replace(~r/\s+/, " ")
           |> String.contains?(
             "Match established stakes; add no forced drama or unestablished mechanics."
           )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.inventory == []
    assert projection.panels == []

    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.map(events, & &1.event_type) == [:player_action, :gm_narration]
    refute Enum.any?(events, &(&1.event_type == :roll_request))
  end

  defp submit_turn_and_capture(campaign, session, key, action) do
    captured = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, key, action,
               provider: fn request ->
                 Agent.update(captured, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(ordinary_proposal())}
               end,
               model: "test-model"
             )

    Agent.get(captured, & &1)
  end

  defp decode_request(request) do
    request.input
    |> Enum.find(&Map.has_key?(&1, :content))
    |> Map.fetch!(:content)
    |> Jason.decode!()
  end

  defp ordinary_proposal do
    %{
      "narration" => "The record lies open on the table.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "character_updates" => [],
      "character_creations" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "location_changes" => [],
      "travel_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "continuity_changes" => [],
      "time_advance_minutes" => 0,
      "roll_request" => nil
    }
  end
end
