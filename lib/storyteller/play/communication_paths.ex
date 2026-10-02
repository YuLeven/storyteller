defmodule Storyteller.Play.CommunicationPaths do
  @moduledoc false

  @max_paths 80
  @max_changes 30
  @max_context_paths 12

  @doc "Validates public path changes against known canon and the validated current scene."
  def validate_changes(changes, paths, characters, dialogue, locations, speaker_visibility)
      when is_list(changes) and is_list(paths) and is_list(characters) and is_list(dialogue) and
             is_map(locations) and is_map(speaker_visibility) and length(changes) <= @max_changes do
    with {:ok, existing} <- normalize_paths(paths),
         {:ok, validated, _paths} <-
           Enum.reduce_while(changes, {:ok, [], existing}, fn change, {:ok, accepted, current} ->
             case validate_change(
                    change,
                    current,
                    characters,
                    dialogue,
                    locations,
                    speaker_visibility
                  ) do
               {:ok, normalized, next} ->
                 {:cont, {:ok, accepted ++ [normalized], next}}

               {:error, _reason} = error ->
                 {:halt, error}
             end
           end) do
      {:ok, validated}
    else
      {:error, _reason} = error -> error
    end
  end

  def validate_changes(_, _, _, _, _, _), do: {:error, :invalid_communication_path_changes}

  @doc "Validates remote public messages against a previously persisted active path."
  def validate_messages(messages, paths, characters)
      when is_list(messages) and is_list(paths) and is_list(characters) and
             length(messages) <= @max_changes do
    with {:ok, normalized_paths} <- normalize_paths(paths) do
      paths_by_id = normalized_paths

      known_speakers =
        characters
        |> Enum.filter(&(get(&1, :role) in [:gm, "gm"]))
        |> MapSet.new(&get(&1, :speaker_id))

      Enum.reduce_while(messages, {:ok, [], MapSet.new()}, fn message, {:ok, accepted, senders} ->
        case validate_message(message, paths_by_id, known_speakers, senders) do
          {:ok, normalized, next_senders} ->
            {:cont, {:ok, accepted ++ [normalized], next_senders}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, accepted, _senders} -> {:ok, accepted}
        error -> error
      end
    end
  end

  def validate_messages(_, _, _), do: {:error, :invalid_remote_messages}

  @doc "Applies already validated changes to the compact public state ledger."
  def apply_changes(paths, changes) when is_list(paths) and is_list(changes) do
    Enum.reduce(changes, paths, fn
      %{"type" => "establish"} = change, current ->
        current ++ [Map.take(change, ~w(path_id sender_id recipient_id channel endpoint status))]

      %{"type" => "deactivate", "path_id" => path_id}, current ->
        Enum.map(current, fn path ->
          if path["path_id"] == path_id, do: Map.put(path, "status", "inactive"), else: path
        end)
    end)
  end

  @doc "Returns the public active paths in stable, bounded context form."
  def active_context(paths, player_input \\ "")

  def active_context(paths, player_input) when is_list(paths) do
    with {:ok, normalized} <- normalize_paths(paths) do
      query_terms = context_terms(player_input)

      paths
      |> Enum.with_index()
      |> Enum.flat_map(fn {path, index} ->
        path_id = get(path, :path_id)

        case Map.get(normalized, path_id) do
          %{"status" => "active"} = normalized_path ->
            [{context_relevance(normalized_path, query_terms), index, normalized_path}]

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn {score, index, path} -> {-score, -index, path["path_id"]} end)
      |> Enum.take(@max_context_paths)
      |> Enum.map(fn {_score, _index, path} ->
        Map.take(path, ~w(path_id sender_id recipient_id channel endpoint))
      end)
    else
      _ -> []
    end
  end

  def active_context(_, _), do: []

  @doc "Validates a persisted path ledger, including state imported from a backup."
  def validate_ledger(paths, characters) when is_list(paths) and is_list(characters) do
    gm_speakers =
      characters
      |> Enum.filter(&(get(&1, :role) in [:gm, "gm"]))
      |> MapSet.new(&get(&1, :speaker_id))

    with {:ok, normalized} <- normalize_paths(paths),
         true <- Enum.all?(Map.values(normalized), &MapSet.member?(gm_speakers, &1["sender_id"])) do
      :ok
    else
      _ -> {:error, :invalid_communication_paths}
    end
  end

  def validate_ledger(_, _), do: {:error, :invalid_communication_paths}

  defp validate_change(change, paths, characters, dialogue, locations, speaker_visibility)
       when is_map(change) do
    case get(change, :type) do
      "establish" ->
        validate_establishment(change, paths, characters, dialogue, locations, speaker_visibility)

      "deactivate" ->
        validate_deactivation(change, paths)

      _ ->
        {:error, :invalid_communication_path_change}
    end
  end

  defp validate_change(_, _, _, _, _, _), do: {:error, :invalid_communication_path_change}

  defp validate_establishment(change, paths, characters, dialogue, locations, speaker_visibility) do
    with :ok <- only_keys(change, ~w(type path_id speaker_id channel endpoint basis_text reason)),
         {:ok, path_id} <- stable_id(get(change, :path_id)),
         {:ok, speaker_id} <- stable_id(get(change, :speaker_id)),
         {:ok, channel} <- required_text(get(change, :channel), 80),
         {:ok, endpoint} <- required_text(get(change, :endpoint), 180),
         {:ok, basis_text} <- required_text(get(change, :basis_text), 2_000),
         {:ok, reason} <- required_text(get(change, :reason), 300),
         true <- plainly_established?(basis_text, endpoint),
         true <- not Map.has_key?(paths, path_id),
         true <- map_size(paths) < @max_paths,
         true <- known_gm?(characters, speaker_id),
         true <- Map.get(speaker_visibility, speaker_id, :public) == :public,
         true <- same_scene?(locations, speaker_id),
         true <- Enum.any?(dialogue, &(&1.speaker_id == speaker_id and &1.text == basis_text)) do
      normalized = %{
        "type" => "establish",
        "path_id" => path_id,
        "sender_id" => speaker_id,
        "recipient_id" => "player",
        "channel" => channel,
        "endpoint" => endpoint,
        "status" => "active",
        "basis_text" => basis_text,
        "reason" => reason
      }

      path = Map.take(normalized, ~w(path_id sender_id recipient_id channel endpoint status))
      {:ok, normalized, Map.put(paths, path_id, path)}
    else
      false -> {:error, :invalid_communication_path_basis}
      {:error, _reason} = error -> error
    end
  end

  defp validate_deactivation(change, paths) do
    with :ok <- only_keys(change, ~w(type path_id reason)),
         {:ok, path_id} <- stable_id(get(change, :path_id)),
         {:ok, reason} <- required_text(get(change, :reason), 300),
         %{"status" => "active"} <- Map.get(paths, path_id) do
      {:ok, %{"type" => "deactivate", "path_id" => path_id, "reason" => reason},
       Map.put(paths, path_id, Map.put(Map.fetch!(paths, path_id), "status", "inactive"))}
    else
      _ -> {:error, :invalid_communication_path_change}
    end
  end

  defp validate_message(message, paths, known_speakers, used_senders) when is_map(message) do
    with :ok <- only_keys(message, ~w(speaker_id path_id text)),
         {:ok, speaker_id} <- stable_id(get(message, :speaker_id)),
         {:ok, path_id} <- stable_id(get(message, :path_id)),
         {:ok, text} <- required_text(get(message, :text), 2_000),
         true <- MapSet.member?(known_speakers, speaker_id),
         false <- MapSet.member?(used_senders, speaker_id),
         %{
           "sender_id" => ^speaker_id,
           "recipient_id" => "player",
           "status" => "active",
           "channel" => channel
         } <- Map.get(paths, path_id) do
      {:ok,
       %{
         speaker_id: speaker_id,
         path_id: path_id,
         channel: channel,
         text: text
       }, MapSet.put(used_senders, speaker_id)}
    else
      _ -> {:error, :invalid_remote_message}
    end
  end

  defp validate_message(_, _, _, _), do: {:error, :invalid_remote_message}

  defp normalize_paths(paths) when is_list(paths) and length(paths) <= @max_paths do
    Enum.reduce_while(paths, {:ok, %{}}, fn path, {:ok, acc} ->
      with true <- is_map(path),
           :ok <- only_keys(path, ~w(path_id sender_id recipient_id channel endpoint status)),
           {:ok, path_id} <- stable_id(get(path, :path_id)),
           {:ok, sender_id} <- stable_id(get(path, :sender_id)),
           "player" <- get(path, :recipient_id),
           {:ok, channel} <- required_text(get(path, :channel), 80),
           {:ok, endpoint} <- required_text(get(path, :endpoint), 180),
           status when status in ["active", "inactive"] <- get(path, :status),
           false <- Map.has_key?(acc, path_id) do
        normalized = %{
          "path_id" => path_id,
          "sender_id" => sender_id,
          "recipient_id" => "player",
          "channel" => channel,
          "endpoint" => endpoint,
          "status" => status
        }

        {:cont, {:ok, Map.put(acc, path_id, normalized)}}
      else
        _ -> {:halt, {:error, :invalid_communication_paths}}
      end
    end)
  end

  defp normalize_paths(_), do: {:error, :invalid_communication_paths}

  defp known_gm?(characters, speaker_id) do
    Enum.any?(characters, fn character ->
      get(character, :speaker_id) == speaker_id and get(character, :role) in [:gm, "gm"]
    end)
  end

  defp same_scene?(locations, speaker_id) do
    player_place = Map.get(locations, "player")
    is_binary(player_place) and Map.get(locations, speaker_id) == player_place
  end

  defp plainly_established?(basis_text, endpoint) do
    dialogue_words = words(basis_text)
    endpoint_words = words(endpoint)

    endpoint_words != [] and
      Enum.any?(Enum.chunk_every(dialogue_words, length(endpoint_words), 1, :discard), fn words ->
        words == endpoint_words
      end)
  end

  defp words(text) do
    Regex.scan(~r/[\p{L}\p{N}]+/u, String.downcase(text)) |> List.flatten()
  end

  defp context_terms(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> MapSet.new()
  end

  defp context_terms(_), do: MapSet.new()

  defp context_relevance(path, query_terms) do
    path_terms =
      [path["path_id"], path["sender_id"], path["channel"], path["endpoint"]]
      |> Enum.join(" ")
      |> context_terms()

    MapSet.intersection(path_terms, query_terms) |> MapSet.size()
  end

  defp stable_id(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= 100 and
         Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, value),
       do: {:ok, value},
       else: {:error, :invalid_communication_path}
  end

  defp stable_id(_), do: {:error, :invalid_communication_path}

  defp required_text(value, max_length) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= max_length,
      do: {:ok, value},
      else: {:error, :invalid_communication_path}
  end

  defp required_text(_, _), do: {:error, :invalid_communication_path}

  defp only_keys(map, allowed) do
    keys = Enum.map(Map.keys(map), &normalize_key/1)

    if Enum.all?(keys, &(&1 in allowed)) and length(Enum.uniq(keys)) == length(keys),
      do: :ok,
      else: {:error, :invalid_communication_path}
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_, _), do: nil

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_), do: nil
end
