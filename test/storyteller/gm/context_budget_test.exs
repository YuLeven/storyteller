defmodule Storyteller.GM.ContextBudgetTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.ContextBudget

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
      assert metrics.estimated_request_bytes <= 24_000
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
    instructions = production_gm_policy()
    budget = Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["default"]

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

    assert Enum.all?(older_texts, &(byte_size(&1) <= 600))
    assert Enum.all?(newest_texts, &(byte_size(&1) > 600))

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
    instruction_bytes =
      budget - request_bytes(no_history_context, "") - 512

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
             "Wine, food, or drink tastings: give sensory details (appearance, aroma, taste, finish) first"

    assert policy =~
             "if relevant, a present NPC expert offers a qualified, evidence-based view."

    assert policy =~
             "Yield for player reaction; never ask them to invent sensory facts or dictate their response."

    assert policy =~ "Never ask players to define sensory facts."

    assert policy =~ "Preserve each NPC's knowledge, motives, work, and distinct voice."
    assert policy =~ "Each speaker_id's voice profile shapes dialogue; never blend profiles."

    assert policy =~
             "Briefly show a configured mannerism when apt; quirks only when relevant."

    assert policy =~ "Natural wording; avoid phonetics, caricature, or clichés."
    assert policy =~ "No forced humor/gestures or repeated cues."

    assert policy =~
             "Create exactly {type:\"create\",entry:{entry_id,kind, title,details,visibility},reason}"

    assert policy =~ "Record witnessed evidence, not guessed causes"

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

    assert byte_size(Jason.encode!(context)) + byte_size("Short GM policy") + 512 < 24_000

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.estimated_request_bytes <= 24_000
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

      assert metrics.estimated_request_bytes <= 24_000

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

    assert metrics.estimated_request_bytes <= 24_000

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

  test "fails recoverably when active continuity canon alone cannot fit" do
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

    assert {:error, {:context_budget_exceeded, diagnostics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_byte_budget: 5_000
             )

    assert diagnostics.estimated_request_bytes > diagnostics.budget_bytes
    assert diagnostics.largest_sections != []
    assert diagnostics.section_bytes["gm_instructions"] == byte_size("Policy")
    assert Enum.all?(Map.values(diagnostics.section_bytes), &is_integer/1)

    assert Map.keys(diagnostics)
           |> Enum.all?(
             &(&1 in [
                 :budget_bytes,
                 :estimated_request_bytes,
                 :instructions_bytes,
                 :context_json_bytes,
                 :section_bytes,
                 :largest_sections
               ])
           )
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

  defp request_bytes(context, instructions) do
    byte_size(instructions) + byte_size(Jason.encode!(context)) + 512
  end
end
