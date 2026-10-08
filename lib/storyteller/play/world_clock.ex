defmodule Storyteller.Play.WorldClock do
  @moduledoc false

  @months %{
    english:
      ~w(january february march april may june july august september october november december),
    spanish:
      ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre),
    french: [
      "janvier",
      "février",
      "mars",
      "avril",
      "mai",
      "juin",
      "juillet",
      "août",
      "septembre",
      "octobre",
      "novembre",
      "décembre"
    ]
  }

  @twelve_hour_time ~r/^\s*(\d{1,2}):(\d{2})(\s*)([ap])(\.?m\.?)\s*$/i
  @twenty_four_hour_time ~r/^\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*$/

  @doc """
  Advances parseable in-world date and time labels by canonical elapsed minutes.

  Free-form time labels are left alone; a failed parse never invents a clock
  reading. If a known time crosses midnight, a date must also be recognizable
  before either label is changed.
  """
  def advance(world, anchor, elapsed_minutes)
      when is_map(world) and is_map(anchor) and is_integer(elapsed_minutes) and
             elapsed_minutes > 0 do
    anchor_time = value(anchor, "time") || value(world, "time")
    anchor_date = value(anchor, "date") || value(world, "date")

    with time_label when is_binary(time_label) <- anchor_time,
         {:ok, time, time_style} <- parse_time(time_label),
         {advanced_time, day_offset} <- advance_time(time, elapsed_minutes),
         {:ok, advanced_date} <- advanced_date(anchor_date, day_offset) do
      world
      |> Map.put("time", format_time(advanced_time, time_style))
      |> put_date(advanced_date)
    else
      _ -> world
    end
  end

  def advance(world, _anchor, _elapsed_minutes), do: world

  defp value(map, key) do
    atom_key = String.to_existing_atom(key)
    Map.get(map, key) || Map.get(map, atom_key)
  end

  defp parse_time(label) do
    case parse_exact_time(label) do
      {:ok, _time, _style} = parsed ->
        parsed

      _error ->
        parse_suffixed_time(label)
    end
  end

  defp parse_suffixed_time(label) do
    case String.split(label, ",", parts: 2) do
      [clock_label, suffix] when suffix != "" ->
        with true <- String.trim(suffix) != "",
             {:ok, time, style} <- parse_exact_time(String.trim(clock_label)) do
          {:ok, time, {:suffixed, style, "," <> suffix}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_exact_time(label) do
    case Regex.run(@twelve_hour_time, label) do
      [_, hour_text, minute_text, spacing, meridiem, marker_tail] ->
        hour = String.to_integer(hour_text)
        minute = String.to_integer(minute_text)
        marker = String.downcase(meridiem)

        hour_24 = rem(hour, 12) + if(marker == "p", do: 12, else: 0)

        with {:ok, time} <- Time.new(hour_24, minute, 0) do
          {:ok, time,
           {:twelve_hour, byte_size(hour_text), spacing, String.upcase(meridiem) == meridiem,
            marker_tail}}
        end

      _ ->
        parse_twenty_four_hour_time(label)
    end
  end

  defp parse_twenty_four_hour_time(label) do
    case Regex.run(@twenty_four_hour_time, label) do
      [_, hour_text, minute_text] ->
        parse_24_hour_components(hour_text, minute_text, "00", false)

      [_, hour_text, minute_text, second_text] ->
        parse_24_hour_components(hour_text, minute_text, second_text, true)

      _ ->
        :error
    end
  end

  defp parse_24_hour_components(hour_text, minute_text, second_text, show_seconds?) do
    with {:ok, time} <-
           Time.new(
             String.to_integer(hour_text),
             String.to_integer(minute_text),
             String.to_integer(second_text)
           ) do
      {:ok, time, {:twenty_four_hour, byte_size(hour_text), show_seconds?}}
    end
  end

  defp advance_time(time, elapsed_minutes) do
    total_seconds = time.hour * 3_600 + time.minute * 60 + time.second + elapsed_minutes * 60
    day_offset = div(total_seconds, 86_400)
    seconds_in_day = rem(total_seconds, 86_400)
    hour = div(seconds_in_day, 3_600)
    minute = div(rem(seconds_in_day, 3_600), 60)
    second = rem(seconds_in_day, 60)

    {:ok, advanced_time} = Time.new(hour, minute, second, time.microsecond)
    {advanced_time, day_offset}
  end

  defp format_time(%Time{} = time, {:twelve_hour, hour_width, spacing, uppercase?, marker_tail}) do
    hour = if rem(time.hour, 12) == 0, do: 12, else: rem(time.hour, 12)
    marker = if time.hour < 12, do: "a", else: "p"
    marker = if uppercase?, do: String.upcase(marker), else: marker

    marker_tail =
      if uppercase?, do: String.upcase(marker_tail), else: String.downcase(marker_tail)

    "#{pad(hour, hour_width)}:#{pad(time.minute, 2)}#{spacing}#{marker}#{marker_tail}"
  end

  defp format_time(%Time{} = time, {:twenty_four_hour, hour_width, show_seconds?}) do
    base = "#{pad(time.hour, hour_width)}:#{pad(time.minute, 2)}"
    if show_seconds?, do: base <> ":#{pad(time.second, 2)}", else: base
  end

  defp format_time(%Time{} = time, {:suffixed, style, suffix}) do
    format_time(time, style) <> suffix
  end

  defp advanced_date(_date, 0), do: {:ok, nil}

  defp advanced_date(nil, _day_offset), do: {:ok, nil}

  defp advanced_date(date, day_offset) when is_binary(date) do
    case parse_date(date) do
      {:ok, {:relative_day, prefix, day}, :relative_day} ->
        {:ok, {:relative_day, prefix, day + day_offset}}

      {:ok, %Date{} = parsed_date, style} ->
        {:ok, {Date.add(parsed_date, day_offset), style}}

      error ->
        error
    end
  end

  defp advanced_date(_date, _day_offset), do: {:error, :date_not_recognized}

  defp parse_date(label) do
    case Regex.run(~r/^\s*(\d{4})-(\d{2})-(\d{2})\s*$/, label) do
      [_, year, month, day] ->
        new_date(year, month, day, :iso)

      _ ->
        parse_named_date(label)
    end
  end

  defp parse_named_date(label) do
    cond do
      match = Regex.run(~r/^\s*(\d{1,2})\s+de\s+([\p{L}]+)\s+de\s+(\d{4})\s*$/u, label) ->
        [_, day, month_name, year] = match
        new_named_date(year, month_name, day, :spanish)

      match = Regex.run(~r/^\s*(\d{1,2})\s+([\p{L}]+)\s+(\d{4})\s*$/u, label) ->
        [_, day, month_name, year] = match
        new_named_date(year, month_name, day, :day_month)

      match = Regex.run(~r/^\s*([\p{L}]+)\s+(\d{1,2}),?\s+(\d{4})\s*$/u, label) ->
        [_, month_name, day, year] = match
        new_named_date(year, month_name, day, :month_day)

      match = Regex.run(~r/^\s*(Day\s+)(\d+)\s*$/i, label) ->
        [_, prefix, day] = match
        {:ok, {:relative_day, prefix, String.to_integer(day)}, :relative_day}

      true ->
        {:error, :date_not_recognized}
    end
  end

  defp new_named_date(year, month_name, day, :spanish) do
    with {:spanish, month} <- find_month(month_name) do
      new_date(year, month, day, {:spanish, width(day), month_case(month_name)})
    else
      _ -> {:error, :month_not_recognized}
    end
  end

  defp new_named_date(year, month_name, day, date_order) do
    case find_month(month_name) do
      {language, month} ->
        style = {date_order, width(day), language, month_case(month_name)}
        new_date(year, month, day, style)

      nil ->
        {:error, :month_not_recognized}
    end
  end

  defp new_date(year, month, day, style) do
    case Date.new(String.to_integer(year), month, String.to_integer(day)) do
      {:ok, date} -> {:ok, date, style}
      _ -> {:error, :invalid_date}
    end
  end

  defp find_month(month_name) do
    normalized = String.downcase(month_name)

    Enum.find_value(@months, fn {language, names} ->
      case Enum.find_index(names, &(&1 == normalized)) do
        nil -> nil
        index -> {language, index + 1}
      end
    end)
  end

  defp format_date(date, :iso), do: Date.to_iso8601(date)

  defp format_date(date, {:spanish, day_width, month_case}) do
    day = pad(date.day, day_width)
    month = localized_month(:spanish, date.month, month_case)
    "#{day} de #{month} de #{date.year}"
  end

  defp format_date(date, {:day_month, day_width, language, month_case}) do
    day = pad(date.day, day_width)
    month = localized_month(language, date.month, month_case)
    "#{day} #{month} #{date.year}"
  end

  defp format_date(date, {:month_day, day_width, language, month_case}) do
    day = pad(date.day, day_width)
    month = localized_month(language, date.month, month_case)
    "#{month} #{day}, #{date.year}"
  end

  defp format_date(date, {:french_day_month, day_width, month_case}) do
    day = pad(date.day, day_width)
    month = localized_month(:french, date.month, month_case)
    "#{day} #{month} #{date.year}"
  end

  defp localized_month(language, month, casing) do
    month_name = @months |> Map.fetch!(language) |> Enum.at(month - 1)

    case casing do
      :upper -> String.upcase(month_name)
      :title -> String.capitalize(month_name)
      :lower -> month_name
    end
  end

  defp month_case(name) do
    cond do
      name == String.upcase(name) -> :upper
      name == String.downcase(name) -> :lower
      true -> :title
    end
  end

  defp put_date(world, nil), do: world
  defp put_date(world, {date, style}), do: Map.put(world, "date", format_date(date, style))

  defp put_date(world, {:relative_day, prefix, day}),
    do: Map.put(world, "date", prefix <> Integer.to_string(day))

  defp width(value) when is_binary(value), do: byte_size(value)
  defp pad(value, width), do: value |> Integer.to_string() |> String.pad_leading(width, "0")
end
