defmodule Storyteller.GM.CampaignLookupTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.CampaignLookup

  test "declares a Responses function tool with a required concise query and optional category" do
    spec = CampaignLookup.tool_spec()

    assert spec["type"] == "function"
    assert spec["name"] == "lookup_campaign_canon"
    assert spec["parameters"]["required"] == ["query"]

    assert spec["parameters"]["properties"]["category"]["enum"] ==
             ~w(any character place inventory objective world continuity memory panel)

    assert byte_size(Jason.encode!(spec)) < 2_000
    refute Map.has_key?(spec["parameters"]["properties"], "campaign_id")
  end

  test "retrieves distant matching character, place, item, objective, and world canon" do
    context = source_context()

    character =
      context
      |> CampaignLookup.execute(%{"query" => "French beaver cook", "category" => "character"})
      |> record("character", "marisol")

    assert character["visibility"] == "public"
    assert character["fields"]["current_place_id"] == "finca"
    assert character["fields"]["voice"] =~ "French beaver cook"

    place =
      context
      |> CampaignLookup.execute(%{"query" => "west observatory", "category" => "place"})
      |> record("place", "west-observatory")

    assert place["fields"]["status"] == "sealed"
    assert place["fields"]["description"] =~ "iron archive"

    item =
      context
      |> CampaignLookup.execute(%{"query" => "cobalt key", "category" => "inventory"})
      |> record("inventory", "cobalt-key")

    assert item["fields"]["quantity"] == 1
    assert item["fields"]["owner_id"] == "player"

    objective =
      context
      |> CampaignLookup.execute(%{
        "query" => "recover observatory ledger",
        "category" => "objective"
      })
      |> record("objective", "recover-ledger")

    assert objective["fields"]["status"] == "active"
    assert objective["fields"]["current_place_id"] == "west-observatory"

    world =
      context
      |> CampaignLookup.execute(%{"query" => "iron archive bell", "category" => "world"})
      |> record("world", "world:archive_bell")

    assert world["fields"]["value"] =~ "silent"
  end

  test "keeps public and GM-private facts in separate records" do
    context = %{
      characters: [
        %{
          speaker_id: "mara",
          name: "Mara Vale",
          role: :gm,
          current_place_id: "finca",
          visible_facts: %{
            voice: "A measured, warm voice.",
            detail: "Knows the old cellar.",
            secret: "nested public leak"
          },
          gm_private_facts: %{fear: "She fears the sealed observatory."}
        }
      ]
    }

    response = CampaignLookup.execute(context, %{query: "Mara Vale", category: :character})
    public_record = Enum.find(response["records"], &(&1["visibility"] == "public"))
    private_record = Enum.find(response["records"], &(&1["visibility"] == "gm_private"))
    assert public_record["fields"]["visible_facts"]["voice"] == "A measured, warm voice."
    refute Jason.encode!(public_record) =~ "sealed observatory"
    refute Jason.encode!(public_record) =~ "nested public leak"
    assert Jason.encode!(private_record) =~ "sealed observatory"
  end

  test "keeps characters in a GM-private place inside GM-private lookup scope" do
    context = %{
      characters: [
        %{
          speaker_id: "npc:the-sleeper",
          name: "The Sleeper",
          role: :gm,
          current_place_id: "sealed-vault",
          current_place: %{place_id: "sealed-vault", visibility: :gm_private},
          visible_facts: %{occupation: "An archivist"},
          gm_private_facts: %{secret: "Still inside the sealed vault."}
        }
      ],
      places: %{
        public: [],
        gm_private: [
          %{place_id: "sealed-vault", name: "Sealed Vault", visibility: :gm_private}
        ]
      }
    }

    response =
      CampaignLookup.execute(context, %{
        "query" => "The Sleeper sealed vault",
        "category" => "character"
      })

    assert [%{"visibility" => "gm_private", "fields" => fields}] = response["records"]
    assert fields["current_place_id"] == "sealed-vault"
    assert fields["visible_facts"]["occupation"] == "An archivist"
    refute Enum.any?(response["records"], &(&1["visibility"] == "public"))
    assert Jason.encode!(response["records"]) =~ "Still inside the sealed vault."
  end

  test "bounds encoded results and marks omitted matches and details" do
    world =
      Map.new(1..90, fn index ->
        {"ember_archive_#{index}", String.duplicate("ember ember archive detail ", 80)}
      end)

    context = %{world: %{public: world}}
    response = CampaignLookup.execute(context, %{"query" => "ember archive"})

    assert length(response["records"]) <= 5
    assert byte_size(Jason.encode!(response)) <= 6_000
    assert response["completeness"]["matches_found"] == 90
    assert response["completeness"]["records_returned"] <= 5
    assert response["completeness"]["matches_omitted"]
    assert response["completeness"]["details_omitted"]
    assert Enum.all?(response["records"], & &1["details_truncated"])
  end

  test "rejects empty, oversized, and invalid-category queries with JSON-safe errors" do
    assert %{"error" => _, "records" => [], "complete" => true} =
             CampaignLookup.execute(%{}, %{"query" => "   "})

    assert %{"error" => _, "records" => [], "complete" => true} =
             CampaignLookup.execute(%{}, %{"query" => String.duplicate("x", 161)})

    assert %{"error" => _, "records" => [], "complete" => true} =
             CampaignLookup.execute(%{}, %{"query" => "finca", "category" => "invented"})

    assert {:ok, _json} = CampaignLookup.execute(%{}, %{"query" => "missing"}) |> Jason.encode()
  end

  test "does not return history as canon and does not mutate its input context" do
    context = source_context()
    context = Map.put(context, :history, [%{"payload" => %{"text" => "The emerald bell rings."}}])
    before = :erlang.term_to_binary(context)

    assert CampaignLookup.execute(context, %{"query" => "emerald"})["records"] == []
    assert :erlang.term_to_binary(context) == before
  end

  defp record(response, category, id) do
    assert response["completeness"]["records_returned"] > 0

    Enum.find(response["records"], &(&1["category"] == category and &1["id"] == id)) ||
      flunk("Expected #{category} record #{id}, got #{inspect(response)}")
  end

  defp source_context do
    %{
      campaign: %{id: 12, title: "The Quiet Observatory", premise: "A remote archive mystery"},
      characters: [
        %{
          speaker_id: "marisol",
          name: "Marisol",
          role: :gm,
          current_place_id: "finca",
          visible_facts: %{},
          voice: "A patient French beaver cook with a clipped, musical accent."
        }
      ],
      places: %{
        public: [
          %{
            place_id: "finca",
            name: "Finca",
            description: "Home vineyard.",
            status: "occupied"
          },
          %{
            place_id: "west-observatory",
            name: "West Observatory",
            description: "The iron archive holds a bell beneath the old chart table.",
            status: "sealed"
          }
        ],
        gm_private: []
      },
      inventory: %{
        player_visible: [
          %{
            id: "cobalt-key",
            name: "Cobalt key",
            quantity: 1,
            unit: "key",
            owner_id: "player",
            description: "Opens the west observatory archive."
          }
        ],
        gm_private: []
      },
      objectives: %{
        public: [
          %{
            id: "recover-ledger",
            title: "Recover observatory ledger",
            status: "active",
            current_place_id: "west-observatory",
            details: "Find the archive ledger before the next bell."
          }
        ],
        gm_private: []
      },
      world: %{public: %{archive_bell: "The iron archive bell is silent."}, gm_private: %{}},
      continuity: %{public: [], gm_private: []},
      memory: %{public_summary: "The player has not entered the west observatory."},
      panels: []
    }
  end
end
