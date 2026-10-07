defmodule Storyteller.Play.WorldClockTest do
  use ExUnit.Case, async: true

  alias Storyteller.Play.WorldClock

  test "keeps Spanish and French date labels readable across midnight" do
    spanish = %{"date" => "12 de octubre de 2026", "time" => "11:30 p.m."}

    assert WorldClock.advance(spanish, spanish, 60) == %{
             "date" => "13 de octubre de 2026",
             "time" => "12:30 a.m."
           }

    french = %{"date" => "12 octobre 2026", "time" => "23:30"}

    assert WorldClock.advance(french, french, 60) == %{
             "date" => "13 octobre 2026",
             "time" => "00:30"
           }
  end

  test "leaves free-form clocks and ambiguous midnight dates untouched" do
    relative_time = %{"date" => "Tomorrow", "time" => "Late evening"}

    assert WorldClock.advance(relative_time, relative_time, 60) == relative_time

    unknown_date = %{"date" => "The harvest festival", "time" => "11:30 p.m."}

    assert WorldClock.advance(unknown_date, unknown_date, 60) == unknown_date
  end
end
