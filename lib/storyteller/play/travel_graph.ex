defmodule Storyteller.Play.TravelGraph do
  @moduledoc """
  Pure validation and shortest-route calculations for a campaign's place graph.

  Accepted proposals can add or revise edges, and the same atomic proposal may
  use its normalized edges to validate a move. Durations are computed from that
  graph; model-supplied duration values are never trusted.
  """

  @max_connections 1_000
  @max_changes 50
  @max_scene_relevance 1_000
  @max_reason_length 1_000
  @max_duration_minutes 10_080

  @doc "Normalizes connection operations against campaign places and existing edges."
  def validate_changes(changes, places, existing_connections)
      when is_list(changes) and length(changes) <= @max_changes do
    with {:ok, place_info} <- normalize_places(places),
         {:ok, existing} <- normalize_connections(existing_connections, place_info),
         true <- map_size(existing) <= @max_connections do
      Enum.reduce_while(changes, {:ok, [], existing, MapSet.new()}, fn change,
                                                                       {:ok, normalized, graph,
                                                                        touched} ->
        case normalize_change(change, place_info, graph, touched) do
          {:ok, operation, next_graph, next_touched} ->
            {:cont, {:ok, normalized ++ [operation], next_graph, next_touched}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, normalized, _graph, _touched} -> {:ok, normalized}
        {:error, _reason} = error -> error
      end
    else
      false -> {:error, :too_many_connections}
      {:error, _reason} = error -> error
    end
  end

  def validate_changes(_changes, _places, _existing_connections),
    do: {:error, :invalid_connection_changes}

  @doc "Adds route durations and requires trusted authorization for first placement from an unknown origin."
  def validate_movements(
        changes,
        characters,
        connections,
        player_place_id,
        first_placement_ids \\ MapSet.new()
      ) do
    with {:ok, graph} <- normalize_connections(connections),
         {:ok, locations, active_duties} <- normalize_character_locations(characters) do
      Enum.reduce_while(changes, {:ok, [], locations, active_duties}, fn
        %{"type" => "move_character", "speaker_id" => speaker_id, "place_id" => place_id} = move,
        {:ok, accepted, current_locations, duties} ->
          current_place_id = Map.get(current_locations, speaker_id)
          current_scene_id = Map.get(current_locations, "player", player_place_id)

          result =
            case Map.get(duties, speaker_id) do
              %{place_id: duty_place_id} when duty_place_id != place_id ->
                {:error, :active_duty}

              _ ->
                movement_duration(
                  current_place_id,
                  place_id,
                  speaker_id,
                  current_scene_id,
                  graph,
                  first_placement_ids
                )
            end

          case result do
            {:ok, minutes} ->
              normalized = Map.put(move, "travel_minutes", minutes)

              {:cont,
               {:ok, accepted ++ [normalized], Map.put(current_locations, speaker_id, place_id),
                duties}}

            {:error, _reason} = error ->
              {:halt, error}
          end

        change, {:ok, accepted, current_locations, duties} ->
          {:cont, {:ok, accepted ++ [change], current_locations, duties}}
      end)
      |> case do
        {:ok, validated, locations, _duties} -> {:ok, validated, locations}
        {:error, _reason} = error -> error
      end
    end
  end

  @doc "Applies normalized edge proposals in memory for same-turn route validation."
  def merge_changes(connections, changes) do
    with {:ok, graph} <- normalize_connections(connections),
         {:ok, merged} <- apply_normalized_changes(graph, changes) do
      {:ok, Map.values(merged)}
    end
  end

  @doc "Returns whether every public NPC line is spoken from the player's final scene."
  def public_lines_in_scene?(lines, locations, player_place_id) when is_list(lines) do
    Enum.all?(lines, fn line ->
      speaker_id = get(line, :speaker_id)

      speaker_id == "player" or is_nil(player_place_id) or
        (is_binary(player_place_id) and Map.get(locations, speaker_id) == player_place_id)
    end)
  end

  @doc "Finds the shortest undirected path duration, or `:error` when disconnected."
  def shortest_minutes(start_id, destination_id, _connections) when start_id == destination_id,
    do: {:ok, 0}

  def shortest_minutes(start_id, destination_id, connections) do
    with {:ok, graph} <- normalize_connections(connections) do
      shortest_minutes_in_graph(start_id, destination_id, graph)
    end
  end

  @doc "Returns the canonical shortest path as stable place IDs and its computed duration."
  def shortest_route(start_id, destination_id, _connections) when start_id == destination_id,
    do: {:ok, %{travel_minutes: 0, place_ids: [start_id]}}

  def shortest_route(start_id, destination_id, connections) do
    with {:ok, graph} <- normalize_connections(connections) do
      shortest_route_in_graph(start_id, destination_id, graph)
    end
  end

  @doc "Returns true when the edge touches a place relevant to the current scene."
  def relevant_to_places?(connection, place_ids) do
    a = get(connection, :place_a_id)
    b = get(connection, :place_b_id)
    MapSet.member?(place_ids, a) or MapSet.member?(place_ids, b)
  end

  def connection_pair(place_a_id, place_b_id) do
    if place_a_id <= place_b_id,
      do: {place_a_id, place_b_id},
      else: {place_b_id, place_a_id}
  end

  defp movement_duration(
         nil,
         _place_id,
         speaker_id,
         _player_place_id,
         _graph,
         first_placement_ids
       ) do
    if MapSet.member?(first_placement_ids, speaker_id),
      do: {:ok, 0},
      else: {:error, :unknown_origin}
  end

  defp movement_duration(
         current_id,
         place_id,
         _speaker_id,
         _player_place_id,
         _graph,
         _first_placement_ids
       )
       when current_id == place_id,
       do: {:ok, 0}

  defp movement_duration(
         current_id,
         place_id,
         "player",
         _player_place_id,
         graph,
         _first_placement_ids
       ) do
    public_graph =
      graph
      |> Map.values()
      |> Enum.filter(&(&1["visibility"] == "public"))
      |> Map.new(fn edge ->
        {connection_pair(edge["place_a_id"], edge["place_b_id"]), edge}
      end)

    shortest_minutes_in_graph(current_id, place_id, public_graph)
  end

  defp movement_duration(
         current_id,
         place_id,
         _speaker_id,
         _player_place_id,
         graph,
         _first_placement_ids
       ),
       do: shortest_minutes_in_graph(current_id, place_id, graph)

  defp normalize_change(change, places, graph, touched) when is_map(change) do
    case get(change, :type) do
      "create_connection" -> normalize_create(change, places, graph, touched)
      "update_connection" -> normalize_update(change, places, graph, touched)
      _ -> {:error, :invalid_connection_operation}
    end
  end

  defp normalize_change(_change, _places, _graph, _touched),
    do: {:error, :invalid_connection_operation}

  defp normalize_create(change, places, graph, touched) do
    with :ok <-
           only_keys(
             change,
             ~w(type place_a_id place_b_id travel_minutes scene_relevance visibility reason)
           ),
         {:ok, a} <- required_id(change, :place_a_id),
         {:ok, b} <- required_id(change, :place_b_id),
         true <- a != b,
         {:ok, place_a} <- Map.fetch(places, a),
         {:ok, place_b} <- Map.fetch(places, b),
         {:ok, minutes} <- duration(get(change, :travel_minutes)),
         {:ok, relevance} <- optional_text(get(change, :scene_relevance), @max_scene_relevance),
         {:ok, visibility} <- visibility(get(change, :visibility)),
         :ok <- connection_visibility(visibility, place_a.visibility, place_b.visibility),
         {:ok, reason} <- required_text(get(change, :reason), @max_reason_length),
         pair = connection_pair(a, b),
         false <- Map.has_key?(graph, pair),
         false <- MapSet.member?(touched, pair),
         true <- map_size(graph) < @max_connections do
      {place_a_id, place_b_id} = pair

      operation = %{
        "type" => "create_connection",
        "place_a_id" => place_a_id,
        "place_b_id" => place_b_id,
        "travel_minutes" => minutes,
        "visibility" => visibility,
        "reason" => reason
      }

      operation = maybe_put(operation, "scene_relevance", relevance)

      edge =
        Map.take(operation, ~w(place_a_id place_b_id travel_minutes visibility scene_relevance))

      {:ok, operation, Map.put(graph, pair, edge), MapSet.put(touched, pair)}
    else
      true -> {:error, :duplicate_connection}
      false -> {:error, :too_many_connections}
      :error -> {:error, :place_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_update(change, places, graph, touched) do
    with :ok <-
           only_keys(change, ~w(type place_a_id place_b_id travel_minutes scene_relevance reason)),
         {:ok, a} <- required_id(change, :place_a_id),
         {:ok, b} <- required_id(change, :place_b_id),
         true <- a != b,
         {:ok, _place_a} <- Map.fetch(places, a),
         {:ok, _place_b} <- Map.fetch(places, b),
         pair = connection_pair(a, b),
         {:ok, current} <- Map.fetch(graph, pair),
         false <- MapSet.member?(touched, pair),
         {:ok, minutes} <- optional_duration(get(change, :travel_minutes)),
         {:ok, relevance} <- optional_text(get(change, :scene_relevance), @max_scene_relevance),
         true <- not is_nil(minutes) or not is_nil(relevance),
         {:ok, reason} <- required_text(get(change, :reason), @max_reason_length) do
      operation = %{
        "type" => "update_connection",
        "place_a_id" => elem(pair, 0),
        "place_b_id" => elem(pair, 1),
        "visibility" => current["visibility"],
        "reason" => reason
      }

      operation = maybe_put(operation, "travel_minutes", minutes)
      operation = maybe_put(operation, "scene_relevance", relevance)

      edge =
        current
        |> maybe_put("travel_minutes", minutes)
        |> maybe_put("scene_relevance", relevance)

      {:ok, operation, Map.put(graph, pair, edge), MapSet.put(touched, pair)}
    else
      true -> {:error, :connection_already_changed}
      false -> {:error, :empty_connection_update}
      :error -> {:error, :connection_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_places(places) when is_list(places) and length(places) <= 5_000 do
    Enum.reduce_while(places, {:ok, %{}}, fn place, {:ok, acc} ->
      with {:ok, id} <- required_id(place, :place_id),
           {:ok, visibility} <- visibility(get(place, :visibility)),
           false <- Map.has_key?(acc, id) do
        {:cont, {:ok, Map.put(acc, id, %{visibility: visibility})}}
      else
        true -> {:halt, {:error, :duplicate_place_id}}
        _ -> {:halt, {:error, :invalid_places}}
      end
    end)
  end

  defp normalize_places(_), do: {:error, :invalid_places}

  defp normalize_connections(connections, places) do
    with {:ok, edges} <- normalize_connections(connections) do
      if Enum.all?(Map.values(edges), fn edge ->
           Map.has_key?(places, edge["place_a_id"]) and Map.has_key?(places, edge["place_b_id"])
         end),
         do: {:ok, edges},
         else: {:error, :invalid_connections}
    end
  end

  defp normalize_connections(connections)
       when is_list(connections) and length(connections) <= @max_connections do
    Enum.reduce_while(connections, {:ok, %{}}, fn connection, {:ok, acc} ->
      with {:ok, a} <- required_id(connection, :place_a_id),
           {:ok, b} <- required_id(connection, :place_b_id),
           true <- a != b,
           {:ok, minutes} <- duration(get(connection, :travel_minutes)),
           pair = connection_pair(a, b),
           false <- Map.has_key?(acc, pair) do
        normalized = %{
          "place_a_id" => elem(pair, 0),
          "place_b_id" => elem(pair, 1),
          "travel_minutes" => minutes,
          "visibility" => visibility_value(get(connection, :visibility)),
          "scene_relevance" => get(connection, :scene_relevance)
        }

        {:cont, {:ok, Map.put(acc, pair, normalized)}}
      else
        true -> {:halt, {:error, :duplicate_connection}}
        _ -> {:halt, {:error, :invalid_connections}}
      end
    end)
  end

  defp normalize_connections(_), do: {:error, :invalid_connections}

  defp normalize_character_locations(characters) when is_list(characters) do
    Enum.reduce_while(characters, {:ok, %{}}, fn character, {:ok, acc} ->
      speaker_id = get(character, :speaker_id)
      place_id = get(character, :current_place_id)

      if is_binary(speaker_id) and (is_nil(place_id) or is_binary(place_id)) and
           not Map.has_key?(acc, speaker_id) do
        normalized = Map.put(acc, speaker_id, place_id)
        {:cont, {:ok, normalized}}
      else
        {:halt, {:error, :invalid_characters}}
      end
    end)
    |> case do
      {:ok, locations} ->
        duties =
          characters
          |> Enum.reduce(%{}, fn character, acc ->
            speaker_id = get(character, :speaker_id)
            duty_name = get(character, :duty_name)
            duty_place_id = get(character, :duty_place_id)

            if is_binary(duty_name) and duty_name != "" and is_binary(duty_place_id) do
              Map.put(acc, speaker_id, %{name: duty_name, place_id: duty_place_id})
            else
              acc
            end
          end)

        {:ok, locations, duties}

      error ->
        error
    end
  end

  defp normalize_character_locations(_), do: {:error, :invalid_characters}

  defp apply_normalized_changes(graph, changes) when is_list(changes) do
    Enum.reduce_while(changes, {:ok, graph}, fn change, {:ok, acc} ->
      pair = connection_pair(get(change, :place_a_id), get(change, :place_b_id))
      current = Map.get(acc, pair)

      case get(change, :type) do
        "create_connection" ->
          if current do
            {:halt, {:error, :duplicate_connection}}
          else
            {:cont,
             {:ok,
              Map.put(acc, pair, %{
                "place_a_id" => elem(pair, 0),
                "place_b_id" => elem(pair, 1),
                "travel_minutes" => get(change, :travel_minutes),
                "scene_relevance" => get(change, :scene_relevance),
                "visibility" => get(change, :visibility)
              })}}
          end

        "update_connection" when is_map(current) ->
          updated =
            current
            |> maybe_put("travel_minutes", get(change, :travel_minutes))
            |> maybe_put("scene_relevance", get(change, :scene_relevance))

          {:cont, {:ok, Map.put(acc, pair, updated)}}

        "update_connection" ->
          {:halt, {:error, :connection_not_found}}

        _ ->
          {:halt, {:error, :invalid_connection_operation}}
      end
    end)
  end

  defp apply_normalized_changes(_graph, _changes), do: {:error, :invalid_connection_changes}

  defp shortest_minutes_in_graph(start_id, destination_id, graph) do
    adjacency =
      Enum.reduce(graph, %{}, fn {_pair, edge}, acc ->
        a = edge["place_a_id"]
        b = edge["place_b_id"]
        minutes = edge["travel_minutes"]

        acc
        |> Map.update(a, [{b, minutes}], &[{b, minutes} | &1])
        |> Map.update(b, [{a, minutes}], &[{a, minutes} | &1])
      end)

    dijkstra(start_id, destination_id, adjacency, %{start_id => 0}, MapSet.new())
  end

  defp shortest_route_in_graph(start_id, destination_id, graph) do
    adjacency =
      Enum.reduce(graph, %{}, fn {_pair, edge}, acc ->
        a = edge["place_a_id"]
        b = edge["place_b_id"]
        minutes = edge["travel_minutes"]

        acc
        |> Map.update(a, [{b, minutes}], &[{b, minutes} | &1])
        |> Map.update(b, [{a, minutes}], &[{a, minutes} | &1])
      end)

    dijkstra_route(
      start_id,
      destination_id,
      adjacency,
      %{start_id => 0},
      %{start_id => [start_id]},
      MapSet.new()
    )
  end

  defp dijkstra_route(destination_id, destination_id, _adjacency, distances, paths, _visited) do
    {:ok,
     %{
       travel_minutes: Map.fetch!(distances, destination_id),
       place_ids: Map.fetch!(paths, destination_id)
     }}
  end

  defp dijkstra_route(current, destination_id, adjacency, distances, paths, visited) do
    current_distance = Map.fetch!(distances, current)

    {next_distances, next_paths} =
      Enum.reduce(Map.get(adjacency, current, []), {distances, paths}, fn {neighbor, weight},
                                                                          {dist_acc, path_acc} ->
        candidate = current_distance + weight
        existing = Map.get(dist_acc, neighbor, :infinity)

        if MapSet.member?(visited, neighbor) or candidate >= existing do
          {dist_acc, path_acc}
        else
          {Map.put(dist_acc, neighbor, candidate),
           Map.put(path_acc, neighbor, Map.fetch!(paths, current) ++ [neighbor])}
        end
      end)

    next_visited = MapSet.put(visited, current)

    case next_distances
         |> Enum.reject(fn {node, _distance} -> MapSet.member?(next_visited, node) end)
         |> Enum.min_by(fn {node, distance} -> {distance, node} end, fn -> nil end) do
      {next, _distance} ->
        dijkstra_route(next, destination_id, adjacency, next_distances, next_paths, next_visited)

      nil ->
        {:error, :unconnected_move}
    end
  end

  defp dijkstra(destination_id, destination_id, _adjacency, distances, _visited),
    do: {:ok, Map.fetch!(distances, destination_id)}

  defp dijkstra(current, destination_id, adjacency, distances, visited) do
    current_distance = Map.fetch!(distances, current)

    next_distances =
      Enum.reduce(Map.get(adjacency, current, []), distances, fn {neighbor, weight}, acc ->
        candidate = current_distance + weight

        if MapSet.member?(visited, neighbor) or candidate >= Map.get(acc, neighbor, :infinity),
          do: acc,
          else: Map.put(acc, neighbor, candidate)
      end)

    next_visited = MapSet.put(visited, current)

    case next_distances
         |> Enum.reject(fn {node, _distance} -> MapSet.member?(next_visited, node) end)
         |> Enum.min_by(fn {node, distance} -> {distance, node} end, fn -> nil end) do
      {next, _distance} -> dijkstra(next, destination_id, adjacency, next_distances, next_visited)
      nil -> {:error, :unconnected_move}
    end
  end

  defp required_id(map, key) do
    case get(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value != "" and String.length(value) <= 100 and
             Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, value),
           do: {:ok, value},
           else: {:error, :invalid_id}

      _ ->
        {:error, :invalid_id}
    end
  end

  defp duration(value) when is_integer(value) and value >= 1 and value <= @max_duration_minutes,
    do: {:ok, value}

  defp duration(_), do: {:error, :invalid_duration}

  defp optional_duration(nil), do: {:ok, nil}
  defp optional_duration(value), do: duration(value)

  defp visibility("public"), do: {:ok, "public"}
  defp visibility("gm_private"), do: {:ok, "gm_private"}
  defp visibility(:public), do: {:ok, "public"}
  defp visibility(:gm_private), do: {:ok, "gm_private"}
  defp visibility(_), do: {:error, :invalid_visibility}

  defp visibility_value(value) do
    case visibility(value) do
      {:ok, normalized} -> normalized
      _ -> "public"
    end
  end

  defp connection_visibility("public", "gm_private", _),
    do: {:error, :private_place_connection_cannot_be_public}

  defp connection_visibility("public", _, "gm_private"),
    do: {:error, :private_place_connection_cannot_be_public}

  defp connection_visibility(_, _, _), do: :ok

  defp required_text(value, max_length) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= max_length,
      do: {:ok, value},
      else: {:error, :invalid_text}
  end

  defp required_text(_, _), do: {:error, :invalid_text}

  defp optional_text(nil, _max_length), do: {:ok, nil}

  defp optional_text(value, max_length) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= max_length,
      do: {:ok, value},
      else: {:error, :invalid_text}
  end

  defp optional_text(_, _), do: {:error, :invalid_text}

  defp only_keys(map, allowed) do
    keys = Enum.map(Map.keys(map), &normalize_key/1)

    if Enum.all?(keys, &(&1 in allowed)) and length(Enum.uniq(keys)) == length(keys),
      do: :ok,
      else: {:error, :unknown_key}
  end

  defp get(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get(_map, _key), do: nil

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
