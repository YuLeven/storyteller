defmodule Storyteller.GM.TimePassageDurationTest do
  use ExUnit.Case, async: true

  alias Storyteller.GM.TimePassageDuration

  @max_minutes 5_256_000_000

  test "recognizes clear numeric durations in English, Spanish, and French" do
    assert TimePassageDuration.parse(
             "Wait here for 21 days until the courier arrives.",
             @max_minutes
           ) ==
             {:ok, 30_240}

    assert TimePassageDuration.parse("Wait 21 days until the courier arrives.", @max_minutes) ==
             {:ok, 30_240}

    assert TimePassageDuration.parse("Espera 35 minutos.", @max_minutes) == {:ok, 35}
    assert TimePassageDuration.parse("Espera 3 días.", @max_minutes) == {:ok, 4_320}
    assert TimePassageDuration.parse("Attends 2 heures.", @max_minutes) == {:ok, 120}
  end

  test "leaves vague, qualified, and conflicting durations to the GM" do
    assert TimePassageDuration.parse("Let the days pass.", @max_minutes) == :none
    assert TimePassageDuration.parse("Wait for about 3 days.", @max_minutes) == :none
    assert TimePassageDuration.parse("Wait within 3 days.", @max_minutes) == :none
    assert TimePassageDuration.parse("Wait more than 3 days.", @max_minutes) == :none
    assert TimePassageDuration.parse("Wait 3 days max.", @max_minutes) == :none
    assert TimePassageDuration.parse("Wait 2–3 days.", @max_minutes) == :none
    assert TimePassageDuration.parse("Espera entre 2 y 3 días.", @max_minutes) == :none

    assert TimePassageDuration.parse("Wait for 2 days, then wait another 2 days.", @max_minutes) ==
             :ambiguous

    assert TimePassageDuration.parse("Wait for 2 days, then continue for 3 hours.", @max_minutes) ==
             :ambiguous
  end

  test "rejects a clear requested duration beyond the campaign clock limit" do
    assert TimePassageDuration.parse("Wait for 1,000 weeks.", 10_000) == :none
    assert TimePassageDuration.parse("Wait for 100 weeks.", 10_000) == {:error, :out_of_range}
  end
end
