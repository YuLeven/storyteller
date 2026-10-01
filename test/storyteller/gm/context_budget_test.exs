defmodule Storyteller.GM.ContextBudgetTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.ContextBudget

  test "compacts unrelated history while retrieving an older fact named in the action" do
    context = base_context()

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
               context_input_token_budget: 20_000
             )

    assert metrics.compacted?
    assert metrics.conservative_input_token_upper_bound <= 20_000
    assert length(compacted.history) <= 20
    assert Enum.any?(compacted.history, &(&1["sequence"] == 5))
    assert Enum.any?(compacted.history, &(&1["sequence"] == 50))
    assert compacted.context_completeness.history_compacted

    assert compacted.characters
           |> Enum.find(&(&1.speaker_id == "marisol"))
           |> Map.fetch!(:current_place_id) ==
             "finca"
  end

  test "keeps a long campaign request near the short-campaign baseline" do
    instructions = "Short GM policy"
    budget = 20_000

    base =
      update_in(base_context(), [:characters], fn characters ->
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

    assert {:ok, %{context: short_compiled, metrics: short_metrics}} =
             ContextBudget.compile(short_context, instructions, "gpt-6-astra",
               context_input_token_budget: budget
             )

    assert short_compiled == short_context
    refute short_metrics.compacted?

    assert {:ok, %{context: long_compiled, metrics: long_metrics}} =
             ContextBudget.compile(long_context, instructions, "gpt-6-astra",
               context_input_token_budget: budget
             )

    assert long_metrics.compacted?
    assert long_metrics.conservative_input_token_upper_bound <= budget
    assert long_compiled.context_completeness.history_compacted

    full_history_request_bytes = request_bytes(long_context, instructions)
    bounded_history_request_bytes = long_metrics.conservative_input_token_upper_bound
    short_request_bytes = short_metrics.conservative_input_token_upper_bound

    assert full_history_request_bytes >= bounded_history_request_bytes * 5
    assert bounded_history_request_bytes <= short_request_bytes + 2_000

    assert Enum.any?(long_compiled.history, fn event ->
             event["sequence"] == 5 and
               String.contains?(event["payload"]["text"], "Marisol promised")
           end)

    refute Enum.any?(long_compiled.history, &(&1["sequence"] == 100))
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

  test "keeps every active continuity detail while compacting history and closed entries" do
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
            kind: "fact",
            title: "Active canon #{number}",
            details:
              "Unmentioned durable canon #{number}: " <>
                String.duplicate("keepsake stewardship ", 12),
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
               context_input_token_budget: 24_000
             )

    assert metrics.compacted?
    assert metrics.conservative_input_token_upper_bound <= 24_000

    compacted_entries = compacted.continuity.public

    assert Enum.find(compacted_entries, &(&1.entry_id == "active-1")) ==
             Enum.find(continuity_entries, &(&1.entry_id == "active-1"))

    assert Enum.all?(Enum.filter(compacted_entries, &(&1.status == "active")), fn entry ->
             String.starts_with?(entry.details, "Unmentioned durable canon")
           end)

    refute Map.has_key?(Enum.find(compacted_entries, &(&1.entry_id == "closed-old")), :details)
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
               context_input_token_budget: 20_000
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

    assert {:ok, %{context: compacted, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra",
               context_input_token_budget: 20_000
             )

    assert metrics.compacted?

    compacted_characters = Map.new(compacted.characters, &{&1.speaker_id, &1})
    assert compacted_characters["marisol"].voice_guidance == marisol_voice
    assert compacted_characters["keeper"].voice_guidance == keeper_voice
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

    assert metrics.conservative_input_token_upper_bound <= 24_000
    assert metrics.compacted?
    assert metrics.omissions == [:player_managed_memory_details]

    [relevant | unrelated] = compiled.continuity.public
    assert relevant.details == hd(player_memories).details

    assert Enum.all?(unrelated, fn entry ->
             Enum.all?([:title, :details], &(not Map.has_key?(entry, &1)))
           end)

    assert Enum.map(compiled.continuity.public, & &1.entry_id) ==
             Enum.map(player_memories, & &1.entry_id)

    assert compiled.context_completeness.player_managed_memory_details_omitted
    refute Map.get(compiled.context_completeness, :history_compacted, false)

    assert metrics.context_json_bytes < byte_size(Jason.encode!(context))
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

      assert metrics.conservative_input_token_upper_bound <= 24_000

      assert Enum.find(compiled.continuity.public, &(&1.entry_id == "wine-reserve")).details ==
               player_memory.details

      unrelated = Enum.find(compiled.continuity.public, &(&1.entry_id == "bridge-toll"))
      refute Map.has_key?(unrelated, :title)
      refute Map.has_key?(unrelated, :details)
    end
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

    assert metrics.conservative_input_token_upper_bound <= 24_000

    detailed_entry_ids =
      compiled.continuity.public
      |> Enum.filter(&Map.has_key?(&1, :details))
      |> Enum.map(& &1.entry_id)

    assert detailed_entry_ids == Enum.map(3..10, &"autumn-event-#{&1}")
    assert compiled.context_completeness.player_managed_memory_details_omitted
  end

  test "uses exact meaningful word matches and leaves GM-authored or private continuity intact" do
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
             Enum.at(context.continuity.public, 1)

    assert compiled.continuity.gm_private == context.continuity.gm_private
  end

  test "fails recoverably when active continuity canon alone cannot fit" do
    context =
      update_in(base_context(), [:continuity], fn _continuity ->
        %{
          public: [
            %{
              entry_id: "active-large",
              kind: "fact",
              title: "A required durable fact",
              details: String.duplicate("active canon ", 3_000),
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

    assert {:error, :context_budget_exceeded} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_token_budget: 5_000
             )
  end

  test "keeps the full context unchanged when it fits and records only sizes" do
    context = Map.put(base_context(), :private_test_value, "Hidden cellar key")

    assert {:ok, %{context: ^context, metrics: metrics}} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_token_budget: 20_000
             )

    assert metrics.compacted? == false
    refute Jason.encode!(metrics) =~ "Hidden cellar key"
    assert metrics.section_bytes.section_world_bytes > 0
    assert metrics.section_bytes.section_history_bytes > 0
  end

  test "rejects required canonical state that cannot fit instead of truncating it" do
    context =
      update_in(base_context(), [:world, :public], fn world ->
        Map.put(world, :massive_state, String.duplicate("canon ", 2_000))
      end)

    assert {:error, :context_budget_exceeded} =
             ContextBudget.compile(context, "Policy", "gpt-6-astra",
               context_input_token_budget: 2_000
             )
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

    assert {:error, :context_budget_exceeded} =
             ContextBudget.compile(base_context(), "Hidden instruction test", "test-model",
               context_input_token_budget: 1
             )

    assert_receive {:rejected_context_metrics, measurements, %{}}
    assert measurements.budget_tokens == 1
    assert Enum.all?(Map.values(measurements), &is_number/1)
    refute Jason.encode!(measurements) =~ "Hidden instruction test"
    :telemetry.detach({__MODULE__, ref})
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
        if sequence == 5 do
          "At the Bodega, Marisol promised the Finca staff would stay in place until the harvest work was complete. " <>
            String.duplicate("This old commitment remains relevant. ", 10)
        else
          "Unrelated accounting report #{sequence}. " <>
            String.duplicate("Wheat prices changed in the regional market. ", 10)
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

  defp request_bytes(context, instructions) do
    byte_size(instructions) + byte_size(Jason.encode!(context)) + 512
  end
end
