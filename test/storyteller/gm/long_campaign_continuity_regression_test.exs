defmodule Storyteller.GM.LongCampaignContinuityRegressionTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.ContextBudget

  test "a distant employee stays anchored across a noisy multi-session campaign" do
    instructions =
      "Keep established places, travel times, character locations, and duties consistent. " <>
        "Use older history only when it bears on the player's current action."

    budget =
      Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["gpt-6-astra"]

    history = long_campaign_history(2_400)
    assert length(Enum.uniq_by(history, & &1["session_id"])) == 100

    base =
      base_context()
      |> Map.put(
        :player_action,
        "I arrive at the Bodega after the forty-minute trip from Finca. Could Marisol or the Finca staff reach the cellar during harvest work?"
      )

    short_context = Map.put(base, :history, Enum.take(history, -12))
    long_context = Map.put(base, :history, history)

    assert {:ok, %{context: short_compiled, metrics: short_metrics}} =
             ContextBudget.compile(short_context, instructions, "gpt-6-astra")

    assert short_compiled == short_context
    refute short_metrics.compacted?

    assert {:ok, %{context: long_compiled, metrics: long_metrics}} =
             ContextBudget.compile(long_context, instructions, "gpt-6-astra")

    assert long_metrics.compacted?
    assert long_metrics.estimated_request_bytes <= budget
    assert long_compiled.context_completeness.history_compacted

    retained_sequences = MapSet.new(long_compiled.history, & &1["sequence"])
    recent_sequences = MapSet.new(Enum.take(history, -12), & &1["sequence"])
    old_sequences = MapSet.difference(MapSet.new(1..2_400), recent_sequences)

    # This public scene establishes the distance and why Marisol and the Finca
    # staff remain at the vineyard. It must survive even after one hundred sessions.
    assert MapSet.member?(retained_sequences, 7)

    assert Enum.find(long_compiled.history, &(&1["sequence"] == 7))["payload"]["text"] =~
             "forty-minute trip"

    # The newest turns remain available, while unrelated older reports do not
    # displace the one fact needed to keep the scene coherent.
    assert MapSet.subset?(recent_sequences, retained_sequences)
    refute MapSet.member?(retained_sequences, 8)
    assert MapSet.intersection(old_sequences, retained_sequences) == MapSet.new([7])

    assert Map.new(long_compiled.characters, &{&1.speaker_id, &1.current_place_id}) ==
             Map.new(long_context.characters, &{&1.speaker_id, &1.current_place_id})

    marisol = Enum.find(long_compiled.characters, &(&1.speaker_id == "marisol"))
    assert marisol.current_place_id == "finca"
    assert marisol.active_duty.place_id == "finca"
    assert long_compiled.travel_connections == long_context.travel_connections
    assert long_compiled.inventory == long_context.inventory

    full_request_bytes = byte_size(instructions) + byte_size(Jason.encode!(long_context)) + 512
    short_request_bytes = short_metrics.estimated_request_bytes

    assert full_request_bytes >= long_metrics.estimated_request_bytes * 5
    assert long_metrics.estimated_request_bytes <= short_request_bytes + 2_000
  end

  defp base_context do
    %{
      phase: "playing",
      campaign: %{title: "The Amber Orchard", premise: "A vineyard campaign in 1567 Italy."},
      player_action: "Travel to the Bodega.",
      player_roll: nil,
      world: %{public: %{location: "Bodega", date: "1567-04-12"}, gm_private: %{}},
      inventory: %{player_visible: [%{name: "Cellar ledger", quantity: 1}], gm_private: []},
      places: %{
        public: [
          %{place_id: "finca", name: "Finca", visibility: :public, description: "The vineyard."},
          %{place_id: "bodega", name: "Bodega", visibility: :public, description: "The cellar."}
        ],
        gm_private: []
      },
      travel_connections: %{
        public: [%{place_a_id: "finca", place_b_id: "bodega", travel_minutes: 40}],
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
          current_place_id: "bodega",
          current_place: %{place_id: "bodega", name: "Bodega", visibility: :public},
          visible_facts: %{},
          gm_private_facts: %{}
        },
        %{
          speaker_id: "marisol",
          name: "Marisol",
          role: :gm,
          current_place_id: "finca",
          current_place: %{place_id: "finca", name: "Finca", visibility: :public},
          active_duty: %{name: "Finish harvest work", place_id: "finca", place_name: "Finca"},
          visible_facts: %{voice: "A patient, wry French beaver cook."},
          gm_private_facts: %{}
        },
        %{
          speaker_id: "tomas",
          name: "Tomás",
          role: :gm,
          current_place_id: "bodega",
          current_place: %{place_id: "bodega", name: "Bodega", visibility: :public},
          visible_facts: %{voice: "Speaks softly."},
          gm_private_facts: %{}
        }
      ],
      panels: [],
      history: []
    }
  end

  defp long_campaign_history(count) do
    Enum.map(1..count, fn sequence ->
      text =
        if sequence == 7 do
          "The Bodega is a forty-minute trip from Finca. Marisol's harvest work keeps her at Finca until dusk, and the Finca staff stay there with her."
        else
          "Session note #{sequence}: the town council reviewed unrelated harbor toll accounts and theater bookings. " <>
            String.duplicate("No vineyard business was discussed. ", 8)
        end

      %{
        "sequence" => sequence,
        "session_id" => div(sequence - 1, 24) + 1,
        "event_type" => "gm_narration",
        "visibility" => "public",
        "speaker_id" => nil,
        "payload" => %{"text" => text}
      }
    end)
  end
end
