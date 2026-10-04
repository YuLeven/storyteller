defmodule Storyteller.GM.ContextBudgetTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.{CampaignLookup, ContextBudget}

  test "compacts unrelated history while retrieving an older fact named in the action" do
    context =
      base_context()
      |> Map.put(
        :player_action,
        "Check whether Marisol stayed at the Finca after the forty-minute trip to the Bodega."
      )

    history =
      Enum.map(1..50, fn sequence ->
        text =
          if sequence == 5 do
            "A bodega forty minutes from the Finca; Marisol stayed at the Finca. " <>
              String.duplicate("specific older note ", 70)
          else
            "Unrelated market report #{sequence}. " <> String.duplicate("unrelated detail ", 70)
          end

        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{"text" => text}
        }
      end)

    context = Map.put(context, :history, history)

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra",
               context_input_byte_budget: 20_000
             )

    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= 20_000
    assert length(compacted.history) <= 20
    assert Enum.any?(compacted.history, &(&1["sequence"] == 5))
    assert Enum.any?(compacted.history, &(&1["sequence"] == 50))
    assert compacted.context_completeness.history_compacted

    assert compacted.characters
           |> Enum.find(&(&1.speaker_id == "marisol"))
           |> Map.fetch!(:current_place_id) ==
             "finca"
  end

  test "falls back to compacting long reference prose before rejecting a playable turn" do
    premise = String.duplicate("A vineyard mystery with careful seasonal rituals. ", 200)

    places =
      Enum.map(1..7, fn index ->
        %{
          place_id: "estate-#{index}",
          name: "Estate #{index}",
          visibility: :public,
          description:
            String.duplicate("A detailed but nonessential architectural description. ", 180)
        }
      end)

    action =
      "Visit " <> Enum.map_join(1..7, ", ", &"Estate #{&1}") <> " and compare their old notes."

    context =
      base_context()
      |> put_in([:campaign, :title], String.duplicate("Amber Orchard Campaign ", 5_000))
      |> put_in([:campaign, :premise], premise)
      |> Map.put(:player_action, action)
      |> put_in([:places, :public], places)
      |> put_in([:characters, Access.at(0), :current_place_id], "estate-1")
      |> put_in(
        [:world, :public, :harvest_notes],
        String.duplicate("public vineyard notes ", 300)
      )
      |> put_in(
        [:world, :gm_private, :hidden_notes],
        String.duplicate("private cellar notes ", 300)
      )

    budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= budget
    assert metrics.compacted?
    assert :campaign_details in metrics.omissions
    assert :place_details in metrics.omissions
    assert :context_details in metrics.omissions
    assert compacted.context_completeness.campaign_details_compacted
    assert compacted.context_completeness.place_details_compacted
    assert compacted.context_completeness.context_details_compacted
    assert compacted.player_action == action
    assert compacted.world.public.date == "1567-04-12"
    assert String.length(compacted.campaign.title) <= 160
    assert compacted.places.public |> Enum.map(& &1.place_id) == Enum.map(places, & &1.place_id)

    assert Enum.all?(compacted.places.public, fn place ->
             not is_binary(Map.get(place, :description)) or
               String.length(place.description) <= 900
           end)

    assert context.campaign.premise == premise
    assert String.length(context.campaign.title) > 100_000
    assert Enum.all?(context.places.public, &(String.length(&1.description) > 900))
  end

  test "retrieval packet keeps authoritative scene anchors and leaves omitted canon unknown" do
    player_action = "I ask the keeper what happened at the remote archive."

    current_place = %{
      place_id: "glass-room",
      name: "The Glass Room",
      visibility: :public,
      description: String.duplicate("A crowded observatory wing. ", 900)
    }

    omitted_fact = "The western stair hides a brass chart drawer."
    private_fact = "The keeper secretly altered the chart before dawn."

    context =
      base_context()
      |> Map.put(:player_action, player_action)
      |> Map.put(:interaction_mode, "question")
      |> put_in([:world, :public], %{
        location: "Stale label must not replace place",
        date: "1567-04-12",
        time: "Midnight",
        weather: %{conditions: "Cool mist over the river", wind: "Light"},
        unrelated: String.duplicate("world note ", 2_000)
      })
      |> put_in([:world, :gm_private], %{secret: private_fact})
      |> put_in([:characters, Access.at(0), :current_place_id], "glass-room")
      |> put_in([:characters, Access.at(0), :current_place], current_place)
      |> put_in([:characters, Access.at(0), :name], "Mira Vale")
      |> put_in([:characters, Access.at(1), :current_place_id], "glass-room")
      |> put_in([:characters, Access.at(1), :name], "Keeper Lio")
      |> put_in([:characters, Access.at(1), :current_place], current_place)
      |> put_in([:characters, Access.at(1), :gm_private_facts], %{secret: private_fact})
      |> put_in(
        [:places, :public],
        [current_place] ++
          Enum.map(1..90, fn index ->
            %{
              place_id: "remote-#{index}",
              name: "Remote archive room #{index}",
              visibility: :public,
              description:
                if(index == 1, do: "#{omitted_fact} ", else: "") <>
                  String.duplicate("Distant archive catalog detail. ", 500)
            }
          end)
      )
      |> Map.put(:campaign, %{
        title: "The Quiet Observatory",
        premise: String.duplicate("An old star map. ", 600),
        narration_language: "English"
      })

    source_snapshot = :erlang.term_to_binary(context)
    instructions = "Keep the current scene authoritative."

    assert {:ok, %{context: packet, metrics: metrics, retrieval_packet?: true}} =
             ContextBudget.compile_retrieval_packet(
               context,
               instructions,
               "test-model",
               context_input_byte_budget: 32_000,
               reserve_request_bytes: 24_000
             )

    assert metrics.estimated_request_bytes <= 8_000
    assert packet["player_action"] == player_action
    assert packet["interaction_mode"] == "question"
    assert packet["world"]["public"]["date"] == "1567-04-12"
    assert packet["world"]["public"]["time"] == "Midnight"
    assert packet["world"]["public"]["weather"]["conditions"] == "Cool mist over the river"
    assert packet["world"]["public"]["location"] == "The Glass Room"
    assert Enum.map(packet["characters"], & &1["speaker_id"]) == ["player", "marisol"]

    assert Enum.find(packet["characters"], &(&1["speaker_id"] == "marisol"))["presence"] ==
             "present"

    assert packet["places"]["public"] == [
             %{"place_id" => "glass-room", "name" => "The Glass Room", "visibility" => :public}
           ]

    assert packet["context_completeness"]["retrieval_packet"]
    assert packet["context_completeness"]["omitted_canon_is_unknown"]

    encoded_packet = Jason.encode!(packet)
    refute encoded_packet =~ omitted_fact
    refute encoded_packet =~ private_fact

    retrieved =
      CampaignLookup.execute(context, %{
        "query" => "western stair brass chart drawer",
        "category" => "place"
      })

    assert Enum.any?(retrieved["records"], &(&1["fields"]["description"] =~ omitted_fact))
    refute Jason.encode!(retrieved["records"]) =~ private_fact
    assert :erlang.term_to_binary(context) == source_snapshot
  end

  test "retrieval packet keeps the addressed present character when a crowded scene is truncated" do
    scene_characters =
      Enum.map(1..40, fn index ->
        %{
          speaker_id: "npc:observer-#{index}",
          name: "Observer #{index}",
          role: :gm,
          current_place_id: "finca"
        }
      end) ++
        [
          %{
            speaker_id: "npc:sera",
            name: "Sera Villeneuve",
            role: :gm,
            current_place_id: "finca"
          }
        ]

    base = base_context()
    player = Enum.find(base.characters, &(&1.speaker_id == "player"))

    context =
      base
      |> Map.put(:player_action, "I ask Sera Villeneuve what she found at the observatory.")
      |> Map.put(:characters, [player | scene_characters])

    assert {:ok, %{context: packet, metrics: metrics}} =
             ContextBudget.compile_retrieval_packet(context, "Short GM policy", "test-model",
               context_input_byte_budget: 32_000
             )

    speaker_ids = Enum.map(packet["characters"], & &1["speaker_id"])

    assert length(speaker_ids) == 1 + 32
    assert "player" in speaker_ids
    assert "npc:sera" in speaker_ids
    refute "npc:observer-40" in speaker_ids
    assert packet["context_completeness"]["scene_cast_truncated"]
    assert metrics.estimated_request_bytes <= 32_000
  end

  test "retrieval packet does not mistake a common word for an addressed character name" do
    scene_characters =
      Enum.map(1..40, fn index ->
        %{
          speaker_id: "npc:observer-#{index}",
          name: "Observer #{index}",
          role: :gm,
          current_place_id: "finca"
        }
      end) ++
        [
          %{
            speaker_id: "npc:rosetta",
            name: "Rosetta March",
            role: :gm,
            current_place_id: "finca"
          },
          %{speaker_id: "npc:sera", name: "Sera Vale", role: :gm, current_place_id: "finca"}
        ]

    base = base_context()
    player = Enum.find(base.characters, &(&1.speaker_id == "player"))

    context =
      base
      |> Map.put(:player_action, "I choose a rose for the table, then ask Sera about the chart.")
      |> Map.put(:characters, [player | scene_characters])

    assert {:ok, %{context: packet}} =
             ContextBudget.compile_retrieval_packet(context, "Short GM policy", "test-model",
               context_input_byte_budget: 32_000
             )

    speaker_ids = Enum.map(packet["characters"], & &1["speaker_id"])

    assert "npc:sera" in speaker_ids
    refute "npc:rosetta" in speaker_ids
    assert "npc:observer-31" in speaker_ids
  end

  test "retrieval packet keeps a crowded-scene character addressed by a public role" do
    scene_characters =
      Enum.map(1..40, fn index ->
        %{
          speaker_id: "npc:observer-#{index}",
          name: "Observer #{index}",
          role: :gm,
          current_place_id: "finca"
        }
      end) ++
        [
          %{
            speaker_id: "npc:cook",
            name: "Armand Vey",
            role: :gm,
            current_place_id: "finca",
            visible_facts: %{"occupation" => "cook"}
          }
        ]

    base = base_context()
    player = Enum.find(base.characters, &(&1.speaker_id == "player"))

    context =
      base
      |> Map.put(:player_action, "I ask the cook to describe the bread.")
      |> Map.put(:characters, [player | scene_characters])

    assert {:ok, %{context: packet}} =
             ContextBudget.compile_retrieval_packet(context, "Short GM policy", "test-model",
               context_input_byte_budget: 32_000
             )

    speaker_ids = Enum.map(packet["characters"], & &1["speaker_id"])

    assert "npc:cook" in speaker_ids
    refute "npc:observer-40" in speaker_ids
  end

  test "recalls accented canon across NFC and decomposed Unicode text" do
    nfc = "La dégustation a lieu dans la salle des cartes."
    nfd = String.normalize(nfc, :nfd)

    memory = %{
      entry_id: "map-room-tasting",
      kind: "fact",
      title: "Dégustation",
      details: nfc,
      status: "active",
      visibility: "public",
      player_managed: true
    }

    for {action, details} <- [
          {String.normalize("dégustation", :nfd), nfc},
          {"dégustation", nfd}
        ] do
      context =
        base_context()
        |> Map.put(:player_action, action)
        |> Map.put(:continuity, %{public: [%{memory | details: details}], gm_private: []})

      assert {:ok, %{context: compiled}} =
               ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

      assert Enum.find(compiled.continuity.public, &(&1.entry_id == "map-room-tasting")).details ==
               details
    end

    long_description =
      String.duplicate("Description sans détail. ", 12) <>
        "La dégustation est mentionnée derrière les archives."

    for {query, description} <- [
          {"dégustation", String.normalize(long_description, :nfd)},
          {String.normalize("dégustation", :nfd), long_description}
        ] do
      result =
        CampaignLookup.execute(
          %{
            places: %{
              public: [
                %{
                  place_id: "map-room",
                  name: "Salle des cartes",
                  visibility: :public,
                  description: description
                }
              ]
            }
          },
          %{"query" => query, "category" => "place"}
        )

      assert [record] = result["records"]
      assert String.normalize(record["fields"]["description"], :nfc) =~ "dégustation"
    end
  end

  test "keeps a bounded recent slice of a long continuity ledger" do
    entries =
      Enum.map(1..140, fn index ->
        %{
          entry_id: "observatory-note-#{index}",
          kind: "fact",
          title: "Observatory note #{index}",
          details: "The brass telescope is kept in the east room.",
          status: if(index <= 100, do: "active", else: "completed"),
          visibility: "public"
        }
      end)

    context =
      base_context()
      |> Map.put(:player_action, "Let time pass in the observatory.")
      |> put_in([:continuity, :public], entries)

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert length(compacted.continuity.public) <= 64
    assert Enum.any?(compacted.continuity.public, &(&1.entry_id == "observatory-note-140"))
    assert compacted.context_completeness.continuity_details_omitted
    assert :continuity_details in metrics.omissions
    assert length(context.continuity.public) == 140
  end

  test "fits the maximum inventory by prioritizing item context without changing the source ledger" do
    bulk_inventory =
      Enum.map(1..198, fn sequence ->
        %{
          "id" => "reserve-#{sequence}",
          "name" => "Reserve wine #{sequence}",
          "quantity" => sequence,
          "unit" => "bottle",
          "category" => "wine",
          "owner_id" => "player",
          "visibility" => "public",
          "description" => String.duplicate("Unrelated cellar aging notes. ", 20),
          "properties" => %{
            "vintage" => 1560 + rem(sequence, 10),
            "notes" => String.duplicate("Oak storage details. ", 15)
          }
        }
      end)

    named_item = %{
      "id" => "la-bella-2028",
      "name" => "La Bella 2028",
      "quantity" => 3,
      "unit" => "bottle",
      "category" => "wine",
      "owner_id" => "player",
      "visibility" => "public",
      "description" => "Deep plum, soft tannin, and a long finish.",
      "properties" => %{"vintage" => 2028, "condition" => "young"}
    }

    private_item = %{
      "id" => "hidden-cellar-key",
      "name" => "Cellar key",
      "quantity" => 1,
      "owner_id" => "party",
      "visibility" => "gm_private",
      "description" => "A hidden brass key behind the west cask.",
      "properties" => %{"secret" => "Do not reveal"}
    }

    context =
      base_context()
      |> Map.put(:player_action, "I inspect the La Bella 2028 wine's color and vintage.")
      |> put_in([:inventory, :player_visible], bulk_inventory ++ [named_item])
      |> put_in([:inventory, :gm_private], [private_item])

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, production_gm_policy(), "gpt-6-astra",
               context_input_byte_budget: 24_000
             )

    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= 24_000
    assert :inventory_details in metrics.omissions
    assert compiled.context_completeness.inventory_details_omitted
    assert compiled.context_completeness.inventory_items_omitted

    public_items = compiled.inventory.player_visible
    assert length(public_items) <= 16
    assert length(context.inventory.player_visible) == 199
    assert Enum.any?(public_items, &(&1["id"] == "la-bella-2028"))
    assert Enum.all?(public_items, &Map.has_key?(&1, "quantity"))
    refute Enum.any?(public_items, &(&1["id"] == "reserve-30"))

    preserved_named_item = Enum.find(public_items, &(&1["id"] == "la-bella-2028"))
    assert preserved_named_item["description"] == named_item["description"]
    assert preserved_named_item["properties"] == named_item["properties"]
    assert Enum.count(public_items, &Map.has_key?(&1, "description")) <= 1

    assert [compacted_private_item] = compiled.inventory.gm_private
    assert compacted_private_item["visibility"] == "gm_private"
    assert compacted_private_item["name"] == "Cellar key"
    assert compacted_private_item["description"] == private_item["description"]
    assert compacted_private_item["properties"] == private_item["properties"]
  end

  test "projects oversized world maps while keeping canonical anchors and an action-matched fact" do
    unrelated_public_fields =
      Map.new(1..90, fn index ->
        {"archive_#{index}", String.duplicate("Unrelated regional record. ", 40)}
      end)

    relevant_world_fact =
      "At the autumn tasting, the reserve wine was set aside for the cellar master. " <>
        String.duplicate("Archived notes about the reserve. ", 160)

    public_world =
      Map.merge(unrelated_public_fields, %{
        "date" => "1567-04-12",
        "time" => "before dawn",
        "weather" => "Cool mist over the river",
        "location" => "Bodega",
        "reserved_wine_notes" => relevant_world_fact
      })

    private_world =
      Map.new(1..24, fn index ->
        {"sealed_archive_#{index}", String.duplicate("Unrelated hidden record. ", 40)}
      end)

    context =
      base_context()
      |> Map.put(
        :player_action,
        "At the Bodega, I ask about the reserve wine from the autumn tasting."
      )
      |> put_in([:world, :public], public_world)
      |> put_in([:world, :gm_private], private_world)

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert request_bytes(context, "Short GM policy") > metrics.budget_bytes
    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert metrics.compacted?
    assert :world_state_fields in metrics.omissions
    assert :world_state_details in metrics.omissions
    assert compiled.world.public["date"] == "1567-04-12"
    assert compiled.world.public["time"] == "before dawn"
    assert compiled.world.public["weather"] == "Cool mist over the river"
    assert compiled.world.public["location"] == "Bodega"
    assert compiled.world.public["reserved_wine_notes"] =~ "autumn tasting"

    assert String.length(compiled.world.public["reserved_wine_notes"]) <
             String.length(relevant_world_fact)

    assert map_size(compiled.world.public) <= 32
    assert map_size(compiled.world.gm_private) <= 32
    assert byte_size(Jason.encode!(compiled.world.public)) <= 8_000
    assert byte_size(Jason.encode!(compiled.world.gm_private)) <= 8_000
    assert compiled.context_completeness.world_state_fields_omitted
    assert compiled.context_completeness.world_state_details_compacted
    assert context.world.public == public_world
    assert context.world.gm_private == private_world
  end

  test "keeps action-relevant tracked resources when a campaign defines many panels" do
    panels =
      Enum.map(1..100, fn index ->
        %{
          key: "resource_#{index}",
          panel: "Campaign resources",
          label: "Field ledger #{index}",
          type: :quantity,
          unit: "units",
          visibility: :public,
          value: index
        }
      end)

    relevant_panel = %{
      key: "reserve_wine",
      panel: "Cellar",
      label: "Reserve wine",
      type: :text,
      unit: nil,
      visibility: :public,
      value: String.duplicate("La Bella reserve wine for the autumn tasting. ", 50)
    }

    context =
      base_context()
      |> Map.put(:player_action, "How much reserve wine remains for the autumn tasting?")
      |> Map.put(:panels, List.replace_at(panels, 70, relevant_panel))

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert :panel_fields in metrics.omissions
    assert :panel_values in metrics.omissions
    assert length(compiled.panels) <= 32
    assert byte_size(Jason.encode!(compiled.panels)) <= 8_000
    assert Enum.any?(compiled.panels, &(&1.key == "resource_1"))
    assert [selected] = Enum.filter(compiled.panels, &(&1.key == "reserve_wine"))
    assert selected.value =~ "autumn tasting"
    assert String.length(selected.value) <= 800
    assert compiled.context_completeness.panel_fields_omitted
    assert compiled.context_completeness.panel_values_compacted
    assert length(context.panels) == 100
    assert hd(context.panels).value == 1
    assert String.length(relevant_panel.value) > String.length(selected.value)
  end

  test "bounds growing character, location, and objective canon without losing named scene facts" do
    action =
      "I ask Mira Copper at the Copper Archive about the ledger and whether the Finca staff stayed put."

    noise = String.duplicate("Unrelated regional record. ", 240)

    player = hd(base_context().characters)

    scene_cast =
      Enum.map(1..15, fn index ->
        %{
          speaker_id: "present_#{index}",
          name: "Present witness #{index}",
          role: :gm,
          current_place_id: "finca",
          visible_facts: %{"background" => noise},
          gm_private_facts: %{"background" => noise},
          voice_guidance: %{accent: "Local", mannerisms: noise},
          visible_activity: noise
        }
      end)

    named_character = %{
      speaker_id: "mira_copper",
      name: "Mira Copper",
      role: :gm,
      current_place_id: "archive",
      visible_facts: %{"specialty" => "A careful archivist who reads ledger hands."},
      gm_private_facts: %{
        "ledger_promise" =>
          "Mira promised to bring the original harvest ledger to the Copper Archive."
      },
      voice_guidance: %{
        accent: "French",
        mannerisms: "Touches each page corner before turning it."
      }
    }

    remote_characters =
      Enum.map(1..90, fn index ->
        %{
          speaker_id: "remote_#{index}",
          name: "Remote witness #{index}",
          role: :gm,
          current_place_id: "remote_place_#{index}",
          visible_facts: %{"background" => noise},
          gm_private_facts: %{"background" => noise},
          voice_guidance: %{cadence: noise}
        }
      end)

    distant_places =
      Enum.map(1..90, fn index ->
        %{
          place_id: "remote_place_#{index}",
          name: "Remote Place #{index}",
          visibility: :public,
          description: noise,
          facts: %{"terrain" => noise}
        }
      end)

    archive = %{
      place_id: "archive",
      name: "The Copper Archive",
      visibility: :public,
      description: "The Copper Archive holds the harvest ledger. " <> noise,
      facts: %{
        "ledger" => "The original ledger is in a locked case in the Copper Archive. " <> noise
      }
    }

    gorge = %{
      place_id: "gorge",
      name: "The distant gorge",
      visibility: :public,
      description: "A remote gorge beyond the western ridge. " <> noise,
      facts: %{"terrain" => noise}
    }

    objectives =
      Enum.map(1..120, fn index ->
        %{
          objective_id: "objective_#{index}",
          title: "Unrelated task #{index}",
          details: String.duplicate("Routine task detail. ", 70),
          status: "open"
        }
      end)

    relevant_objective = %{
      objective_id: "archive-ledger",
      title: "Inspect the Copper Archive ledger",
      details: "Compare the original harvest ledger with the Finca register.",
      status: "open"
    }

    private_objective = %{
      objective_id: "hidden-archive-route",
      title: "Keep Mira's private route to the Copper Archive concealed",
      details: "Mira knows a concealed service passage behind the archive shelves.",
      status: "open"
    }

    context =
      base_context()
      |> Map.put(:player_action, action)
      |> Map.put(:characters, [player, named_character] ++ scene_cast ++ remote_characters)
      |> Map.put(:places, %{
        public: base_context().places.public ++ [archive, gorge] ++ distant_places,
        gm_private: []
      })
      |> Map.put(:travel_connections, %{
        public: [
          %{place_a_id: "finca", place_b_id: "bodega", travel_minutes: 40},
          %{place_a_id: "bodega", place_b_id: "archive", travel_minutes: 5},
          %{place_a_id: "archive", place_b_id: "gorge", travel_minutes: 30}
        ],
        gm_private: [],
        public_routes: [],
        gm_private_routes: []
      })
      |> Map.put(:objectives, %{
        public: [relevant_objective | objectives],
        gm_private: [private_objective]
      })

    assert request_bytes(context, "Short GM policy") > 64_000

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert metrics.compacted?
    assert compiled.context_completeness.character_details_compacted
    assert compiled.context_completeness.characters_omitted
    assert compiled.context_completeness.places_omitted
    assert compiled.context_completeness.remote_place_details_omitted
    assert compiled.context_completeness.place_details_compacted
    assert compiled.context_completeness.objectives_omitted
    assert compiled.context_completeness.objective_details_omitted

    assert length(compiled.characters) <= 48
    mira = Enum.find(compiled.characters, &(&1.speaker_id == "mira_copper"))
    assert mira.current_place_id == "archive"
    assert mira.voice_guidance.accent == "French"
    assert mira.gm_private_facts["ledger_promise"] =~ "original harvest ledger"

    archive_context = Enum.find(compiled.places.public, &(&1.place_id == "archive"))
    assert archive_context.description =~ "harvest ledger"
    assert archive_context.facts["ledger"] =~ "locked case"

    assert Enum.find(compiled.places.public, &(&1.place_id == "bodega")).description ==
             "The wine cellar."

    gorge_context = Enum.find(compiled.places.public, &(&1.place_id == "gorge"))
    assert is_nil(gorge_context) or not Map.has_key?(gorge_context, :description)
    assert length(compiled.places.public) <= 64

    assert Enum.any?(compiled.objectives.public, &(&1.objective_id == "archive-ledger"))

    assert Enum.find(compiled.objectives.public, &(&1.objective_id == "archive-ledger")).details =~
             "Compare the original"

    assert Enum.any?(compiled.objectives.gm_private, &(&1.objective_id == "hidden-archive-route"))

    assert length(context.characters) == 107
    assert Enum.find(context.characters, &(&1.speaker_id == "mira_copper")) == named_character
    assert length(context.places.public) == 94
    assert Enum.find(context.places.public, &(&1.place_id == "archive")) == archive
    assert length(context.objectives.public) == 121
    assert hd(context.objectives.public) == relevant_objective
  end

  test "fits accepted maximum canon counts with near-cap descriptions and preserves current scene anchors" do
    action =
      "At the Copper Archive, I ask Mira Copper about the original harvest ledger and her promise."

    near_cap_prose =
      "The Copper Archive holds the original harvest ledger beside the eastern window. " <>
        String.duplicate("Shelves hold carefully labeled regional records. ", 220)

    nearby_places = [
      %{
        place_id: "finca",
        name: "Finca",
        visibility: :public,
        description: "The Finca lies forty minutes from the Copper Archive. " <> near_cap_prose,
        facts: %{"travel" => "The trip between the Finca and Archive takes forty minutes."}
      },
      %{
        place_id: "bodega",
        name: "Bodega",
        visibility: :public,
        description: "The Bodega cellar is down the lane. " <> near_cap_prose,
        facts: %{"wine" => "The cellar stores the current harvest."}
      },
      %{
        place_id: "chapel",
        name: "Old Chapel",
        visibility: :public,
        description: "The old chapel stands beyond the archive garden. " <> near_cap_prose,
        facts: %{"bells" => "The chapel bell marks the evening hour."}
      },
      %{
        place_id: "courtyard",
        name: "Archive Courtyard",
        visibility: :public,
        description: "The courtyard is quiet at this hour. " <> near_cap_prose,
        facts: %{"scene" => "Rain beads on the flagstones."}
      }
    ]

    archive = %{
      place_id: "archive",
      name: "Copper Archive",
      visibility: :public,
      description: near_cap_prose,
      facts: %{
        "ledger" =>
          "The original harvest ledger is kept in a locked case. " <>
            String.duplicate("The archivist records each transfer. ", 30)
      }
    }

    remote_places =
      Enum.map(1..59, fn index ->
        %{
          place_id: "remote_#{index}",
          name: "Remote Place #{index}",
          visibility: :public,
          description: near_cap_prose,
          facts: %{"regional_history" => "An unrelated district archive."}
        }
      end)

    base_characters = base_context().characters
    player = hd(base_characters) |> Map.put(:current_place_id, "archive")

    mira = %{
      speaker_id: "mira_copper",
      name: "Mira Copper",
      role: :gm,
      current_place_id: "archive",
      visible_facts: %{
        "ledger" => %{
          "finding" =>
            "Mira's ledger is blue-threaded and records the original harvest. " <>
              String.duplicate("She has catalogued its margins. ", 20)
        },
        "background" => String.duplicate("Unrelated biographical notes. ", 40)
      },
      gm_private_facts: %{
        "ledger_promise" => %{
          "commitment" =>
            "Mira promised the original ledger to Ana before dusk. " <>
              String.duplicate("She has not yet kept that promise. ", 20)
        },
        "background" => String.duplicate("Unrelated private staff notes. ", 40)
      },
      voice_guidance: %{
        accent: "French",
        mannerisms: String.duplicate("Touches the edge of a page before answering. ", 7)
      },
      visible_activity: "Mira has one hand resting on the ledger case."
    }

    scene_cast =
      Enum.map(1..11, fn index ->
        %{
          speaker_id: "archive_witness_#{index}",
          name: "Archive Witness #{index}",
          role: :gm,
          current_place_id: "archive",
          visible_facts: %{
            "background" => String.duplicate("A witness waits quietly. ", 20)
          },
          gm_private_facts: %{
            "background" => String.duplicate("A routine private staff note. ", 20)
          },
          voice_guidance: %{
            cadence: String.duplicate("Measured and restrained. ", 10)
          },
          visible_activity: String.duplicate("Reviews an old catalog card. ", 8)
        }
      end)

    remote_characters =
      Enum.map(1..35, fn index ->
        %{
          speaker_id: "remote_character_#{index}",
          name: "Remote Character #{index}",
          role: :gm,
          current_place_id: "remote_#{index}",
          visible_facts: %{"background" => "An unrelated regional resident."},
          gm_private_facts: %{"background" => "An unrelated private note."}
        }
      end)

    public_objectives =
      Enum.map(1..48, fn index ->
        %{
          objective_id: "public_objective_#{index}",
          title: if(index == 1, do: "Review the harvest ledger", else: "Open task #{index}"),
          details:
            if(index == 1,
              do:
                "Compare the original harvest ledger with the Finca register. " <>
                  String.duplicate("Check the date and recorded transfer. ", 20),
              else: String.duplicate("Routine task detail with no scene relevance. ", 18)
            ),
          status: "open"
        }
      end)

    private_objectives =
      Enum.map(1..48, fn index ->
        %{
          objective_id: "private_objective_#{index}",
          title:
            if(index == 1,
              do: "Mira's private ledger promise",
              else: "Private open task #{index}"
            ),
          details:
            if(index == 1,
              do:
                "Mira promised to bring the original ledger before the evening bell. " <>
                  String.duplicate("She worries the ink will fade. ", 20),
              else: String.duplicate("Routine private task detail. ", 24)
            ),
          status: "open"
        }
      end)

    context =
      base_context()
      |> put_in([:world, :public, :location], "Copper Archive")
      |> Map.put(:player_action, action)
      |> Map.put(:characters, [player, mira] ++ scene_cast ++ remote_characters)
      |> Map.put(:places, %{
        public: [archive | nearby_places] ++ remote_places,
        gm_private: []
      })
      |> Map.put(:travel_connections, %{
        public: [
          %{place_a_id: "archive", place_b_id: "finca", travel_minutes: 40},
          %{place_a_id: "archive", place_b_id: "bodega", travel_minutes: 18},
          %{place_a_id: "archive", place_b_id: "chapel", travel_minutes: 6},
          %{place_a_id: "archive", place_b_id: "courtyard", travel_minutes: 1}
        ],
        gm_private: [],
        public_routes: [],
        gm_private_routes: []
      })
      |> Map.put(:objectives, %{public: public_objectives, gm_private: private_objectives})

    policy = "Short GM policy"
    assert length(context.characters) == 48
    assert length(context.places.public) == 64
    assert length(context.objectives.public) == 48
    assert length(context.objectives.gm_private) == 48
    assert String.length(archive.description) > 10_000
    assert request_bytes(context, policy) > 64_000

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, policy, "gpt-6-astra")

    assert metrics.budget_bytes == 64_000
    assert metrics.estimated_request_bytes <= 64_000
    assert metrics.compacted?
    assert :place_details in metrics.omissions
    assert :character_details in metrics.omissions
    assert compiled.context_completeness.place_details_compacted
    assert compiled.context_completeness.character_details_compacted
    assert length(compiled.characters) == 48
    assert length(compiled.places.public) == 64
    assert length(compiled.objectives.public) == 48
    assert length(compiled.objectives.gm_private) == 48

    compiled_mira = Enum.find(compiled.characters, &(&1.speaker_id == "mira_copper"))
    assert Map.get(compiled_mira, :current_place_id) == "archive"

    visible_facts =
      Map.get(compiled_mira, :visible_facts) || Map.get(compiled_mira, "visible_facts")

    private_facts =
      Map.get(compiled_mira, :gm_private_facts) || Map.get(compiled_mira, "gm_private_facts")

    voice_guidance =
      Map.get(compiled_mira, :voice_guidance) || Map.get(compiled_mira, "voice_guidance")

    assert visible_facts["ledger"]["finding"] =~
             "Mira's ledger is blue-threaded"

    assert String.ends_with?(visible_facts["ledger"]["finding"], "…")

    assert private_facts["ledger_promise"]["commitment"] =~
             "Mira promised the original ledger"

    assert String.ends_with?(private_facts["ledger_promise"]["commitment"], "…")
    assert Map.get(voice_guidance, :accent) == "French"

    compiled_archive = Enum.find(compiled.places.public, &(&1.place_id == "archive"))
    assert compiled_archive.description =~ "original harvest ledger"
    assert compiled_archive.description =~ "context excerpt; older text omitted"
    assert compiled_archive.facts["ledger"] =~ "locked case"

    assert Enum.find(compiled.places.public, &(&1.place_id == "finca")).description =~
             "forty minutes"

    assert Enum.find(compiled.objectives.public, &(&1.objective_id == "public_objective_1")).details =~
             "Compare the original harvest ledger"

    assert Enum.find(compiled.objectives.gm_private, &(&1.objective_id == "private_objective_1")).details =~
             "Mira promised to bring the original ledger"

    assert compiled.world.public.location == "Copper Archive"
    assert compiled.world.public.date == "1567-04-12"

    assert Enum.any?(compiled.travel_connections.public, fn edge ->
             edge.place_a_id == "archive" and edge.place_b_id == "finca" and
               edge.travel_minutes == 40
           end)

    source_mira = Enum.find(context.characters, &(&1.speaker_id == "mira_copper"))
    assert source_mira == mira
    assert source_mira.visible_facts == mira.visible_facts
    assert source_mira.gm_private_facts == mira.gm_private_facts

    assert String.length(
             Enum.find(context.places.public, &(&1.place_id == "archive")).description
           ) >
             10_000
  end

  test "broad questions retrieve a small bounded set of scene anchors in each supported language" do
    history =
      Enum.map(1..40, fn sequence ->
        {event_type, speaker_id, text} =
          case sequence do
            5 ->
              {:gm_narration, nil,
               "At the Bodega, the reserve wine is held for a private autumn tasting."}

            17 ->
              {:npc_dialogue, "marisol", "I promised to set the reserve aside for you."}

            _ ->
              {:gm_narration, nil,
               "Unrelated regional accounting summary #{sequence}. " <>
                 String.duplicate("No vineyard details. ", 45)}
          end

        %{
          "sequence" => sequence,
          "session_id" => div(sequence - 1, 20) + 1,
          "event_type" => Atom.to_string(event_type),
          "visibility" => "public",
          "speaker_id" => speaker_id,
          "payload" => %{"text" => text}
        }
      end)

    actions = [
      "I ask what needs doing before we close for the evening.",
      "¿Qué hace falta antes de cerrar por la noche?",
      "Qu'est-ce qu'il faut faire avant de fermer pour la soirée ?"
    ]

    for action <- actions do
      context =
        base_context()
        |> Map.put(:player_action, action)
        |> Map.put(:history, history)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

      assert metrics.compacted?
      assert metrics.estimated_request_bytes <= 64_000
      assert length(compiled.history) <= 20
      assert Enum.any?(compiled.history, &(&1["sequence"] == 5))
      assert Enum.any?(compiled.history, &(&1["sequence"] == 17))
      refute Enum.any?(compiled.history, &(&1["sequence"] == 10))
    end
  end

  test "keeps a long campaign request near the short-campaign baseline" do
    instructions = production_gm_policy()
    budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]

    base =
      base_context()
      |> Map.put(
        :player_action,
        "At the Bodega, I ask whether Marisol can help with cellar pressing before harvest work is done."
      )
      |> update_in([:characters], fn characters ->
        Enum.map(characters, fn character ->
          if character.speaker_id == "tomas" do
            Map.put(character, :active_duty, %{
              name: "Oversee the cellar pressing",
              place_id: "bodega",
              place_name: "Bodega"
            })
          else
            character
          end
        end)
      end)

    short_context = Map.put(base, :history, synthetic_history(12))
    long_context = Map.put(base, :history, synthetic_history(240))
    assert short_context.player_action == long_context.player_action

    assert {:ok, %{context: short_compiled, metrics: short_metrics}} =
             ContextBudget.compile(short_context, instructions, "gpt-6-astra",
               context_input_byte_budget: budget
             )

    assert short_metrics.compacted?
    assert :remote_character_profiles in short_metrics.omissions
    assert short_metrics.estimated_request_bytes <= budget
    assert short_compiled.world == short_context.world
    assert short_compiled.player_action == short_context.player_action

    short_characters = Map.new(short_compiled.characters, &{&1.speaker_id, &1})
    assert short_characters["tomas"].current_place_id == "bodega"
    assert short_characters["tomas"].active_duty.name == "Oversee the cellar pressing"
    refute Map.has_key?(short_characters["tomas"], :visible_facts)

    assert {:ok, %{context: long_compiled, metrics: long_metrics}} =
             ContextBudget.compile(long_context, instructions, "gpt-6-astra",
               context_input_byte_budget: budget
             )

    assert long_metrics.compacted?
    assert long_metrics.estimated_request_bytes <= budget
    assert long_compiled.context_completeness.history_compacted

    full_history_request_bytes = request_bytes(long_context, instructions)
    bounded_history_request_bytes = long_metrics.estimated_request_bytes
    short_request_bytes = short_metrics.estimated_request_bytes

    assert full_history_request_bytes >= bounded_history_request_bytes * 5
    assert bounded_history_request_bytes <= short_request_bytes + 2_000

    recent_sequences =
      long_context.history
      |> Enum.take(-12)
      |> MapSet.new(& &1["sequence"])

    expected_relevant_sequences = MapSet.new([5, 73, 157])
    hard_decoy_candidates = MapSet.new([193, 199, 211, 217, 223, 225, 227])

    older_candidates =
      long_context.history
      |> Enum.reject(&MapSet.member?(recent_sequences, &1["sequence"]))
      |> MapSet.new(& &1["sequence"])

    retrieved_older_sequences =
      long_compiled.history
      |> Enum.reject(&MapSet.member?(recent_sequences, &1["sequence"]))
      |> MapSet.new(& &1["sequence"])

    true_positives = MapSet.intersection(retrieved_older_sequences, expected_relevant_sequences)
    false_inclusions = MapSet.difference(retrieved_older_sequences, expected_relevant_sequences)
    expected_decoys = MapSet.difference(older_candidates, expected_relevant_sequences)

    precision = MapSet.size(true_positives) / max(MapSet.size(retrieved_older_sequences), 1)
    recall = MapSet.size(true_positives) / MapSet.size(expected_relevant_sequences)

    assert MapSet.size(expected_decoys) >= 200
    assert Enum.all?(expected_relevant_sequences, &MapSet.member?(older_candidates, &1))
    assert MapSet.intersection(hard_decoy_candidates, older_candidates) == hard_decoy_candidates
    assert MapSet.size(true_positives) == MapSet.size(expected_relevant_sequences)
    assert false_inclusions == MapSet.new()
    assert MapSet.intersection(retrieved_older_sequences, hard_decoy_candidates) == MapSet.new()
    assert precision == 1.0
    assert recall == 1.0
    assert Enum.any?(long_compiled.history, &(&1["sequence"] == 240))
    assert long_compiled.world == long_context.world
    assert long_compiled.inventory == long_context.inventory
    assert long_compiled.travel_connections == long_context.travel_connections

    canonical_character_locations = fn context ->
      Map.new(context.characters, fn character ->
        {character.speaker_id, {character.current_place_id, Map.get(character, :active_duty)}}
      end)
    end

    assert canonical_character_locations.(long_compiled) ==
             canonical_character_locations.(long_context)

    public_place_identity = fn context ->
      Map.new(context.places.public, fn place ->
        {place.place_id, Map.take(place, [:place_id, :name, :visibility])}
      end)
    end

    assert public_place_identity.(long_compiled) == public_place_identity.(long_context)
  end

  test "shortens recent narration in stages when the canonical request slightly exceeds its budget" do
    instructions =
      production_gm_policy() <> String.duplicate("Additional required GM policy. ", 160)

    budget = 32_000

    history =
      Enum.map(1..12, fn sequence ->
        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{
            "text" =>
              "Scene detail #{sequence}. " <>
                String.duplicate("A barrel rests by the cellar door. ", 48)
          }
        }
      end)

    context = Map.put(base_context(), :history, history)
    assert request_bytes(context, instructions) > budget

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, instructions, "gpt-6-astra",
               context_input_byte_budget: budget
             )

    assert metrics.compacted?
    assert :history in metrics.omissions
    assert metrics.estimated_request_bytes <= budget
    assert compacted.context_completeness.history_compacted
    assert Enum.map(compacted.history, & &1["sequence"]) == Enum.to_list(1..12)

    older_texts = compacted.history |> Enum.take(8) |> Enum.map(& &1["payload"]["text"])
    newest_texts = compacted.history |> Enum.take(-4) |> Enum.map(& &1["payload"]["text"])

    assert Enum.all?(older_texts, &(String.length(&1) <= 600))
    assert Enum.all?(newest_texts, &(String.length(&1) > 600 and String.length(&1) <= 1_600))

    assert compacted.world == context.world
    assert compacted.inventory == context.inventory
    assert compacted.travel_connections == context.travel_connections

    assert compacted.places.public |> Enum.map(& &1.place_id) ==
             context.places.public |> Enum.map(& &1.place_id)

    assert Enum.find(compacted.characters, &(&1.speaker_id == "marisol")).gm_private_facts ==
             Enum.find(context.characters, &(&1.speaker_id == "marisol")).gm_private_facts
  end

  test "omits oversized historical narration before rejecting a retry, preserving scene facts and NPC voices" do
    marisol_voice = %{
      "accent_dialect" => "French accent with Lyonnais vowels.",
      "cadence" => "Short phrases, then a pause before a confession."
    }

    iria_voice = %{
      "quirks" => "Repeats the last word as a quiet question.",
      "vocabulary" => "Favors weather and gardening metaphors."
    }

    characters =
      base_context().characters
      |> Enum.map(fn character ->
        if character.speaker_id == "marisol",
          do: Map.put(character, :voice_guidance, marisol_voice),
          else: character
      end)
      |> Kernel.++([
        %{
          speaker_id: "iria",
          name: "Iria",
          role: :gm,
          current_place_id: "finca",
          current_place: %{place_id: "finca", name: "Finca", visibility: :public},
          visible_facts: %{},
          gm_private_facts: %{},
          voice_guidance: iria_voice
        }
      ])

    history =
      Enum.map(1..60, fn sequence ->
        %{
          "sequence" => sequence,
          "session_id" => div(sequence - 1, 6) + 1,
          "event_type" => "npc_dialogue",
          "visibility" => "public",
          "speaker_id" => if(rem(sequence, 2) == 0, do: "marisol", else: "iria"),
          "payload" => %{
            "text" =>
              "At the Finca, Marisol and Iria discuss the Bodega harvest report. " <>
                String.duplicate("Archived fictional history. ", 90)
          }
        }
      end)

    context =
      base_context()
      |> Map.put(:campaign, %{
        title: "The Amber Orchard",
        premise: "A quiet vineyard mystery",
        setup_notes: "The cellar smells of rain and cedar."
      })
      |> Map.put(:memory, %{
        public_summary: "Marisol and Iria shared the last harvest at the Finca.",
        gm_private_summary: ""
      })
      |> Map.put(:continuity, %{
        public: [
          %{
            entry_id: "marisol-harvest-promise",
            kind: "commitment",
            title: "Marisol's Bodega harvest promise",
            details: "Marisol promised to reserve the first harvest cask at the Bodega.",
            status: "active",
            visibility: "public"
          }
        ],
        gm_private: []
      })
      |> Map.put(:player_action, "I ask Marisol and Iria what they heard at the Bodega.")
      |> Map.put(:characters, characters)
      |> Map.put(:history, history)

    budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]
    no_history_context = Map.put(context, :history, [])

    # Put the request near, but still below, the same configured local limit
    # without a transcript. The long history then exhausts the remaining room.
    instruction_bytes = budget - request_bytes(no_history_context, "") - 1_024

    assert instruction_bytes > 0
    instructions = String.duplicate("p", instruction_bytes)

    assert request_bytes(no_history_context, instructions) < budget

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, instructions, "gpt-6-astra",
               context_input_byte_budget: budget
             )

    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= budget
    assert metrics.budget_bytes == budget
    assert compacted.history == []
    assert compacted.context_completeness.history_compacted
    assert compacted.context_completeness.history_omitted
    assert :history in metrics.omissions

    assert compacted.campaign == context.campaign
    assert compacted.player_action == context.player_action
    assert compacted.world == context.world
    assert compacted.memory.public_summary == context.memory.public_summary
    assert compacted.continuity.public == context.continuity.public

    assert compacted.characters
           |> Enum.find(&(&1.speaker_id == "marisol"))
           |> Map.take([:name, :current_place_id, :voice_guidance]) ==
             %{name: "Marisol", current_place_id: "finca", voice_guidance: marisol_voice}

    assert compacted.characters
           |> Enum.find(&(&1.speaker_id == "iria"))
           |> Map.take([:name, :current_place_id, :voice_guidance]) ==
             %{name: "Iria", current_place_id: "finca", voice_guidance: iria_voice}

    assert context.history == history
    assert context.campaign.setup_notes == "The cellar smells of rain and cedar."
  end

  test "keeps relevant active continuity details while compacting unrelated history" do
    context = base_context()

    continuity_entries =
      [
        %{
          entry_id: "closed-old",
          kind: "fact",
          title: "Closed legacy",
          details: String.duplicate("dormant relic custodian ", 12),
          status: "completed",
          visibility: "public"
        }
      ] ++
        Enum.map(1..13, fn number ->
          %{
            entry_id: "active-#{number}",
            kind: if(number == 1, do: "commitment", else: "fact"),
            title:
              if(number == 1,
                do: "Marisol's Bodega harvest agreement",
                else: "Active canon #{number}"
              ),
            details:
              if(number == 1,
                do: "Marisol promised to reserve harvest wine at the Bodega.",
                else:
                  "Unmentioned durable canon #{number}: " <>
                    String.duplicate("keepsake stewardship ", 12)
              ),
            status: "active",
            visibility: "public"
          }
        end)

    history =
      Enum.map(1..40, fn sequence ->
        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{"text" => String.duplicate("Harbor ships arrive today. ", 45)}
        }
      end)

    context =
      context
      |> Map.put(:continuity, %{public: continuity_entries, gm_private: []})
      |> Map.put(:history, history)

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra",
               context_input_byte_budget: 24_000
             )

    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= 24_000

    compacted_entries = compacted.continuity.public

    assert Enum.find(compacted_entries, &(&1.entry_id == "active-1")) ==
             Enum.find(continuity_entries, &(&1.entry_id == "active-1"))

    unrelated_active =
      Enum.filter(compacted_entries, &(&1.status == "active" and &1.entry_id != "active-1"))

    assert length(unrelated_active) == 12

    assert Enum.all?(unrelated_active, fn entry ->
             entry.status == "active" and not Map.has_key?(entry, :details) and
               not Map.has_key?(entry, :title)
           end)

    refute Map.has_key?(Enum.find(compacted_entries, &(&1.entry_id == "closed-old")), :details)
    assert compacted.context_completeness.continuity_memory_details_omitted
    assert :continuity_memory_details in metrics.omissions
    assert compacted.world == context.world
    assert compacted.inventory == context.inventory
    assert compacted.travel_connections == context.travel_connections
  end

  test "retains a remote GM character's active duty while compacting unrelated character details" do
    context = base_context()

    characters =
      Enum.map(context.characters, fn character ->
        if character.speaker_id == "tomas" do
          Map.put(character, :active_duty, %{
            name: "Keep the river bodega vats under observation",
            place_id: "bodega",
            place_name: "Bodega"
          })
        else
          character
        end
      end)

    history =
      Enum.map(1..50, fn sequence ->
        text =
          if sequence == 5 do
            "A bodega forty minutes from the Finca; Marisol stayed at the Finca. " <>
              String.duplicate("specific older note ", 70)
          else
            "Unrelated market report #{sequence}. " <> String.duplicate("unrelated detail ", 70)
          end

        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{"text" => text}
        }
      end)

    context = context |> Map.put(:characters, characters) |> Map.put(:history, history)

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra",
               context_input_byte_budget: 20_000
             )

    assert metrics.compacted?
    tomas = Enum.find(compacted.characters, &(&1.speaker_id == "tomas"))
    assert tomas.active_duty == Enum.find(characters, &(&1.speaker_id == "tomas")).active_duty
    refute Map.has_key?(tomas, :gm_private_facts)
  end

  test "keeps each present NPC's distinct voice guidance when compacting the GM context" do
    context = base_context()

    marisol_voice = %{
      "quirks" => "Answers with a dry joke when nervous.",
      "accent_dialect" => "French accent, with Lyonnais vowels.",
      "cadence" => "Short phrases, then a pause before a confession.",
      "vocabulary" => "Uses kitchen and cellar terms.",
      "mannerisms" => "Taps the spoon against her apron when thinking."
    }

    keeper_voice = %{
      "quirks" => "Repeats the last word as a quiet question.",
      "accent_dialect" => "Soft coastal Spanish lilt.",
      "cadence" => "Slow, careful sentences.",
      "vocabulary" => "Favors weather and gardening metaphors.",
      "mannerisms" => "Looks toward the vines before answering."
    }

    remote_voice = %{"cadence" => "Speaks in clipped, formal sentences."}

    characters =
      Enum.map(context.characters, fn character ->
        case character.speaker_id do
          "marisol" -> Map.put(character, :voice_guidance, marisol_voice)
          "tomas" -> Map.put(character, :voice_guidance, remote_voice)
          _ -> character
        end
      end) ++
        [
          %{
            speaker_id: "keeper",
            name: "Iria",
            role: :gm,
            current_place_id: "finca",
            current_place: %{place_id: "finca", name: "Finca", visibility: :public},
            visible_facts: %{},
            gm_private_facts: %{},
            voice_guidance: keeper_voice
          }
        ]

    history =
      Enum.map(1..50, fn sequence ->
        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{
            "text" => "Unrelated ledger detail #{sequence}. " <> String.duplicate("record ", 70)
          }
        }
      end)

    context = context |> Map.put(:characters, characters) |> Map.put(:history, history)

    policy = production_gm_policy()

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, policy, "gpt-6-astra",
               context_input_byte_budget: 24_000
             )

    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= 24_000

    policy = String.replace(policy, ~r/\s+/, " ")
    assert policy =~ "OBSERVATION/JUDGMENT: GM owns external facts."

    assert policy =~
             "Wine, food, or drink tastings: describe appearance, aroma, palate (fruit, acidity, tannin, body/sweetness as relevant), and finish before inviting reaction."

    assert policy =~
             "A present NPC expert may offer a qualified, evidence-based view;"

    assert policy =~
             "never dictate the player's response."

    assert policy =~ "Never ask players to define sensory facts."

    assert policy =~ "Preserve each NPC's knowledge, motives, work, and distinct voice."

    assert policy =~
             "Use each speaker's profile for distinct word choice and rhythm;"

    assert policy =~
             "accents naturally in the campaign language, never phonetically."

    assert policy =~
             "Keep quirks selective and mannerisms brief; avoid catchphrases, caricature, and forced cues."

    assert policy =~ "Never blend voices."

    assert policy =~
             "Create exactly {type:\"create\",entry:{entry_id,kind, title,details,visibility},reason}"

    assert policy =~
             "Persist lasting evidence as public continuity; don't guess causes or transient impressions."

    compacted_characters = Map.new(compacted.characters, &{&1.speaker_id, &1})

    assert {compacted_characters["marisol"].name, compacted_characters["marisol"].voice_guidance} ==
             {"Marisol", marisol_voice}

    assert {compacted_characters["keeper"].name, compacted_characters["keeper"].voice_guidance} ==
             {"Iria", keeper_voice}

    refute compacted_characters["marisol"].voice_guidance == keeper_voice
    refute compacted_characters["keeper"].voice_guidance == marisol_voice
    refute Map.has_key?(compacted_characters["tomas"], :voice_guidance)
  end

  test "retrieves relevant player memories without resending unrelated details under budget" do
    context = base_context()

    player_memories =
      Enum.map(1..8, fn number ->
        %{
          entry_id: "player-memory-#{number}",
          kind: "commitment",
          title:
            if(number == 1,
              do: "Bodega harvest agreement",
              else: "Player memory #{number}"
            ),
          details:
            if(number == 1,
              do: "Marisol checks the harvest at the Bodega before dawn.",
              else: String.pad_trailing("Unrelated public promise #{number}.", 300, " ")
            ),
          status: "active",
          visibility: "public",
          source_sequence: nil,
          player_managed: true
        }
      end)

    context =
      context
      |> Map.put(:continuity, %{public: player_memories, gm_private: []})

    default_budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]
    assert default_budget == 64_000
    assert byte_size(Jason.encode!(context)) + byte_size("Short GM policy") + 512 < default_budget

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= default_budget
    assert metrics.compacted?
    assert :continuity_memory_details in metrics.omissions
    assert :remote_character_profiles in metrics.omissions

    [relevant | unrelated] = compiled.continuity.public
    assert relevant.details == hd(player_memories).details

    assert Enum.all?(unrelated, fn entry ->
             Enum.all?([:title, :details], &(not Map.has_key?(entry, &1)))
           end)

    assert Enum.map(compiled.continuity.public, & &1.entry_id) ==
             Enum.map(player_memories, & &1.entry_id)

    assert compiled.context_completeness.continuity_memory_details_omitted
    refute Map.get(compiled.context_completeness, :history_compacted, false)

    assert metrics.context_json_bytes < byte_size(Jason.encode!(context))
  end

  test "generic promise questions retrieve bounded typed public commitments in all locales" do
    commitments =
      Enum.map(1..10, fn number ->
        %{
          entry_id: "typed-commitment-#{number}",
          kind: "commitment",
          title: "Arrangement #{number}",
          details:
            "Marisol will inspect fermentation barrels #{number} before the first frost. " <>
              String.duplicate("The cellar plan remains part of the campaign. ", 4),
          status: "active",
          visibility: "public",
          player_managed: false
        }
      end)

    non_commitment_decoy = %{
      entry_id: "promise-word-fact",
      kind: "fact",
      title: "An old weather saying",
      details: "The village proverb promised the east wind would calm before sunrise.",
      status: "active",
      visibility: "public",
      player_managed: false
    }

    context =
      base_context()
      |> Map.put(:continuity, %{public: [non_commitment_decoy | commitments], gm_private: []})

    for action <- [
          "What did we agree to?",
          "¿Qué acordamos?",
          "Qu'avons-nous convenu ?"
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000

      assert metrics.section_bytes.section_continuity_bytes <
               byte_size(Jason.encode!(context.continuity))

      detailed_ids =
        compiled.continuity.public
        |> Enum.filter(&Map.has_key?(&1, :details))
        |> Enum.map(& &1.entry_id)

      assert detailed_ids == Enum.map(3..10, &"typed-commitment-#{&1}")

      assert Enum.map(compiled.continuity.public, & &1.entry_id) ==
               Enum.map([non_commitment_decoy | commitments], & &1.entry_id)

      assert compiled.context_completeness.continuity_memory_details_omitted
      assert :continuity_memory_details in metrics.omissions

      refute Enum.any?(compiled.continuity.public, fn entry ->
               entry.entry_id == "promise-word-fact" and Map.has_key?(entry, :details)
             end)
    end
  end

  test "plan paraphrases retrieve bounded active commitments across supported locales" do
    commitments =
      Enum.map(1..10, fn number ->
        %{
          entry_id: "observatory-plan-#{number}",
          kind: "commitment",
          title: "Observatory duty #{number}",
          details: "Mira will check the eastern lens before the first frost, duty #{number}.",
          status: "active",
          visibility: "public",
          player_managed: false
        }
      end)

    completed_commitment = %{
      entry_id: "completed-observatory-duty",
      kind: "commitment",
      title: "Completed observatory duty",
      details: "The keeper already repaired the western shutter last week.",
      status: "completed",
      visibility: "public",
      player_managed: false
    }

    ordinary_fact = %{
      entry_id: "tower-plan-fact",
      kind: "fact",
      title: "The tower plan",
      details: "A plan of the old tower hangs beside the entrance.",
      status: "active",
      visibility: "public",
      player_managed: false
    }

    continuity = %{
      public: commitments ++ [completed_commitment, ordinary_fact],
      gm_private: []
    }

    context = Map.put(base_context(), :continuity, continuity)

    for action <- [
          "What was our plan?",
          "What were we intending to do?",
          "¿Qué teníamos previsto hacer?",
          "Qu'avions-nous prévu de faire ?"
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000
      assert metrics.section_bytes.section_continuity_bytes < byte_size(Jason.encode!(continuity))
      assert metrics.context_json_bytes < byte_size(Jason.encode!(request_context))

      detailed_ids =
        compiled.continuity.public
        |> Enum.filter(&Map.has_key?(&1, :details))
        |> Enum.map(& &1.entry_id)

      assert detailed_ids == Enum.map(3..10, &"observatory-plan-#{&1}")

      for entry_id <- [completed_commitment.entry_id, ordinary_fact.entry_id] do
        entry = Enum.find(compiled.continuity.public, &(&1.entry_id == entry_id))
        refute Map.has_key?(entry, :title)
        refute Map.has_key?(entry, :details)
      end

      assert compiled.context_completeness.continuity_memory_details_omitted
      assert :continuity_memory_details in metrics.omissions
    end
  end

  test "remaining-work retrieval requires both a remaining cue and an action cue" do
    commitment = %{
      entry_id: "lens-inspection",
      kind: "commitment",
      title: "Inspect the eastern lens",
      details: "The eastern lens will be inspected before the first frost.",
      status: "active",
      visibility: "public",
      player_managed: false
    }

    context =
      base_context()
      |> Map.put(:continuity, %{public: [commitment], gm_private: []})

    for {action, expected_detail?} <- [
          {"What remains for us?", false},
          {"What wine remains in the cellar?", false},
          {"¿Qué nos queda?", false},
          {"Qu’est-ce qu’il nous reste ?", false},
          {"What remains for us to do?", true},
          {"¿Qué nos queda por hacer?", true},
          {"Qu’est-ce qu’il nous reste à faire ?", true}
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      entry = hd(compiled.continuity.public)
      assert Map.has_key?(entry, :details) == expected_detail?
    end
  end

  test "retrieves typed meeting and reply commitments from bounded multilingual cues" do
    meeting = %{
      entry_id: "future-meeting",
      kind: "commitment",
      title: "Nella's North Gate Promise",
      details: "Nella will meet the archivist at the north gate after the comet returns.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    reply = %{
      entry_id: "future-reply",
      kind: "commitment",
      title: "Mira's Charter Promise",
      details: "Mira promised to send a reply about the charter after the comet returns.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    meeting_fact_decoy = %{
      entry_id: "appointment-fact",
      kind: "fact",
      title: "The Cartographer's Appointment",
      details: "The miller expects an appointment with the cartographer after the first frost.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    reply_fact_decoy = %{
      entry_id: "answer-fact",
      kind: "fact",
      title: "The Magistrate's Answer",
      details: "The magistrate's answer about the river tax arrived at dawn.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    unrelated_commitment = %{
      entry_id: "key-promise",
      kind: "commitment",
      title: "The Keeper's Key Promise",
      details: "The keeper promised to return the silver key before dawn.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    entries = [meeting, reply, meeting_fact_decoy, reply_fact_decoy, unrelated_commitment]

    context =
      base_context()
      |> Map.put(:continuity, %{public: entries, gm_private: []})

    for {action, expected_entry_id} <- [
          {"When is our appointment?", meeting.entry_id},
          {"¿Cuándo quedamos para vernos?", meeting.entry_id},
          {"Où devions-nous retrouver quelqu'un ?", meeting.entry_id},
          {"Où se rencontrent-ils demain ?", meeting.entry_id},
          {"Où se retrouvent-ils demain ?", meeting.entry_id},
          {"Did she answer us yet?", reply.entry_id},
          {"¿Ya nos contestó?", reply.entry_id},
          {"A-t-elle répondu ?", reply.entry_id}
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000

      detailed_ids =
        compiled.continuity.public
        |> Enum.filter(&Map.has_key?(&1, :details))
        |> Enum.map(& &1.entry_id)

      assert detailed_ids == [expected_entry_id]
      assert compiled.context_completeness.continuity_memory_details_omitted
      assert :continuity_memory_details in metrics.omissions
    end
  end

  test "cross-language concealed-key recall requires both the key and concealment cues" do
    concealed_key = %{
      entry_id: "french-concealed-key",
      kind: "fact",
      title: "La clef de cuivre",
      details: "La clef de cuivre a été cachée sous la pierre de la crypte.",
      status: "active",
      visibility: "public",
      source_sequence: 14,
      player_managed: false
    }

    key_only = %{
      entry_id: "french-copper-key",
      kind: "fact",
      title: "La clef de cuivre",
      details: "La clef de cuivre ouvre la porte nord.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    hidden_object_only = %{
      entry_id: "french-hidden-seal",
      kind: "fact",
      title: "Le sceau caché",
      details: "Le sceau de cire a été caché sous la table du conseil.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    context =
      base_context()
      |> Map.put(:continuity, %{
        public: [concealed_key, key_only, hidden_object_only],
        gm_private: []
      })

    for action <- [
          "Where did we hide the copper key?",
          "¿Dónde escondieron la llave de cobre?",
          "Où avons-nous caché la clef de cuivre ?"
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000

      entries = Map.new(compiled.continuity.public, &{&1.entry_id, &1})
      assert entries["french-concealed-key"].details == concealed_key.details
      assert entries["french-concealed-key"].source_sequence == 14

      for entry_id <- ["french-copper-key", "french-hidden-seal"] do
        refute Map.has_key?(entries[entry_id], :title)
        refute Map.has_key?(entries[entry_id], :details)
      end
    end

    for action <- ["What is the copper key?", "What was hidden under the table?"] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000
      entry = Enum.find(compiled.continuity.public, &(&1.entry_id == concealed_key.entry_id))
      refute Map.has_key?(entry, :title)
      refute Map.has_key?(entry, :details)
    end
  end

  test "retrieves a durable wine memory when the player asks in Spanish or French" do
    player_memory = %{
      entry_id: "wine-reserve",
      kind: "fact",
      title: "Wine reserve for autumn",
      details: "Keep six bottles aside for the autumn tasting.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    unrelated_memory = %{
      entry_id: "bridge-toll",
      kind: "fact",
      title: "Bridge toll agreement",
      details: "The town bridge toll is waived until summer.",
      status: "active",
      visibility: "public",
      player_managed: true
    }

    context =
      base_context()
      |> Map.put(:continuity, %{public: [player_memory, unrelated_memory], gm_private: []})

    for action <- ["¿Cuántos vinos quedan en reserva?", "Combien de vins restent en réserve ?"] do
      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(
                 %{context | player_action: action},
                 "Short GM policy",
                 "gpt-6-astra"
               )

      assert metrics.estimated_request_bytes <= 64_000

      assert Enum.find(compiled.continuity.public, &(&1.entry_id == "wine-reserve")).details ==
               player_memory.details

      unrelated = Enum.find(compiled.continuity.public, &(&1.entry_id == "bridge-toll"))
      refute Map.has_key?(unrelated, :title)
      refute Map.has_key?(unrelated, :details)
    end
  end

  test "retrieves an older employment promise from Spanish and French paraphrases" do
    employment_memory = %{
      entry_id: "apothecary-offer",
      kind: "commitment",
      title: "Rosa's apothecary offer",
      details:
        "Before accepting the job at the apothecary, Rosa promised to ask the employer about wages, working hours, and terms.",
      status: "active",
      visibility: "public",
      source_sequence: 4,
      player_managed: true
    }

    unrelated_memories = [
      %{
        entry_id: "stone-bridge-repair",
        kind: "fact",
        title: "Stone bridge repair",
        details:
          "The mason repaired the old stone bridge after the spring flood. " <>
            "Its opening hours are posted by the gate, and bridge tolls are paid at dawn. " <>
            String.duplicate(
              "Repair notes describe the damaged arch and replacement stones. ",
              20
            ),
        status: "active",
        visibility: "public",
        player_managed: true
      },
      %{
        entry_id: "wheat-harvest-plan",
        kind: "plan",
        title: "Wheat harvest plan",
        details:
          "The fields are scheduled for the late summer harvest. " <>
            String.duplicate("The plan records the cutting order and storage needs. ", 20),
        status: "active",
        visibility: "public",
        player_managed: true
      }
    ]

    memories = [employment_memory | unrelated_memories]

    context =
      base_context()
      |> Map.put(:campaign, %{
        title: "Northgate",
        premise: "A small town with shared work and obligations."
      })
      |> Map.put(:continuity, %{public: memories, gm_private: []})

    for action <- [
          "Antes de aceptar el trabajo, ¿qué debo aclarar sobre la oferta?",
          "Avant d'accepter le poste, quels points dois-je clarifier ?",
          "What hours were part of that position?",
          "¿Qué horario tenía ese puesto?",
          "Quels horaires étaient prévus pour le poste ?",
          "What did I promise about the position?",
          "¿Qué había prometido sobre ese puesto?",
          "Qu'avais-je promis au sujet du poste ?",
          "What does the employer pay?",
          "¿Cuánto paga el empleador?",
          "Combien l'employeur paie-t-il ?"
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000

      assert metrics.section_bytes.section_continuity_bytes <
               byte_size(Jason.encode!(context.continuity))

      assert metrics.context_json_bytes < byte_size(Jason.encode!(request_context))

      [retrieved | unrelated] = compiled.continuity.public
      assert retrieved.entry_id == employment_memory.entry_id
      assert retrieved.details == employment_memory.details

      assert Enum.map(unrelated, & &1.entry_id) == Enum.map(unrelated_memories, & &1.entry_id)

      assert Enum.all?(unrelated, fn entry ->
               not Map.has_key?(entry, :title) and not Map.has_key?(entry, :details)
             end)

      assert compiled.context_completeness.continuity_memory_details_omitted
    end

    for action <- [
          "Should I accept it?",
          "Where is the employer?",
          "What are the bridge opening hours?",
          "¿A qué hora abre el puente?",
          "Quels sont les horaires d'ouverture du pont ?",
          "Who pays the bridge toll?",
          "¿Quién paga el peaje del puente?",
          "Qui paie le péage du pont ?"
        ] do
      request_context = Map.put(context, :player_action, action)

      assert {:ok, %{context: compiled, metrics: metrics}} =
               ContextBudget.compile(request_context, "Short GM policy", "gpt-6-astra",
                 context_input_byte_budget: 24_000
               )

      assert metrics.estimated_request_bytes <= 24_000

      employment =
        Enum.find(compiled.continuity.public, &(&1.entry_id == employment_memory.entry_id))

      refute Map.has_key?(employment, :details)

      if action in ["What are the bridge opening hours?", "Who pays the bridge toll?"] do
        bridge = Enum.find(compiled.continuity.public, &(&1.entry_id == "stone-bridge-repair"))
        assert bridge.details =~ "opening hours"
      end
    end

    toll_context = Map.put(context, :player_action, "I paid the bridge toll.")

    assert {:ok, %{context: toll_compiled}} =
             ContextBudget.compile(toll_context, "Short GM policy", "gpt-6-astra",
               context_input_byte_budget: 24_000
             )

    toll_details =
      Map.new(toll_compiled.continuity.public, &{&1.entry_id, Map.has_key?(&1, :details)})

    assert toll_details["stone-bridge-repair"]
    refute toll_details["apothecary-offer"]
    refute toll_details["wheat-harvest-plan"]
  end

  test "bounds broad seasonal event retrieval to the newest eight matching notes" do
    player_memories =
      Enum.map(1..10, fn number ->
        %{
          entry_id: "autumn-event-#{number}",
          kind: "fact",
          title: "Autumn event #{number}",
          details: "The town autumn event #{number} takes place in the square.",
          status: "active",
          visibility: "public",
          player_managed: true
        }
      end)

    context =
      base_context()
      |> Map.put(:player_action, "Tell me about the fall event.")
      |> Map.put(:continuity, %{public: player_memories, gm_private: []})

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= 64_000

    detailed_entry_ids =
      compiled.continuity.public
      |> Enum.filter(&Map.has_key?(&1, :details))
      |> Enum.map(& &1.entry_id)

    assert detailed_entry_ids == Enum.map(3..10, &"autumn-event-#{&1}")
    assert compiled.context_completeness.continuity_memory_details_omitted
  end

  test "filters unrelated public and private continuity details by relevance" do
    context = base_context()

    context =
      put_in(context, [:continuity], %{
        public: [
          %{
            entry_id: "player-note",
            title: "A distant plan",
            details: "The harvesters tend the western orchard row.",
            status: "active",
            player_managed: true
          },
          %{
            entry_id: "gm-note",
            title: "An established public fact",
            details: "The harbor toll is waived for the autumn boats.",
            status: "active",
            player_managed: false
          }
        ],
        gm_private: [
          %{
            entry_id: "private-note",
            title: "Hidden plan",
            details: "The hidden orchard cache is under the western row.",
            status: "active",
            player_managed: true
          }
        ]
      })

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra")

    assert metrics.compacted?

    assert Enum.find(compiled.continuity.public, &(&1.entry_id == "player-note")) ==
             Map.take(hd(context.continuity.public), [
               :entry_id,
               :kind,
               :status,
               :player_managed
             ])

    assert Enum.find(compiled.continuity.public, &(&1.entry_id == "gm-note")) ==
             Map.take(Enum.at(context.continuity.public, 1), [
               :entry_id,
               :kind,
               :status,
               :visibility,
               :player_managed
             ])

    assert compiled.continuity.gm_private == [
             Map.take(hd(context.continuity.gm_private), [
               :entry_id,
               :kind,
               :status,
               :visibility,
               :player_managed
             ])
           ]
  end

  test "compacts oversized continuity prose and preserves the active commitment" do
    context =
      base_context()
      |> Map.put(:player_action, "What did we agree about Marisol at the Bodega?")
      |> update_in([:continuity], fn _continuity ->
        %{
          public: [
            %{
              entry_id: "active-large",
              kind: "commitment",
              title: "Marisol's Bodega agreement",
              details:
                "Marisol agreed to " <> String.duplicate("keep the harvest reserve ", 3_000),
              status: "active",
              visibility: "public"
            },
            %{
              entry_id: "closed-large",
              kind: "fact",
              title: "Closed arc",
              details: String.duplicate("closed prose ", 3_000),
              status: "completed",
              visibility: "public"
            }
          ],
          gm_private: []
        }
      end)

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_byte_budget: 5_000
             )

    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert :continuity_memory_details in metrics.omissions
    assert compacted.player_action == context.player_action
    active = Enum.find(compacted.continuity.public, &(&1.entry_id == "active-large"))
    assert active.status == "active"
    assert active.title == "Marisol's Bodega agreement"
    assert String.length(active.details) <= 280
    assert length(context.continuity.public) == 2
  end

  test "applies safe relevance compaction below the byte limit and reports omissions" do
    instructions = "Policy"

    action =
      "Check whether Marisol stayed at the Finca after the forty-minute trip to the Bodega."

    history =
      Enum.map(1..18, fn sequence ->
        text =
          if sequence == 1 do
            "Marisol stayed at the Finca after the forty-minute trip to the Bodega."
          else
            "Regional market report #{sequence}; the quarterly grain totals remain unchanged."
          end

        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{"text" => text}
        }
      end)

    context =
      base_context()
      |> Map.put(:player_action, action)
      |> Map.put(:private_test_value, "Hidden cellar key")
      |> Map.put(:history, history)
      |> update_in([:characters], fn characters ->
        characters
        |> Enum.map(fn character ->
          if character.speaker_id == "marisol" do
            Map.put(character, :voice_guidance, %{
              accent: "French",
              mannerisms: "Taps the rim of a glass while thinking."
            })
          else
            character
          end
        end)
        |> Kernel.++([
          %{
            speaker_id: "archivist",
            name: "Ivo",
            role: :gm,
            current_place_id: "archive",
            current_place: %{
              place_id: "archive",
              name: "The Copper Archive",
              visibility: :public,
              description: String.duplicate("Archive description. ", 60),
              facts: %{hidden_shelf: String.duplicate("unseen record ", 40)}
            },
            visible_facts: %{specialty: String.duplicate("archival note ", 40)},
            gm_private_facts: %{secret: "Ivo has not met the player."},
            voice_guidance: %{cadence: String.duplicate("measured ", 40)}
          }
        ])
      end)
      |> update_in([:places, :public], fn places ->
        places ++
          [
            %{
              place_id: "archive",
              name: "The Copper Archive",
              visibility: :public,
              description: String.duplicate("Archive description. ", 60),
              facts: %{hidden_shelf: String.duplicate("unseen record ", 40)}
            }
          ]
      end)
      |> update_in([:objectives, :public], fn objectives ->
        [
          %{
            objective_id: "cellar-review",
            title: "Review the cellar records",
            details: "Compare the Bodega records after checking the Finca ledger.",
            status: "open"
          },
          %{
            objective_id: "closed-market-report",
            title: "Old market report",
            details: String.duplicate("Closed market detail. ", 50),
            status: "completed"
          }
          | objectives
        ]
      end)
      |> update_in([:memory, :public_summary], fn _summary ->
        String.duplicate("Older campaign summary. ", 80)
      end)
      |> update_in([:continuity, :public], fn _entries ->
        [
          %{
            entry_id: "finca-staff-commitment",
            kind: "commitment",
            title: "Marisol stays at the Finca",
            details:
              "Marisol promised to remain at the Finca while the cellar team travels to the Bodega.",
            status: "active",
            visibility: "public"
          },
          %{
            entry_id: "archive-lunch",
            kind: "fact",
            title: "Lunch at the archive",
            details: "A detail unrelated to the current scene.",
            status: "active",
            visibility: "public"
          }
        ]
      end)

    budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]
    source_bytes = request_bytes(context, instructions)
    assert source_bytes < budget

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, instructions, "gpt-6-astra")

    assert metrics.compacted?
    assert metrics.estimated_request_bytes < source_bytes
    assert metrics.estimated_request_bytes <= budget
    assert :history in metrics.omissions
    assert :remote_character_profiles in metrics.omissions
    assert :remote_place_details in metrics.omissions
    assert :closed_objective_details in metrics.omissions
    assert :memory_summary in metrics.omissions
    assert :continuity_memory_details in metrics.omissions

    assert compiled.context_completeness.history_compacted
    assert compiled.context_completeness.remote_character_profiles_omitted
    assert compiled.context_completeness.remote_place_details_omitted
    assert compiled.context_completeness.closed_objective_details_omitted
    assert compiled.context_completeness.memory_summary_compacted
    assert compiled.context_completeness.continuity_memory_details_omitted

    assert Enum.map(compiled.history, & &1["sequence"]) == [1 | Enum.to_list(7..18)]

    assert Enum.find(compiled.history, &(&1["sequence"] == 1))["payload"]["text"] =~
             "Marisol stayed"

    assert Enum.any?(compiled.history, &(&1["sequence"] == 18))

    original_marisol = Enum.find(context.characters, &(&1.speaker_id == "marisol"))
    marisol = Enum.find(compiled.characters, &(&1.speaker_id == "marisol"))
    assert marisol.visible_facts == original_marisol.visible_facts
    assert marisol.gm_private_facts == original_marisol.gm_private_facts
    assert marisol.voice_guidance.accent == "French"

    archivist = Enum.find(compiled.characters, &(&1.speaker_id == "archivist"))

    assert Map.get(archivist, "current_place") == %{
             place_id: "archive",
             name: "The Copper Archive",
             visibility: :public
           }

    refute Map.has_key?(archivist, :visible_facts)
    refute Map.has_key?(archivist, :gm_private_facts)
    refute Map.has_key?(archivist, :voice_guidance)

    archive = Enum.find(compiled.places.public, &(&1.place_id == "archive"))
    assert archive == %{place_id: "archive", name: "The Copper Archive", visibility: :public}

    assert Enum.find(compiled.places.public, &(&1.place_id == "finca")).description ==
             Enum.find(context.places.public, &(&1.place_id == "finca")).description

    assert Enum.find(compiled.places.public, &(&1.place_id == "bodega")).description ==
             Enum.find(context.places.public, &(&1.place_id == "bodega")).description

    active_objective =
      Enum.find(compiled.objectives.public, &(&1.objective_id == "cellar-review"))

    assert active_objective.details =~ "Compare the Bodega records"

    closed_objective =
      Enum.find(compiled.objectives.public, &(&1.objective_id == "closed-market-report"))

    refute Map.has_key?(closed_objective, :details)

    relevant_commitment =
      Enum.find(compiled.continuity.public, &(&1.entry_id == "finca-staff-commitment"))

    assert relevant_commitment.details =~ "Marisol promised"

    irrelevant_commitment =
      Enum.find(compiled.continuity.public, &(&1.entry_id == "archive-lunch"))

    refute Map.has_key?(irrelevant_commitment, :details)

    assert compiled.world == context.world
    assert compiled.player_action == context.player_action
    assert length(context.history) == 18
    refute Jason.encode!(metrics) =~ "Hidden cellar key"
    assert metrics.section_bytes.section_world_bytes > 0
    assert metrics.section_bytes.section_history_bytes < byte_size(Jason.encode!(context.history))
  end

  test "reports no compaction when an under-budget scene has no irrelevant details" do
    context =
      base_context()
      |> update_in([:characters], fn characters ->
        Enum.map(characters, fn character ->
          if character.speaker_id == "tomas" do
            place = %{place_id: "finca", name: "Finca", visibility: :public}

            character
            |> Map.put(:current_place_id, "finca")
            |> Map.put(:current_place, place)
          else
            character
          end
        end)
      end)

    assert {:ok, %{context: ^context, metrics: metrics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra")

    refute metrics.compacted?
    assert metrics.omissions == []
    assert metrics.estimated_request_bytes == request_bytes(context, "Policy")
  end

  test "accepts the 31,825-byte relevant scene shape under the default local guard" do
    configured_budgets = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)

    assert Enum.sort(Map.keys(configured_budgets)) ==
             Enum.sort([
               "default",
               "gpt-6-astra",
               "gpt-5.6-sol",
               "gpt-5.6-terra",
               "gpt-5.6-luna",
               "gpt-5.5"
             ])

    assert Map.values(configured_budgets) |> Enum.uniq() == [64_000]

    premise = String.duplicate("A", 10_000)
    current_place_description = String.duplicate("B", 10_000)

    context =
      base_context()
      |> put_in([:campaign, :premise], premise)
      |> update_in([:places, :public], fn places ->
        Enum.map(places, fn
          %{place_id: "finca"} = place ->
            Map.put(place, :description, current_place_description)

          place ->
            place
        end)
      end)

    assert {:ok, %{metrics: empty_instructions_metrics}} =
             ContextBudget.compile(context, "", "gpt-6-astra")

    instruction_bytes = 31_825 - empty_instructions_metrics.estimated_request_bytes
    assert instruction_bytes >= 8_000
    instructions = String.duplicate("i", instruction_bytes)

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, instructions, "gpt-6-astra")

    assert metrics.budget_bytes == 64_000
    assert metrics.instructions_bytes == instruction_bytes
    assert metrics.estimated_request_bytes == 31_825
    assert compiled.campaign.premise == premise

    assert Enum.find(compiled.places.public, &(&1.place_id == "finca")).description ==
             current_place_description

    assert {:ok, %{context: compacted, metrics: compacted_metrics}} =
             ContextBudget.compile(context, instructions, "gpt-6-astra",
               context_input_byte_budget: 24_000
             )

    assert compacted_metrics.estimated_request_bytes <= 24_000
    assert :campaign_details in compacted_metrics.omissions
    assert compacted.context_completeness.campaign_details_compacted
    assert compacted.player_action == context.player_action
  end

  test "rejects required canonical state that cannot fit instead of truncating it" do
    context =
      update_in(base_context(), [:world, :public], fn world ->
        Map.put(world, :massive_state, String.duplicate("canon ", 2_000))
      end)

    assert {:error, {:context_budget_exceeded, diagnostics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_byte_budget: 2_000
             )

    assert diagnostics.largest_sections |> hd() |> Map.fetch!(:bytes) > 0
  end

  test "emits safe provider counts and section sizes as numeric telemetry" do
    context = base_context()
    assert {:ok, %{metrics: metrics}} = ContextBudget.compile(context, "Policy", "gpt-6-astra")

    ref = make_ref()
    parent = self()

    :ok =
      :telemetry.attach(
        {__MODULE__, ref},
        [:storyteller, :gm, :context],
        fn event, measurements, metadata, _config ->
          send(parent, {:metrics, event, measurements, metadata})
        end,
        nil
      )

    ContextBudget.emit_metrics(metrics, %{input_tokens: 1_234, output_tokens: 56})

    assert_receive {:metrics, [:storyteller, :gm, :context], emitted, %{}}
    assert emitted.provider_input_tokens == 1_234
    assert emitted.provider_output_tokens == 56
    assert emitted.section_world_bytes == metrics.section_bytes.section_world_bytes
    refute Map.has_key?(emitted, :campaign_id)
    :telemetry.detach({__MODULE__, ref})
  end

  test "reports only sizes when required canon exceeds the configured bound" do
    ref = make_ref()
    parent = self()

    :ok =
      :telemetry.attach(
        {__MODULE__, ref},
        [:storyteller, :gm, :context],
        fn _event, measurements, metadata, _config ->
          send(parent, {:rejected_context_metrics, measurements, metadata})
        end,
        nil
      )

    assert {:error, {:context_budget_exceeded, diagnostics}} =
             ContextBudget.compile(base_context(), "Hidden instruction test", "test-model",
               context_input_byte_budget: 1
             )

    assert diagnostics.budget_bytes == 1
    assert diagnostics.instructions_bytes == byte_size("Hidden instruction test")
    assert diagnostics.section_bytes |> Map.values() |> Enum.all?(&is_integer/1)
    refute Map.values(diagnostics) |> inspect() =~ "Hidden instruction test"

    assert_receive {:rejected_context_metrics, measurements, %{}}
    assert measurements.budget_bytes == 1
    assert Enum.all?(Map.values(measurements), &is_number/1)
    refute Jason.encode!(measurements) =~ "Hidden instruction test"
    :telemetry.detach({__MODULE__, ref})
  end

  test "compacts against the exact escaped request envelope for multilingual campaign text" do
    instructions =
      "Policy with \"quoted rules\"\nKeep Spanish and French accents: acción, fraîche."

    notes =
      String.duplicate(
        "El GM dice: \"brume fraîche\"\nEl jugador pregunta: \"¿Qué pasó?\"\n",
        80
      )

    context = put_in(base_context(), [:world, :public, :flavor_notes], notes)

    legacy_estimate = byte_size(instructions) + byte_size(Jason.encode!(context)) + 512
    exact_automatic_model_bytes = request_bytes(context, instructions, nil)
    assert exact_automatic_model_bytes > legacy_estimate

    budget = div(legacy_estimate + exact_automatic_model_bytes, 2)
    assert legacy_estimate < budget
    assert exact_automatic_model_bytes > budget

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, instructions, nil, context_input_byte_budget: budget)

    assert metrics.compacted?
    assert metrics.estimated_request_bytes == request_bytes(compiled, instructions, nil)
    assert metrics.estimated_request_bytes <= budget
    assert request_bytes(compiled, instructions, "fixture-model") <= budget
    assert compiled.world.public.flavor_notes =~ "brume fraîche"
    assert String.length(compiled.world.public.flavor_notes) < String.length(notes)
    assert context.world.public.flavor_notes == notes
  end

  test "classifies invalid context encoding separately from a size overflow" do
    assert {:error, :context_compilation_failed} =
             ContextBudget.compile(%{unsupported: self()}, "Policy", "test-model")

    assert {:error, :context_compilation_failed} =
             ContextBudget.compile([], "Policy", "test-model")
  end

  test "includes GM instructions among the numeric categories that can dominate a request" do
    instructions = String.duplicate("policy ", 2_000)

    assert {:error, {:context_budget_exceeded, diagnostics}} =
             ContextBudget.compile(base_context(), instructions, "test-model",
               context_input_byte_budget: 1
             )

    assert hd(diagnostics.largest_sections) == %{
             category: "gm_instructions",
             bytes: byte_size(instructions)
           }

    refute inspect(diagnostics) =~ instructions
  end

  defp base_context do
    %{
      phase: "initial",
      campaign: %{title: "The Amber Orchard", premise: "A quiet vineyard mystery"},
      player_action: "Return to the Bodega and ask Marisol about the harvest.",
      player_roll: nil,
      world: %{public: %{location: "Finca", date: "1567-04-12"}, gm_private: %{}},
      inventory: %{player_visible: [], gm_private: []},
      places: %{
        public: [
          %{
            place_id: "finca",
            name: "Finca",
            visibility: :public,
            description: "The home vineyard."
          },
          %{
            place_id: "bodega",
            name: "Bodega",
            visibility: :public,
            description: "The wine cellar."
          }
        ],
        gm_private: []
      },
      travel_connections: %{
        public: [%{place_a_id: "bodega", place_b_id: "finca", travel_minutes: 40}],
        gm_private: [],
        public_routes: [],
        gm_private_routes: []
      },
      objectives: %{public: [], gm_private: []},
      memory: %{public_summary: "", gm_private_summary: ""},
      continuity: %{public: [], gm_private: []},
      characters: [
        %{
          speaker_id: "player",
          name: "Ana",
          role: :player,
          current_place_id: "finca",
          current_place: %{place_id: "finca", name: "Finca", visibility: :public},
          visible_facts: %{},
          gm_private_facts: %{}
        },
        %{
          speaker_id: "marisol",
          name: "Marisol",
          role: :gm,
          current_place_id: "finca",
          current_place: %{place_id: "finca", name: "Finca", visibility: :public},
          visible_facts: %{voice: "A patient, wry French beaver cook."},
          gm_private_facts: %{motive: "Keep the cellar ledger hidden."}
        },
        %{
          speaker_id: "tomas",
          name: "Tomás",
          role: :gm,
          current_place_id: "bodega",
          current_place: %{place_id: "bodega", name: "Bodega", visibility: :public},
          visible_facts: %{voice: "Speaks softly."},
          gm_private_facts: %{secret: "Do not repeat this."}
        }
      ],
      panels: [],
      history: []
    }
  end

  defp synthetic_history(count) do
    Enum.map(1..count, fn sequence ->
      text =
        case sequence do
          5 ->
            "At the Bodega, Marisol promised the Finca staff would stay in place until harvest work was complete. " <>
              String.duplicate("This old commitment remains relevant. ", 10)

          73 ->
            "At the Finca, Marisol said she could not join cellar pressing at the Bodega before harvest ended. " <>
              String.duplicate("This old commitment remains relevant. ", 10)

          157 ->
            "Marisol's harvest duty at the Finca ends before she can make the forty-minute trip to the Bodega. " <>
              String.duplicate("This old commitment remains relevant. ", 10)

          193 ->
            "At the Bodega, a broken roof tile was replaced after a spring storm."

          199 ->
            "At the Finca, the public notice board was repainted before dawn."

          211 ->
            "Marisol labels a kitchen basket for the market."

          217 ->
            "A Bodega-side bridge toll announcement repeated last week's rates."

          223 ->
            "An old machine pressing demonstration ran at the county fair."

          225 ->
            "At the Bodega print shop, a poster was made for a town festival."

          227 ->
            "Marisol described the Finca fountain's new stonework; no staff matter was discussed."

          _ ->
            unrelated_history_text(sequence)
        end

      %{
        "sequence" => sequence,
        "session_id" => div(sequence - 1, 30) + 1,
        "event_type" => "gm_narration",
        "visibility" => "public",
        "speaker_id" => nil,
        "payload" => %{"text" => text}
      }
    end)
  end

  defp unrelated_history_text(sequence) do
    detail =
      case rem(sequence, 4) do
        0 -> "Wheat prices changed in the regional market."
        1 -> "The town bridge toll waiver remains in force through midsummer."
        2 -> "The traveling theater troupe moved its opening performance indoors."
        3 -> "Quarterly bond yields shifted after the central bank announcement."
      end

    "Unrelated record #{sequence}: #{detail} " <> String.duplicate("Archived report. ", 10)
  end

  # Play keeps its policy private and action mode adds no extra guidance.
  # Read the policy literal so this context-size comparison follows the shipped text.
  defp production_gm_policy do
    source_path = Path.expand("../../../lib/storyteller/play.ex", __DIR__)
    source = File.read!(source_path)

    case Regex.run(~r/@gm_policy\s+"""\r?\n(.*?)\r?\n([ ]+)"""/s, source) do
      [_, policy, indentation] ->
        policy
        |> String.split("\n")
        |> Enum.map(&String.replace_prefix(&1, indentation, ""))
        |> Enum.join("\n")

      _ ->
        flunk("Could not find the production GM policy heredoc in #{source_path}")
    end
  end

  defp request_bytes(context, instructions, model \\ "gpt-6-astra") do
    model = if is_binary(model), do: model, else: String.duplicate("m", 255)

    body = %{
      "model" => model,
      "instructions" => instructions,
      "input" => [
        %{
          role: "user",
          content: [%{type: "input_text", text: Jason.encode!(context)}]
        }
      ],
      "store" => false,
      "stream" => true
    }

    byte_size(Jason.encode!(body))
  end
end
