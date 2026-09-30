defmodule Storyteller.Play.InventoryTest do
  use ExUnit.Case, async: true

  alias Storyteller.Play.Inventory

  @owners ["player", "lyra"]

  defp item(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "healing-herbs",
        "name" => "Healing herbs",
        "quantity" => 3,
        "unit" => "bundle",
        "category" => "supplies",
        "owner_id" => "player",
        "visibility" => "public",
        "properties" => %{"healing" => %{"points" => 2}}
      },
      overrides
    )
  end

  describe "normalize_initial/2" do
    test "fills player-friendly defaults and keeps flexible JSON properties" do
      assert {:ok, [normalized]} =
               Inventory.normalize_initial(
                 [Map.drop(item(), ["owner_id", "visibility", "properties"])],
                 @owners
               )

      assert normalized["owner_id"] == "player"
      assert normalized["visibility"] == "public"
      assert normalized["properties"] == %{}
    end

    test "assigns deterministic unique IDs to setup rows without IDs" do
      rows = [
        %{"name" => "Field journal", "quantity" => 1},
        %{"name" => "Trail rations", "quantity" => 4}
      ]

      assert {:ok, first} = Inventory.normalize_initial(rows, @owners)
      assert {:ok, second} = Inventory.normalize_initial(rows, @owners)
      assert Enum.map(first, & &1["id"]) == Enum.map(second, & &1["id"])
      assert length(Enum.uniq(Enum.map(first, & &1["id"]))) == 2
      assert Enum.all?(first, &String.starts_with?(&1["id"], "initial-"))
    end

    test "rejects duplicate IDs and owners outside the campaign" do
      assert {:error, :duplicate_item_id} = Inventory.normalize_initial([item(), item()], @owners)

      assert {:error, :invalid_owner} =
               Inventory.normalize_initial([item(%{"owner_id" => "stranger"})], @owners)
    end

    test "trims valid owner IDs before matching item ownership" do
      assert {:ok, [%{"owner_id" => "lyra"}]} =
               Inventory.normalize_initial([item(%{"owner_id" => " lyra "})], [" lyra "])
    end
  end

  describe "validate_changes/3 and apply_changes/2" do
    test "adds a new canonical item and retains arbitrary JSON properties" do
      added =
        item(%{
          "id" => "old-map",
          "name" => "Old map",
          "quantity" => 1,
          "properties" => %{"grid" => [8, 4]}
        })

      changes = [%{"type" => "add", "item" => added, "reason" => "Found in the desk"}]

      assert {:ok, [normalized]} = Inventory.validate_changes(changes, [], @owners)
      assert normalized["item"]["properties"] == %{"grid" => [8, 4]}
      assert normalized["visibility"] == "public"
      assert Inventory.apply_changes([], [normalized]) == [normalized["item"]]
    end

    test "transfers a whole stack and consumes only the requested quantity" do
      changes = [
        %{
          "type" => "transfer",
          "item_id" => "healing-herbs",
          "owner_id" => "lyra",
          "reason" => "Lyra carries the pack"
        },
        %{
          "type" => "consume",
          "item_id" => "healing-herbs",
          "quantity" => 2,
          "reason" => "Used to treat a wound"
        }
      ]

      assert {:ok, normalized} = Inventory.validate_changes(changes, [item()], @owners)
      assert Enum.map(normalized, & &1["visibility"]) == ["public", "public"]

      assert [%{"owner_id" => "lyra", "quantity" => 1}] =
               Inventory.apply_changes([item()], normalized)
    end

    test "partially transfers a stack into a new stack with copied fields" do
      change = %{
        "type" => "transfer",
        "item_id" => "healing-herbs",
        "quantity" => 1,
        "new_item_id" => "lyra-healing-herbs",
        "owner_id" => "lyra",
        "reason" => "Lyra takes one bundle"
      }

      assert {:ok, [normalized]} = Inventory.validate_changes([change], [item()], @owners)

      assert normalized == %{
               "type" => "transfer",
               "item_id" => "healing-herbs",
               "new_item_id" => "lyra-healing-herbs",
               "item_name" => "Healing herbs",
               "quantity" => 1,
               "unit" => "bundle",
               "owner_id" => "lyra",
               "reason" => "Lyra takes one bundle",
               "visibility" => "public"
             }

      assert Inventory.apply_changes([item()], [normalized]) == [
               item(%{"quantity" => 2}),
               item(%{
                 "id" => "lyra-healing-herbs",
                 "quantity" => 1,
                 "owner_id" => "lyra"
               })
             ]
    end

    test "whole-stack transfer keeps its established normalized event shape" do
      change = %{
        "type" => "transfer",
        "item_id" => "healing-herbs",
        "owner_id" => "lyra",
        "reason" => "Lyra takes the whole bundle"
      }

      assert {:ok, [normalized]} = Inventory.validate_changes([change], [item()], @owners)

      assert normalized == %{
               "type" => "transfer",
               "item_id" => "healing-herbs",
               "item_name" => "Healing herbs",
               "quantity" => 3,
               "unit" => "bundle",
               "owner_id" => "lyra",
               "reason" => "Lyra takes the whole bundle",
               "visibility" => "public"
             }

      assert Inventory.apply_changes([item()], [normalized]) == [item(%{"owner_id" => "lyra"})]
    end

    test "rejects invalid or colliding IDs and quantities for partial transfers" do
      transfer = fn overrides ->
        Map.merge(
          %{
            "type" => "transfer",
            "item_id" => "healing-herbs",
            "quantity" => 1,
            "new_item_id" => "lyra-healing-herbs",
            "owner_id" => "lyra",
            "reason" => "Lyra takes one bundle"
          },
          overrides
        )
      end

      existing_id = item(%{"id" => "already-here", "name" => "Rations"})

      assert {:error, :duplicate_item_id} =
               Inventory.validate_changes(
                 [transfer.(%{"new_item_id" => "already-here"})],
                 [item(), existing_id],
                 @owners
               )

      assert {:error, :duplicate_item_id} =
               Inventory.validate_changes(
                 [transfer.(%{"new_item_id" => "healing-herbs"})],
                 [item()],
                 @owners
               )

      assert {:error, :invalid_id} =
               Inventory.validate_changes([transfer.(%{"new_item_id" => " "})], [item()], @owners)

      assert {:error, :invalid_id} =
               Inventory.validate_changes(
                 [Map.delete(transfer.(%{}), "new_item_id")],
                 [item()],
                 @owners
               )

      assert {:error, :invalid_quantity} =
               Inventory.validate_changes([transfer.(%{"quantity" => 0})], [item()], @owners)

      assert {:error, :invalid_quantity} =
               Inventory.validate_changes([transfer.(%{"quantity" => 3})], [item()], @owners)

      assert {:error, :insufficient_quantity} =
               Inventory.validate_changes([transfer.(%{"quantity" => 4})], [item()], @owners)
    end

    test "rejects an unknown item or owner in a partial transfer" do
      change = %{
        "type" => "transfer",
        "item_id" => "healing-herbs",
        "quantity" => 1,
        "new_item_id" => "lyra-healing-herbs",
        "owner_id" => "lyra",
        "reason" => "Lyra takes one bundle"
      }

      assert {:error, :item_not_found} =
               Inventory.validate_changes(
                 [Map.put(change, "item_id", "missing")],
                 [item()],
                 @owners
               )

      assert {:error, :invalid_owner} =
               Inventory.validate_changes(
                 [Map.put(change, "owner_id", "stranger")],
                 [item()],
                 @owners
               )
    end

    test "rejects the entire split-transfer proposal when a later operation fails" do
      before = [item()]

      changes = [
        %{
          "type" => "transfer",
          "item_id" => "healing-herbs",
          "quantity" => 1,
          "new_item_id" => "lyra-healing-herbs",
          "owner_id" => "lyra",
          "reason" => "Lyra takes one bundle"
        },
        %{
          "type" => "consume",
          "item_id" => "healing-herbs",
          "quantity" => 3,
          "reason" => "Use more than remains"
        }
      ]

      assert {:error, :insufficient_quantity} =
               Inventory.validate_changes(changes, before, @owners)

      assert before == [item()]
    end

    test "removes a stack when the final quantity is consumed" do
      change = %{
        "type" => "consume",
        "item_id" => "healing-herbs",
        "quantity" => 3,
        "reason" => "The herbs were used"
      }

      assert {:ok, normalized} = Inventory.validate_changes([change], [item()], @owners)
      assert Inventory.apply_changes([item()], normalized) == []
    end

    test "rejects the entire proposed change list when a later operation is invalid" do
      before = [item()]

      changes = [
        %{
          "type" => "consume",
          "item_id" => "healing-herbs",
          "quantity" => 1,
          "reason" => "Use one"
        },
        %{
          "type" => "consume",
          "item_id" => "healing-herbs",
          "quantity" => 9,
          "reason" => "Use too many"
        }
      ]

      assert {:error, :insufficient_quantity} =
               Inventory.validate_changes(changes, before, @owners)

      assert before == [item()]
    end

    test "rejects unknown keys, missing IDs, duplicate IDs, and invalid owners" do
      assert {:error, :unknown_key} =
               Inventory.validate_changes(
                 [
                   %{
                     "type" => "consume",
                     "item_id" => "healing-herbs",
                     "quantity" => 1,
                     "reason" => "Use one",
                     "secret" => true
                   }
                 ],
                 [item()],
                 @owners
               )

      assert {:error, :item_not_found} =
               Inventory.validate_changes(
                 [
                   %{
                     "type" => "transfer",
                     "item_id" => "missing",
                     "owner_id" => "lyra",
                     "reason" => "Move it"
                   }
                 ],
                 [item()],
                 @owners
               )

      assert {:error, :duplicate_item_id} =
               Inventory.validate_changes(
                 [%{"type" => "add", "item" => item(), "reason" => "Duplicate"}],
                 [item()],
                 @owners
               )

      assert {:error, :invalid_owner} =
               Inventory.validate_changes(
                 [
                   %{
                     "type" => "transfer",
                     "item_id" => "healing-herbs",
                     "owner_id" => "unknown",
                     "reason" => "Move it"
                   }
                 ],
                 [item()],
                 @owners
               )

      assert {:error, :unknown_key} =
               Inventory.validate_changes(
                 [
                   Map.put(
                     %{
                       "type" => "consume",
                       "item_id" => "healing-herbs",
                       "quantity" => 1,
                       "reason" => "Use one"
                     },
                     :type,
                     "consume"
                   )
                 ],
                 [item()],
                 @owners
               )
    end

    test "rejects non-JSON properties and oversized lists" do
      atom_key_properties = item(%{"properties" => %{unsafe: "not JSON"}})
      too_many_changes = List.duplicate(%{"type" => "invalid"}, 51)

      assert {:error, :invalid_properties} =
               Inventory.normalize_initial([atom_key_properties], @owners)

      assert {:error, :invalid_changes} =
               Inventory.validate_changes(too_many_changes, [], @owners)
    end

    test "does not exceed the campaign stack limit with an add or partial transfer" do
      inventory =
        Enum.map(1..200, fn index ->
          item(%{"id" => "stack-#{index}", "name" => "Supply #{index}"})
        end)

      add = %{
        "type" => "add",
        "item" => item(%{"id" => "extra-stack", "name" => "Extra supply"}),
        "reason" => "Found more supplies"
      }

      split = %{
        "type" => "transfer",
        "item_id" => "stack-1",
        "quantity" => 1,
        "new_item_id" => "split-stack",
        "owner_id" => "lyra",
        "reason" => "Lyra takes one bundle"
      }

      assert {:error, :inventory_limit} = Inventory.validate_changes([add], inventory, @owners)

      assert {:error, :inventory_limit} =
               Inventory.validate_changes([split], inventory, @owners)
    end
  end

  test "hides GM-private inventory from the player projection" do
    public_item = item()

    private_item =
      item(%{"id" => "poison", "name" => "Unmarked poison", "visibility" => "gm_private"})

    assert Inventory.public_projection([public_item, private_item]) == [public_item]
  end
end
