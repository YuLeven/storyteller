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

    unparseable_clock = %{"date" => "24 October 1891", "time" => "around 04:44, before dawn"}

    assert WorldClock.advance(unparseable_clock, unparseable_clock, 6) == unparseable_clock

    unknown_date = %{"date" => "The harvest festival", "time" => "11:30 p.m."}

    assert WorldClock.advance(unknown_date, unknown_date, 60) == unknown_date
  end

  test "advances a 24-hour clock with a descriptive suffix and preserves the suffix" do
    clock = %{"date" => "24 October 1891", "time" => "04:44, minutes before dawn"}

    assert WorldClock.advance(clock, clock, 6) == %{
             "date" => "24 October 1891",
             "time" => "04:50, minutes before dawn"
           }
  end

  test "advances a suffixed 12-hour clock across midnight" do
    clock = %{"date" => "June 23, 2028", "time" => "11:54 p.m., just before the bell"}

    assert WorldClock.advance(clock, clock, 10) == %{
             "date" => "June 24, 2028",
             "time" => "12:04 a.m., just before the bell"
           }
  end
end
