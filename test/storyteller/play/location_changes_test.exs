defmodule Storyteller.Play.LocationChangesTest do
  use ExUnit.Case, async: true

  alias Storyteller.Play.LocationChanges

  @speakers ["player", "lyra"]

  defp place(overrides \\ %{}) do
    Map.merge(
      %{
        "place_id" => "old-quarry",
        "name" => "Old quarry",
        "visibility" => "public",
        "facts" => %{"region" => "North ridge"}
      },
      overrides
    )
  end

  defp create_change(overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "watchtower",
          "name" => "The watchtower",
          "description" => "A ruined lookout above the lake.",
          "visibility" => "public",
          "facts" => %{"floor" => 2, "doors" => ["north", "east"]}
        },
        "reason" => "The party finds the tower"
      },
      overrides
    )
  end

  defp move_change(overrides \\ %{}) do
    Map.merge(
      %{
        "type" => "move_character",
        "speaker_id" => "lyra",
        "place_id" => "old-quarry",
        "reason" => "Lyra follows the trail"
      },
      overrides
    )
  end

  test "creates a place and lets a later operation move a character there" do
    assert {:ok, [created, moved]} =
             LocationChanges.validate(
               [create_change(), move_change(%{"place_id" => "watchtower"})],
               [place()],
               @speakers
             )

    assert created["type"] == "create_place"
    assert created["place"]["place_id"] == "watchtower"
    assert created["visibility"] == "public"

    assert moved == %{
             "type" => "move_character",
             "speaker_id" => "lyra",
             "place_id" => "watchtower",
             "reason" => "Lyra follows the trail",
             "visibility" => "public"
           }
  end

  test "keeps GM-private visibility on creation and derives it for movement" do
    private_create =
      create_change(%{
        "place" => %{
          "place_id" => "hidden-cellar",
          "name" => "Hidden cellar",
          "visibility" => "gm_private",
          "facts" => %{"secret" => true}
        }
      })

    private_existing = place(%{"place_id" => "hidden-dock", "visibility" => "gm_private"})

    assert {:ok, [created, moved]} =
             LocationChanges.validate(
               [private_create, move_change(%{"place_id" => "hidden-dock"})],
               [private_existing],
               @speakers
             )

    assert created["visibility"] == "gm_private"
    assert created["place"]["facts"] == %{"secret" => true}
    assert moved["visibility"] == "gm_private"
  end

  test "rejects moving the player to a GM-private place" do
    private_place = place(%{"place_id" => "secret-cellar", "visibility" => "gm_private"})

    assert {:error, :player_cannot_enter_private_place} =
             LocationChanges.validate(
               [move_change(%{"speaker_id" => "player", "place_id" => "secret-cellar"})],
               [private_place],
               @speakers
             )
  end

  test "rejects moves for an unknown character or destination" do
    assert {:error, :unknown_character} =
             LocationChanges.validate(
               [move_change(%{"speaker_id" => "stranger"})],
               [place()],
               @speakers
             )

    assert {:error, :place_not_found} =
             LocationChanges.validate(
               [move_change(%{"place_id" => "missing"})],
               [place()],
               @speakers
             )
  end

  test "rejects a place ID that already exists or is created twice" do
    assert {:error, :duplicate_place_id} =
             LocationChanges.validate(
               [
                 create_change(%{
                   "place" => %{
                     "place_id" => "old-quarry",
                     "name" => "Again",
                     "visibility" => "public"
                   }
                 })
               ],
               [place()],
               @speakers
             )

    assert {:error, :duplicate_place_id} =
             LocationChanges.validate([create_change(), create_change()], [], @speakers)
  end

  test "rejects unknown keys, malformed JSON facts, invalid visibility, and oversized lists" do
    with_extra_key = Map.put(create_change(), "gm_override", true)

    bad_facts =
      create_change(%{
        "place" => %{
          "place_id" => "unsafe-facts",
          "name" => "Unsafe",
          "visibility" => "public",
          "facts" => %{private_atom_key: "not JSON"}
        }
      })

    bad_visibility =
      create_change(%{
        "place" => %{
          "place_id" => "unknown-visibility",
          "name" => "Unknown",
          "visibility" => "everyone",
          "facts" => %{}
        }
      })

    too_deep_facts = Enum.reduce(1..10, "end", fn _, nested -> %{"nested" => nested} end)

    deeply_nested =
      create_change(%{
        "place" => %{
          "place_id" => "deep-facts",
          "name" => "Deep",
          "visibility" => "public",
          "facts" => too_deep_facts
        }
      })

    assert {:error, :unknown_key} = LocationChanges.validate([with_extra_key], [], @speakers)
    assert {:error, :invalid_facts} = LocationChanges.validate([bad_facts], [], @speakers)
    assert {:error, :invalid_facts} = LocationChanges.validate([deeply_nested], [], @speakers)

    assert {:error, :invalid_visibility} =
             LocationChanges.validate([bad_visibility], [], @speakers)

    assert {:error, :invalid_changes} =
             LocationChanges.validate(List.duplicate(move_change(), 51), [place()], @speakers)
  end

  test "requires schema-compatible stable IDs" do
    invalid_id =
      create_change(%{
        "place" => %{
          "place_id" => "place.with.dot",
          "name" => "Invalid ID",
          "visibility" => "public"
        }
      })

    assert {:error, :invalid_id} = LocationChanges.validate([invalid_id], [], @speakers)

    assert {:error, :invalid_speaker_ids} =
             LocationChanges.validate([], [], ["speaker with space"])
  end

  test "fails the entire sequence if a later operation is invalid" do
    before_places = [place()]
    changes = [create_change(), move_change(%{"speaker_id" => "unknown"})]

    assert {:error, :unknown_character} =
             LocationChanges.validate(changes, before_places, @speakers)

    assert before_places == [place()]
    assert changes == [create_change(), move_change(%{"speaker_id" => "unknown"})]
  end
end
