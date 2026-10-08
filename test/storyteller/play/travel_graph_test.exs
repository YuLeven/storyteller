defmodule Storyteller.Play.TravelGraphTest do
  use ExUnit.Case, async: true

  alias Storyteller.Play.TravelGraph

  @places [
    %{place_id: "finca", visibility: :public},
    %{place_id: "crossroads", visibility: :public},
    %{place_id: "bodega", visibility: :public},
    %{place_id: "hidden-cellar", visibility: :gm_private}
  ]

  @connections [
    %{
      place_a_id: "finca",
      place_b_id: "crossroads",
      travel_minutes: 10,
      visibility: :public
    },
    %{
      place_a_id: "bodega",
      place_b_id: "crossroads",
      travel_minutes: 30,
      visibility: :public
    }
  ]

  test "computes the shortest known route rather than trusting model supplied duration" do
    assert {:ok, %{travel_minutes: 40, place_ids: ["finca", "crossroads", "bodega"]}} =
             TravelGraph.shortest_route("finca", "bodega", @connections)

    assert {:ok, 40} = TravelGraph.shortest_minutes("finca", "bodega", @connections)

    assert {:error, :unconnected_move} =
             TravelGraph.shortest_minutes("finca", "hidden-cellar", @connections)
  end

  test "validates a move from canonical character presence and annotates computed minutes" do
    characters = [
      %{speaker_id: "player", current_place_id: "finca"},
      %{speaker_id: "npc:keeper", current_place_id: "bodega"}
    ]

    changes = [
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => "bodega",
        "reason" => "The player travels to the cellar."
      }
    ]

    assert {:ok, [move], locations} =
             TravelGraph.validate_movements(changes, characters, @connections, "finca")

    assert move["travel_minutes"] == 40
    assert locations["player"] == "bodega"
  end

  test "player movement cannot use a GM-private route" do
    private_route = [
      %{
        place_a_id: "finca",
        place_b_id: "bodega",
        travel_minutes: 40,
        visibility: :gm_private
      }
    ]

    assert {:ok, [move], locations} =
             TravelGraph.validate_movements(
               [%{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}],
               [%{speaker_id: "player", current_place_id: "finca"}],
               private_route,
               "finca",
               MapSet.new(),
               0,
               MapSet.new(["finca", "bodega"])
             )

    refute Map.has_key?(move, "travel_minutes")
    assert locations["player"] == "bodega"
  end

  test "accepts a player move between established public places without inventing route time" do
    changes = [%{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}]
    characters = [%{speaker_id: "player", current_place_id: "finca"}]

    assert {:ok, [move], locations} =
             TravelGraph.validate_movements(
               changes,
               characters,
               [],
               "finca",
               MapSet.new(),
               0,
               MapSet.new(["finca", "bodega"])
             )

    refute Map.has_key?(move, "travel_minutes")
    assert locations["player"] == "bodega"

    assert {:error, :unconnected_move} =
             TravelGraph.validate_movements(
               [
                 %{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"},
                 %{
                   "type" => "move_character",
                   "speaker_id" => "npc:keeper",
                   "place_id" => "bodega"
                 }
               ],
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{speaker_id: "npc:keeper", current_place_id: "crossroads"}
               ],
               [],
               "finca",
               MapSet.new(),
               0,
               MapSet.new(["finca", "bodega"])
             )
  end

  test "a co-present companion can follow the same unrecorded public player leg" do
    changes = [
      %{"type" => "move_character", "speaker_id" => "npc:companion", "place_id" => "bodega"},
      %{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}
    ]

    assert {:ok, [companion_move, player_move], locations} =
             TravelGraph.validate_movements(
               changes,
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{speaker_id: "npc:companion", current_place_id: "finca"}
               ],
               [],
               "finca",
               MapSet.new(),
               0,
               MapSet.new(["finca", "bodega"])
             )

    refute Map.has_key?(companion_move, "travel_minutes")
    refute Map.has_key?(player_move, "travel_minutes")
    assert locations["player"] == "bodega"
    assert locations["npc:companion"] == "bodega"
  end

  test "an active duty still blocks departure over an unrecorded route" do
    assert {:error, :active_duty} =
             TravelGraph.validate_movements(
               [
                 %{
                   "type" => "move_character",
                   "speaker_id" => "npc:keeper",
                   "place_id" => "bodega"
                 }
               ],
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{
                   speaker_id: "npc:keeper",
                   current_place_id: "finca",
                   duty_name: "Watch the tasting room",
                   duty_place_id: "finca",
                   duty_release_at_world_minute: nil
                 }
               ],
               [],
               "finca",
               MapSet.new(),
               0,
               MapSet.new(["finca", "bodega"])
             )
  end

  test "rejects disconnected and unknown-origin moves unless first placement is authorized" do
    assert {:error, :unconnected_move} =
             TravelGraph.validate_movements(
               [%{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}],
               [%{speaker_id: "player", current_place_id: "finca"}],
               [],
               "finca"
             )

    assert {:error, :unknown_origin} =
             TravelGraph.validate_movements(
               [
                 %{
                   "type" => "move_character",
                   "speaker_id" => "npc:existing",
                   "place_id" => "finca"
                 }
               ],
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{speaker_id: "npc:existing", current_place_id: nil}
               ],
               [],
               "finca"
             )

    assert {:ok, [%{"travel_minutes" => 0}], locations} =
             TravelGraph.validate_movements(
               [%{"type" => "move_character", "speaker_id" => "npc:new", "place_id" => "finca"}],
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{speaker_id: "npc:new", current_place_id: nil}
               ],
               [],
               "finca",
               MapSet.new(["npc:new"])
             )

    assert locations["npc:new"] == "finca"
    assert TravelGraph.public_lines_in_scene?([%{speaker_id: "npc:new"}], locations, "finca")

    assert {:ok, [%{"travel_minutes" => 0}], same_place_locations} =
             TravelGraph.validate_movements(
               [
                 %{
                   "type" => "move_character",
                   "speaker_id" => "npc:keeper",
                   "place_id" => "finca"
                 }
               ],
               [
                 %{speaker_id: "player", current_place_id: "finca"},
                 %{speaker_id: "npc:keeper", current_place_id: "finca"}
               ],
               [],
               "finca"
             )

    assert same_place_locations["npc:keeper"] == "finca"
  end

  test "computes each leg when one turn moves a character through several connected places" do
    moves = [
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => "crossroads"
      },
      %{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}
    ]

    assert {:ok, [%{"travel_minutes" => 10}, %{"travel_minutes" => 30}], locations} =
             TravelGraph.validate_movements(
               moves,
               [%{speaker_id: "player", current_place_id: "finca"}],
               @connections,
               "finca"
             )

    assert locations["player"] == "bodega"
  end

  test "accepts dialogue when the NPC arrives in the same response and rejects remote chatter" do
    characters = [
      %{speaker_id: "player", current_place_id: "finca"},
      %{speaker_id: "npc:keeper", current_place_id: "bodega"}
    ]

    lines = [%{speaker_id: "npc:keeper", text: "The wine is ready."}]

    refute TravelGraph.public_lines_in_scene?(
             lines,
             %{"player" => "finca", "npc:keeper" => "bodega"},
             "finca"
           )

    refute TravelGraph.public_lines_in_scene?(lines, %{"npc:keeper" => nil}, nil)

    assert {:ok, _moves, final_locations} =
             TravelGraph.validate_movements(
               [
                 %{
                   "type" => "move_character",
                   "speaker_id" => "npc:keeper",
                   "place_id" => "finca"
                 }
               ],
               characters,
               @connections,
               "finca"
             )

    assert TravelGraph.public_lines_in_scene?(lines, final_locations, "finca")
  end

  test "validates and normalizes connection operations while protecting private routes" do
    create = %{
      "type" => "create_connection",
      "place_a_id" => "bodega",
      "place_b_id" => "finca",
      "travel_minutes" => 40,
      "scene_relevance" => "A winding road along the river.",
      "visibility" => "public",
      "reason" => "The road between the finca and bodega is established."
    }

    assert {:ok, [normalized]} = TravelGraph.validate_changes([create], @places, [])
    assert normalized["place_a_id"] == "bodega"
    assert normalized["place_b_id"] == "finca"

    private_edge = %{create | "place_a_id" => "finca", "place_b_id" => "hidden-cellar"}

    assert {:error, :private_place_connection_cannot_be_public} =
             TravelGraph.validate_changes([private_edge], @places, [])

    invalid_duration = %{create | "travel_minutes" => 0}

    assert {:error, :invalid_duration} =
             TravelGraph.validate_changes([invalid_duration], @places, [])

    assert {:error, :duplicate_connection} =
             TravelGraph.validate_changes([create], @places, [
               %{
                 place_a_id: "finca",
                 place_b_id: "bodega",
                 travel_minutes: 40,
                 visibility: :public
               }
             ])
  end

  test "allows a newly established route to support a movement in the same accepted proposal" do
    proposed = %{
      "type" => "create_connection",
      "place_a_id" => "finca",
      "place_b_id" => "bodega",
      "travel_minutes" => 40,
      "visibility" => "public",
      "reason" => "The road is established."
    }

    assert {:ok, [edge]} = TravelGraph.validate_changes([proposed], @places, [])

    assert {:ok, canonical_graph} = TravelGraph.merge_changes([], [edge])

    assert {:ok, [%{"travel_minutes" => 40}], %{"player" => "bodega"}} =
             TravelGraph.validate_movements(
               [%{"type" => "move_character", "speaker_id" => "player", "place_id" => "bodega"}],
               [%{speaker_id: "player", current_place_id: "finca"}],
               canonical_graph,
               "finca"
             )
  end
end
