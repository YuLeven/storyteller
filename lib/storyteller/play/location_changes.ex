defmodule Storyteller.Play.LocationChanges do
  @moduledoc """
  Validates proposed place creation and character movement operations.

  Validation is all-or-nothing. The returned operations are normalized in order,
  so a place created earlier in the same list can be used by a later move.
  This module is pure; callers decide when to persist the validated operations.
  """

  @max_places 200
  @max_changes 50
  @max_id_length 100
  @max_name_length 160
  @max_text_length 2_000
  @max_reason_length 1_000
  @max_fact_nodes 256
  @max_fact_depth 8

  @doc "Validates changes against current places and campaign character IDs."
  def validate(changes, places, valid_speaker_ids) do
    with {:ok, speakers} <- normalize_speaker_ids(valid_speaker_ids),
         {:ok, known_places} <- normalize_places(places),
         :ok <- validate_change_list(changes),
         {:ok, normalized} <- normalize_changes(changes, known_places, speakers) do
      {:ok, normalized}
    end
  end

  defp normalize_speaker_ids(ids) when is_list(ids) do
    with {:ok, normalized} <- normalize_ids(ids) do
      {:ok, MapSet.new(normalized)}
    else
      :error -> {:error, :invalid_speaker_ids}
    end
  end

  defp normalize_speaker_ids(%MapSet{} = ids), do: normalize_speaker_ids(MapSet.to_list(ids))
  defp normalize_speaker_ids(ids) when is_map(ids), do: normalize_speaker_ids(Map.keys(ids))
  defp normalize_speaker_ids(_), do: {:error, :invalid_speaker_ids}

  defp normalize_ids(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case normalize_id(id) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :error -> :error
    end
  end

  defp normalize_places(places) when is_list(places) and length(places) <= @max_places do
    Enum.reduce_while(places, {:ok, %{}}, fn place, {:ok, acc} ->
      with {:ok, id} <- required_id(place, "place_id"),
           {:ok, visibility} <- visibility(get(place, "visibility")),
           false <- Map.has_key?(acc, id) do
        {:cont, {:ok, Map.put(acc, id, visibility)}}
      else
        true -> {:halt, {:error, :duplicate_place_id}}
        _ -> {:halt, {:error, :invalid_places}}
      end
    end)
  end

  defp normalize_places(_), do: {:error, :invalid_places}

  defp validate_change_list(changes) when is_list(changes) and length(changes) <= @max_changes,
    do: :ok

  defp validate_change_list(_), do: {:error, :invalid_changes}

  defp normalize_changes(changes, known_places, speakers) do
    Enum.reduce_while(changes, {:ok, [], known_places}, fn change, {:ok, acc, places} ->
      case normalize_change(change, places, speakers) do
        {:ok, normalized, updated_places} ->
          {:cont, {:ok, [normalized | acc], updated_places}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed, _places} -> {:ok, Enum.reverse(reversed)}
      {:error, _} = error -> error
    end
  end

  defp normalize_change(change, places, speakers) when is_map(change) do
    case get(change, "type") do
      "create_place" -> normalize_create_place(change, places)
      "move_character" -> normalize_move_character(change, places, speakers)
      _ -> {:error, :invalid_operation}
    end
  end

  defp normalize_change(_, _places, _speakers), do: {:error, :invalid_operation}

  defp normalize_create_place(change, places) do
    with :ok <- only_keys(change, ~w(type place reason)),
         {:ok, reason} <- required_text(change, "reason", @max_reason_length),
         {:ok, place} <- normalize_place(get(change, "place")),
         false <- Map.has_key?(places, place["place_id"]),
         true <- map_size(places) < @max_places do
      normalized = %{
        "type" => "create_place",
        "place" => place,
        "reason" => reason,
        "visibility" => place["visibility"]
      }

      {:ok, normalized, Map.put(places, place["place_id"], place["visibility"])}
    else
      true -> {:error, :duplicate_place_id}
      false -> {:error, :too_many_places}
      {:error, _} = error -> error
    end
  end

  defp normalize_move_character(change, places, speakers) do
    with :ok <- only_keys(change, ~w(type speaker_id place_id reason)),
         {:ok, speaker_id} <- required_id(change, "speaker_id"),
         true <- MapSet.member?(speakers, speaker_id),
         {:ok, place_id} <- required_id(change, "place_id"),
         {:ok, destination_visibility} <- Map.fetch(places, place_id),
         :ok <- player_destination_visibility(speaker_id, destination_visibility),
         {:ok, reason} <- required_text(change, "reason", @max_reason_length) do
      {:ok,
       %{
         "type" => "move_character",
         "speaker_id" => speaker_id,
         "place_id" => place_id,
         "reason" => reason,
         "visibility" => destination_visibility
       }, places}
    else
      false -> {:error, :unknown_character}
      :error -> {:error, :place_not_found}
      {:error, _} = error -> error
    end
  end

  defp normalize_place(place) when is_map(place) do
    with :ok <- only_keys(place, ~w(place_id name description visibility facts)),
         {:ok, place_id} <- required_id(place, "place_id"),
         {:ok, name} <- required_text(place, "name", @max_name_length),
         {:ok, description} <- optional_text(place, "description", @max_text_length),
         {:ok, visibility} <- visibility(get(place, "visibility")),
         {:ok, facts} <- normalize_facts(get(place, "facts")) do
      normalized = %{
        "place_id" => place_id,
        "name" => name,
        "visibility" => visibility,
        "facts" => facts
      }

      {:ok, maybe_put(normalized, "description", description)}
    end
  end

  defp normalize_place(_), do: {:error, :invalid_place}

  defp normalize_facts(nil), do: {:ok, %{}}

  defp normalize_facts(facts) when is_map(facts) do
    case validate_json_value(facts, 0, 0) do
      {:ok, _nodes} -> {:ok, facts}
      :error -> {:error, :invalid_facts}
    end
  end

  defp normalize_facts(_), do: {:error, :invalid_facts}

  defp validate_json_value(_value, depth, _nodes) when depth > @max_fact_depth, do: :error
  defp validate_json_value(_value, _depth, nodes) when nodes >= @max_fact_nodes, do: :error

  defp validate_json_value(value, _depth, nodes) when is_binary(value),
    do: if(String.valid?(value), do: {:ok, nodes + 1}, else: :error)

  defp validate_json_value(value, _depth, nodes)
       when is_integer(value) or is_float(value) or is_boolean(value),
       do: {:ok, nodes + 1}

  defp validate_json_value(nil, _depth, nodes), do: {:ok, nodes + 1}

  defp validate_json_value(value, depth, nodes) when is_list(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn item, {:ok, count} ->
      case validate_json_value(item, depth + 1, count) do
        {:ok, updated_count} -> {:cont, {:ok, updated_count}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp validate_json_value(value, depth, nodes) when is_map(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn {key, item}, {:ok, count} ->
      if is_binary(key) and String.valid?(key) do
        case validate_json_value(item, depth + 1, count) do
          {:ok, updated_count} -> {:cont, {:ok, updated_count}}
          :error -> {:halt, :error}
        end
      else
        {:halt, :error}
      end
    end)
  end

  defp validate_json_value(_value, _depth, _nodes), do: :error

  defp required_id(map, key) do
    case get(map, key) do
      value when is_binary(value) ->
        case normalize_id(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, :invalid_id}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  defp normalize_id(value) when is_binary(value) do
    if String.valid?(value) do
      id = String.trim(value)

      if id != "" and String.length(id) <= @max_id_length and
           Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, id),
         do: {:ok, id},
         else: :error
    else
      :error
    end
  end

  defp normalize_id(_), do: :error

  defp required_text(map, key, max_length) do
    case get(map, key) do
      value when is_binary(value) ->
        if String.valid?(value) do
          text = String.trim(value)

          if text != "" and String.length(text) <= max_length,
            do: {:ok, text},
            else: {:error, :invalid_text}
        else
          {:error, :invalid_text}
        end

      _ ->
        {:error, :invalid_text}
    end
  end

  defp optional_text(map, key, max_length) do
    case get(map, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if String.valid?(value) do
          text = String.trim(value)

          if text != "" and String.length(text) <= max_length,
            do: {:ok, text},
            else: {:error, :invalid_text}
        else
          {:error, :invalid_text}
        end

      _ ->
        {:error, :invalid_text}
    end
  end

  defp visibility("public"), do: {:ok, "public"}
  defp visibility("gm_private"), do: {:ok, "gm_private"}
  defp visibility(_), do: {:error, :invalid_visibility}

  defp player_destination_visibility("player", "gm_private"),
    do: {:error, :player_cannot_enter_private_place}

  defp player_destination_visibility(_speaker_id, _visibility), do: :ok

  defp only_keys(map, allowed) do
    keys = Enum.map(Map.keys(map), &normalize_key/1)

    if Enum.all?(keys, &(&1 in allowed)) and length(Enum.uniq(keys)) == length(keys),
      do: :ok,
      else: {:error, :unknown_key}
  end

  defp get(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, atom_key(key))
    end
  end

  defp atom_key("type"), do: :type
  defp atom_key("place"), do: :place
  defp atom_key("place_id"), do: :place_id
  defp atom_key("name"), do: :name
  defp atom_key("description"), do: :description
  defp atom_key("visibility"), do: :visibility
  defp atom_key("facts"), do: :facts
  defp atom_key("speaker_id"), do: :speaker_id
  defp atom_key("reason"), do: :reason
  defp atom_key(_), do: nil

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
