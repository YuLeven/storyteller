defmodule Storyteller.GM.TimePassageDuration do
  @moduledoc """
  Extracts one clear numeric span from a time-passage request.

  This deliberately handles only explicit, unambiguous numeric spans. Vague,
  qualified, compound, or conflicting spans remain the GM's choice.
  """

  @explicit_duration ~r/(?<![0-9,.])\b([0-9]+)\s*-?\s*(minutes?|minutos?|mins?|min|hours?|hrs?|hr|horas?|heures?|h|days?|dias?|jours?|weeks?|wks?|wk|semanas?|semaines?)\b/u
  @duration_range ~r/\b(?:between|entre)\s+[0-9]+\s+(?:and|et|y)\s+[0-9]+\s*-?\s*(?:minutes?|minutos?|mins?|min|hours?|hrs?|hr|horas?|heures?|h|days?|dias?|jours?|weeks?|wks?|wk|semanas?|semaines?)\b|\b[0-9]+\s*(?:-|–|—|to|through|a)\s*[0-9]+\s*-?\s*(?:minutes?|minutos?|mins?|min|hours?|hrs?|hr|horas?|heures?|h|days?|dias?|jours?|weeks?|wks?|wk|semanas?|semaines?)\b/u
  @non_exact_qualifier ~r/\b(?:about|around|roughly|approximately|within|up to|at most|at least|no more than|no less than|not more than|more than|less than|fewer than|over|under|or so|max(?:imum)?|minimum|mas o menos|aproximadamente|al menos|mas de|menos de|no mas de|como maximo|hasta|au moins|au plus|plus de|moins de|pas plus de|pas moins de|plus ou moins|environ|approximativement|a peu pres|jusqua)\b/u

  @doc "Returns the unambiguous requested minutes, `:none`, `:ambiguous`, or `{:error, :out_of_range}`."
  def parse(text, max_minutes)
      when is_binary(text) and is_integer(max_minutes) and max_minutes > 0 do
    normalized = normalize(text)

    if Regex.match?(@non_exact_qualifier, normalized) do
      :none
    else
      if Regex.match?(@duration_range, normalized) do
        :none
      else
        Regex.scan(@explicit_duration, normalized, capture: :all_but_first)
        |> Enum.map(&duration_match_minutes/1)
        |> resolve_matches(max_minutes)
      end
    end
  end

  def parse(_text, _max_minutes), do: :none

  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{M}/u, "")
    |> String.downcase()
  end

  defp duration_match_minutes([amount, unit]) do
    amount = String.to_integer(amount)
    amount * minutes_per(unit)
  end

  defp minutes_per(unit)
       when unit in ["minute", "minutes", "minuto", "minutos", "min", "mins"],
       do: 1

  defp minutes_per(unit)
       when unit in ["hour", "hours", "hr", "hrs", "h", "hora", "horas", "heure", "heures"],
       do: 60

  defp minutes_per(unit) when unit in ["day", "days", "dia", "dias", "jour", "jours"],
    do: 1_440

  defp minutes_per(unit)
       when unit in ["week", "weeks", "wk", "wks", "semana", "semanas", "semaine", "semaines"],
       do: 10_080

  defp resolve_matches(matches, max_minutes) do
    case matches do
      [] ->
        :none

      [minutes] when minutes > 0 and minutes <= max_minutes ->
        {:ok, minutes}

      [minutes] when minutes > max_minutes ->
        {:error, :out_of_range}

      [_minutes] ->
        :none

      _multiple_durations ->
        :ambiguous
    end
  end
end
