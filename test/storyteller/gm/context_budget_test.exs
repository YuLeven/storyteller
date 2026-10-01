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

  test "keeps eight bounded player-authored memories inside the default context budget" do
    context = base_context()

    player_memories =
      Enum.map(1..8, fn number ->
        %{
          entry_id: "player-memory-#{number}",
          kind: "commitment",
          title: "Player memory #{number}",
          details:
            String.pad_trailing("A public promise that remains canonical. #{number}", 300, " "),
          status: "active",
          visibility: "public",
          source_sequence: nil
        }
      end)

    history =
      Enum.map(1..45, fn sequence ->
        %{
          "sequence" => sequence,
          "session_id" => 1,
          "event_type" => "gm_narration",
          "visibility" => "public",
          "speaker_id" => nil,
          "payload" => %{"text" => String.duplicate("Unrelated scene detail. ", 35)}
        }
      end)

    context =
      context
      |> Map.put(:continuity, %{public: player_memories, gm_private: []})
      |> Map.put(:history, history)

    assert {:ok, %{context: compiled, metrics: metrics}} =
             ContextBudget.compile(context, "Short GM policy", "gpt-6-astra")

    assert metrics.conservative_input_token_upper_bound <= 24_000

    assert Enum.map(compiled.continuity.public, & &1.details) ==
             Enum.map(player_memories, & &1.details)

    assert Enum.all?(compiled.continuity.public, &(&1.source_sequence == nil))
    assert compiled.context_completeness.history_compacted
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
end
