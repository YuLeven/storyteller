defmodule Storyteller.Play.VoiceGuidance do
  @moduledoc "Validated, GM-only delivery notes for a character's voice."

  @fields ~w(quirks accent_dialect cadence vocabulary mannerisms)
  @max_field_length 280
  @max_total_length 1_200

  def fields, do: @fields
  def max_field_length, do: @max_field_length
  def max_total_length, do: @max_total_length

  def character_count(guidance) when is_map(guidance) do
    Enum.reduce(guidance, 0, fn {key, value}, total ->
      if key_name(key) in @fields and is_binary(value) do
        total + String.length(String.trim(value))
      else
        total
      end
    end)
  end

  def character_count(_guidance), do: 0

  def normalize(nil), do: {:ok, %{}}

  def normalize(guidance) when is_map(guidance) do
    normalized_keys = Enum.map(Map.keys(guidance), &key_name/1)

    with true <- length(normalized_keys) == length(Enum.uniq(normalized_keys)),
         true <- Enum.all?(normalized_keys, &(&1 in @fields)),
         {:ok, values} <- normalize_values(guidance),
         true <-
           Enum.reduce(values, 0, fn {_key, value}, total -> total + String.length(value) end) <=
             @max_total_length do
      {:ok, values}
    else
      _ -> {:error, :invalid_voice_guidance}
    end
  end

  def normalize(_), do: {:error, :invalid_voice_guidance}

  defp normalize_values(guidance) do
    Enum.reduce_while(guidance, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = key_name(key)

      cond do
        not is_binary(value) or not String.valid?(value) ->
          {:halt, {:error, :invalid_voice_guidance}}

        String.length(String.trim(value)) > @max_field_length ->
          {:halt, {:error, :invalid_voice_guidance}}

        String.trim(value) == "" ->
          {:cont, {:ok, acc}}

        true ->
          {:cont, {:ok, Map.put(acc, key, String.trim(value))}}
      end
    end)
  end

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(_key), do: nil
end
