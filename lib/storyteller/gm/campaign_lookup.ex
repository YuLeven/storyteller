defmodule Storyteller.GM.CampaignLookup do
  @moduledoc """
  Read-only, in-memory retrieval from an already assembled GM context.

  The lookup never queries persistence or a model provider. Callers pass the
  full context for the current turn; results are ranked against the supplied
  query and returned with their original public or GM-private scope intact.
  History is deliberately not indexed as canon.
  """

  @max_query_chars 160
  @max_records 5
  @max_result_bytes 6_000
  @max_record_bytes 1_200
  @categories ~w(any character place inventory objective world continuity memory panel)

  @private_keys ~w(
    gm_private_facts private_facts hidden_facts secret secrets gm_notes private_notes
    hidden_notes gm_instructions private_context hidden_context
  )

  @public_character_fields ~w(
    role status current_place_id current_place activity active_duty voice voice_guidance
    mannerisms personality description public_description occupation species relationship
    visible_facts public_facts traits pronouns
  )

  @private_character_fields ~w(
    gm_private_facts private_facts hidden_facts secrets secret gm_notes private_notes
    hidden_notes private_context hidden_context
  )

  @public_place_fields ~w(
    status description public_description facts public_facts features surroundings
    current_weather current_date
  )

  @private_place_fields ~w(
    gm_private_facts private_facts hidden_facts gm_notes private_notes hidden_notes
    secrets secret
  )

  @public_inventory_fields ~w(
    quantity amount count unit category owner_id holder_id status description properties
    condition location_id current_place_id
  )

  @private_inventory_fields ~w(
    gm_private_facts private_facts hidden_facts gm_notes private_notes secrets secret
  )

  @public_objective_fields ~w(
    status state title summary details description priority due_date current_place_id
    owner_id progress
  )

  @private_objective_fields ~w(
    gm_private_facts private_facts hidden_facts gm_notes private_notes secrets secret
    hidden_details
  )

  @public_panel_fields ~w(panel label type unit value status)
  @private_panel_fields ~w(gm_private_facts private_facts hidden_facts gm_notes private_notes)

  @doc "Returns the Responses API function-tool declaration for campaign retrieval."
  @spec tool_spec() :: map()
  def tool_spec do
    %{
      "type" => "function",
      "name" => "lookup_campaign_canon",
      "description" =>
        "Search the supplied campaign canon for a short name, place, item, person, or fact. " <>
          "Use this when a detail is not present in the current scene context. Results retain " <>
          "their public or GM-private scope. This tool searches only the current campaign context.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "A concise name, ID, or fact to find (1–160 characters)."
          },
          "category" => %{
            "type" => "string",
            "enum" => @categories,
            "description" => "Optional record category; defaults to any."
          }
        },
        "required" => ["query"],
        "additionalProperties" => false
      }
    }
  end

  @doc "Searches only `context` and returns a JSON-safe result no larger than 6,000 bytes."
  @spec execute(map(), map()) :: map()
  def execute(context, arguments) when is_map(context) and is_map(arguments) do
    with {:ok, query} <- read_query(arguments),
         {:ok, category} <- read_category(arguments) do
      query_terms = tokenize(query)

      ranked =
        context
        |> collect_records()
        |> Enum.filter(&(category == "any" or &1["category"] == category))
        |> Enum.map(&{&1, relevance(&1, query, query_terms)})
        |> Enum.filter(fn {_record, score} -> score > 0 end)
        |> Enum.sort_by(fn {record, score} -> {-score, record["_order"]} end)

      result(ranked)
    else
      {:error, message} -> %{"error" => message, "records" => [], "complete" => true}
    end
  end

  def execute(_context, _arguments),
    do: %{
      "error" => "A campaign context and query object are required.",
      "records" => [],
      "complete" => true
    }

  defp read_query(arguments) do
    query = get(arguments, "query")

    if is_binary(query) do
      query = String.trim(query)
      chars = String.length(query)

      if chars > 0 and chars <= @max_query_chars do
        {:ok, query}
      else
        {:error, "Query must contain 1–160 characters."}
      end
    else
      {:error, "A text query is required."}
    end
  end

  defp read_category(arguments) do
    case get(arguments, "category") do
      nil ->
        {:ok, "any"}

      category when is_atom(category) ->
        read_category(%{"category" => Atom.to_string(category)})

      category when is_binary(category) ->
        if category in @categories,
          do: {:ok, category},
          else: {:error, "Unknown campaign record category."}

      _ ->
        {:error, "Unknown campaign record category."}
    end
  end

  defp result(ranked) do
    matches = length(ranked)
    source_records = Enum.map(ranked, &elem(&1, 0))

    {records, dropped_for_size?} =
      source_records
      |> Enum.take(@max_records)
      |> Enum.reduce({[], false}, fn record, {kept, dropped?} ->
        record = Map.delete(record, "_order")
        candidate = kept ++ [record]

        if byte_size(Jason.encode!(result_map(candidate, matches, false, false))) <=
             @max_result_bytes do
          {candidate, dropped?}
        else
          {kept, true}
        end
      end)

    returned = length(records)
    matches_omitted? = matches > returned
    details_omitted? = Enum.any?(records, & &1["details_truncated"])

    final = result_map(records, matches, matches_omitted? or dropped_for_size?, details_omitted?)

    # Metadata is small and all record rows have already been byte-bounded. In
    # the unlikely event the envelope crosses the limit, remove the final row
    # until the complete encoded JSON response satisfies the contract.
    trim_to_byte_limit(final, matches)
  end

  defp result_map(records, matches, matches_omitted?, details_omitted?) do
    %{
      "records" => records,
      "completeness" => %{
        "complete" => not matches_omitted? and not details_omitted?,
        "matches_found" => matches,
        "records_returned" => length(records),
        "matches_omitted" => matches_omitted?,
        "details_omitted" => details_omitted?
      }
    }
  end

  defp trim_to_byte_limit(result, matches) do
    if byte_size(Jason.encode!(result)) <= @max_result_bytes do
      result
    else
      trim_records = Map.get(result, "records", [])
      completeness = Map.get(result, "completeness", %{})

      case trim_records do
        [_ | rest] ->
          result_map(rest, matches, true, Map.get(completeness, "details_omitted", false))
          |> trim_to_byte_limit(matches)

        [] ->
          result_map([], matches, matches > 0, false)
      end
    end
  end

  defp collect_records(context) do
    hidden_place_ids = private_place_ids(get(context, "places"))

    []
    |> collect_campaign(context)
    |> collect_characters(get(context, "characters"), hidden_place_ids)
    |> collect_scoped_list("place", get(context, "places"), &place_record/3)
    |> collect_travel(get(context, "travel_connections"))
    |> collect_scoped_list("inventory", get(context, "inventory"), &inventory_record/3)
    |> collect_scoped_list("objective", get(context, "objectives"), &objective_record/3)
    |> collect_world(get(context, "world"))
    |> collect_continuity(get(context, "continuity"))
    |> collect_memory(get(context, "memory"))
    |> collect_panels(get(context, "panels"))
    |> Enum.with_index()
    |> Enum.map(fn {record, index} -> Map.put(record, "_order", index) end)
  end

  defp collect_campaign(records, context) do
    campaign = get(context, "campaign")

    if is_map(campaign) do
      id = first(campaign, ~w(id campaign_id), "campaign")
      name = first(campaign, ~w(title name), "Campaign")

      records
      |> maybe_add(
        record(
          "continuity",
          id,
          name,
          "public",
          "campaign",
          campaign,
          ~w(title premise genre setting summary)
        )
      )
      |> maybe_add(
        record(
          "continuity",
          id,
          name,
          "gm_private",
          "campaign",
          campaign,
          ~w(gm_instructions continuity_notes private_notes hidden_context)
        )
      )
    else
      records
    end
  end

  defp collect_characters(records, characters, hidden_place_ids) when is_list(characters) do
    Enum.reduce(characters, records, fn character, acc ->
      if is_map(character) do
        id = first(character, ~w(speaker_id character_id id), "unknown-character")
        name = first(character, ~w(name display_name), to_string(id))

        declared_private? =
          private_visibility?(get(character, "visibility")) or
            private_visibility?(get(get(character, "current_place"), "visibility")) or
            MapSet.member?(hidden_place_ids, get(character, "current_place_id"))

        acc =
          if declared_private? do
            maybe_add(
              acc,
              record(
                "character",
                id,
                name,
                "gm_private",
                "character",
                character,
                @public_character_fields ++ @private_character_fields
              )
            )
          else
            maybe_add(
              acc,
              record(
                "character",
                id,
                name,
                "public",
                "character",
                character,
                @public_character_fields
              )
            )
            |> maybe_add(
              record(
                "character",
                id,
                name,
                "gm_private",
                "character",
                character,
                @private_character_fields
              )
            )
          end

        acc
      else
        acc
      end
    end)
  end

  defp collect_characters(records, _characters, _hidden_place_ids), do: records

  defp private_place_ids(places) when is_map(places) do
    places
    |> Enum.filter(fn {scope, _rows} -> private_visibility?(scope) end)
    |> Enum.flat_map(fn {_scope, rows} -> listify(rows) end)
    |> Enum.map(&get(&1, "place_id"))
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  defp private_place_ids(_places), do: MapSet.new()

  defp collect_scoped_list(records, _category, scoped, builder) when is_map(scoped) do
    Enum.reduce(scoped, records, fn {scope, rows}, acc ->
      visibility = scope_visibility(scope)

      rows
      |> listify()
      |> Enum.reduce(acc, fn row, inner ->
        case builder.(row, visibility, scope) do
          nil -> inner
          item -> maybe_add(inner, item)
        end
      end)
    end)
  end

  defp collect_scoped_list(records, _category, rows, builder) when is_list(rows) do
    Enum.reduce(rows, records, fn row, acc ->
      maybe_add(acc, builder.(row, "public", "public"))
    end)
  end

  defp collect_scoped_list(records, _category, _scoped, _builder), do: records

  defp place_record(row, default_visibility, _scope) when is_map(row) do
    id = first(row, ~w(place_id id key), "unknown-place")
    name = first(row, ~w(name title label), to_string(id))
    visibility = effective_visibility(row, default_visibility)

    fields =
      if visibility == "public" do
        @public_place_fields
      else
        @public_place_fields ++ @private_place_fields
      end

    record("place", id, name, visibility, "place", row, fields)
  end

  defp place_record(_, _, _), do: nil

  defp inventory_record(row, default_visibility, scope) when is_map(row) do
    id = first(row, ~w(id item_id key), "unknown-item")
    name = first(row, ~w(name label title), to_string(id))
    visibility = effective_visibility(row, default_visibility)

    fields =
      if visibility == "public" do
        @public_inventory_fields
      else
        @public_inventory_fields ++ @private_inventory_fields
      end

    record("inventory", id, name, visibility, to_string(scope), row, fields)
  end

  defp inventory_record(_, _, _), do: nil

  defp objective_record(row, default_visibility, scope) when is_map(row) do
    id = first(row, ~w(id objective_id key), "unknown-objective")
    name = first(row, ~w(title name label), to_string(id))
    visibility = effective_visibility(row, default_visibility)

    fields =
      if visibility == "public" do
        @public_objective_fields
      else
        @public_objective_fields ++ @private_objective_fields
      end

    record("objective", id, name, visibility, to_string(scope), row, fields)
  end

  defp objective_record(_, _, _), do: nil

  defp collect_world(records, world) when is_map(world) do
    Enum.reduce(world, records, fn {scope, values}, acc ->
      visibility = scope_visibility(scope)

      if is_map(values) do
        Enum.reduce(values, acc, fn {key, value}, inner ->
          row = %{"value" => value}

          maybe_add(
            inner,
            record("world", "world:#{key}", to_string(key), visibility, to_string(scope), row, [
              "value"
            ])
          )
        end)
      else
        acc
      end
    end)
  end

  defp collect_world(records, _), do: records

  defp collect_continuity(records, continuity) when is_map(continuity) do
    Enum.reduce(continuity, records, fn {scope, rows}, acc ->
      visibility = scope_visibility(scope)

      rows
      |> listify()
      |> Enum.reduce(acc, fn row, inner ->
        if is_map(row) do
          id = first(row, ~w(id fact_id event_id), "continuity-#{abs(:erlang.phash2(row))}")
          name = first(row, ~w(title name subject key), to_string(id))

          fields =
            if visibility == "public",
              do: ~w(status type summary description fact text current_place_id location_id),
              else:
                ~w(status type summary description fact text current_place_id location_id gm_private_facts private_facts hidden_facts)

          maybe_add(
            inner,
            record("continuity", id, name, visibility, to_string(scope), row, fields)
          )
        else
          inner
        end
      end)
    end)
  end

  defp collect_continuity(records, _), do: records

  defp collect_memory(records, memory) when is_map(memory) do
    Enum.reduce(memory, records, fn {scope, summary}, acc ->
      {visibility, group} =
        case to_string(scope) do
          "public_summary" -> {"public", "public"}
          "gm_private_summary" -> {"gm_private", "gm_private"}
          _ -> {scope_visibility(scope), to_string(scope)}
        end

      if is_binary(summary) and String.trim(summary) != "" do
        id = "memory:#{group}"

        maybe_add(
          acc,
          record("memory", id, "Campaign memory", visibility, group, %{"summary" => summary}, [
            "summary"
          ])
        )
      else
        acc
      end
    end)
  end

  defp collect_memory(records, _), do: records

  defp collect_panels(records, panels) when is_list(panels) do
    Enum.reduce(panels, records, fn panel, acc ->
      if is_map(panel) do
        id = first(panel, ~w(key id), "unknown-panel")
        name = first(panel, ~w(label name panel), to_string(id))
        visibility = effective_visibility(panel, "public")

        fields =
          if visibility == "public",
            do: @public_panel_fields,
            else: @public_panel_fields ++ @private_panel_fields

        maybe_add(acc, record("panel", id, name, visibility, "panel", panel, fields))
      else
        acc
      end
    end)
  end

  defp collect_panels(records, _), do: records

  defp collect_travel(records, travel) when is_map(travel) do
    Enum.reduce(travel, records, fn {scope, rows}, acc ->
      visibility = scope_visibility(scope)

      rows
      |> listify()
      |> Enum.reduce(acc, fn edge, inner ->
        if is_map(edge) do
          id = first(edge, ~w(path_id route_id id), "route:#{abs(:erlang.phash2(edge))}")
          from = first(edge, ~w(place_a_id from_place_id origin_id), "unknown-place")
          to = first(edge, ~w(place_b_id to_place_id destination_id), "unknown-place")
          name = "#{from} ↔ #{to}"

          fields =
            ~w(place_a_id place_b_id from_place_id to_place_id travel_minutes duration status)

          maybe_add(inner, record("place", id, name, visibility, to_string(scope), edge, fields))
        else
          inner
        end
      end)
    end)
  end

  defp collect_travel(records, _), do: records

  defp record(category, id, name, visibility, group, source, allowed_fields) do
    public_only? = visibility == "public"

    selected =
      allowed_fields
      |> Enum.uniq()
      |> Enum.reduce([], fn field, acc ->
        value = get(source, field)

        cond do
          is_nil(value) -> acc
          public_only? and private_key?(field) -> acc
          true -> acc ++ [{field, value}]
        end
      end)

    {fields, details_truncated?} = fit_fields(selected, id, name, category, visibility, group)

    %{
      "category" => category,
      "id" => short_text(id, 120),
      "name" => short_text(name, 120),
      "visibility" => visibility,
      "group" => short_text(group, 64),
      "fields" => fields,
      "details_truncated" => details_truncated?
    }
  end

  defp fit_fields(selected, id, name, category, visibility, group) do
    {initial, truncated?} =
      Enum.map_reduce(selected, false, fn {key, value}, any_truncated? ->
        {safe_value, field_truncated?} = sanitize(value, 0, visibility != "public", 0)
        {{to_string(key), safe_value}, any_truncated? or field_truncated?}
      end)

    fit_fields(initial, id, name, category, visibility, group, truncated?)
  end

  defp fit_fields(fields, id, name, category, visibility, group, truncated?) do
    candidate = %{
      "category" => category,
      "id" => short_text(id, 120),
      "name" => short_text(name, 120),
      "visibility" => visibility,
      "group" => short_text(group, 64),
      "fields" => Map.new(fields),
      "details_truncated" => truncated?
    }

    if byte_size(Jason.encode!(candidate)) <= @max_record_bytes or fields == [] do
      {Map.new(fields), truncated?}
    else
      fit_fields(Enum.drop(fields, -1), id, name, category, visibility, group, true)
    end
  end

  # The allowlists above keep private data out of public records; this second
  # guard prevents nested maps from smuggling private-looking keys across a
  # scope boundary.
  defp sanitize(value, depth, private_scope?, max_items) do
    cond do
      is_binary(value) ->
        {short_text(value, 180), String.length(value) > 180}

      is_integer(value) or is_float(value) or is_boolean(value) or is_nil(value) ->
        {value, false}

      is_atom(value) ->
        {Atom.to_string(value), false}

      depth >= 2 ->
        {short_text(inspect(value), 100), true}

      is_map(value) ->
        entries = Enum.sort_by(value, fn {key, _} -> to_string(key) end)

        public_entries =
          Enum.reject(entries, fn {key, _} -> not private_scope? and private_key?(key) end)

        limit = if max_items > 0, do: max_items, else: 5
        selected = Enum.take(public_entries, limit)

        {safe_map, nested_truncated?} =
          Enum.map_reduce(selected, false, fn {key, item}, any_truncated? ->
            {safe_item, item_truncated?} = sanitize(item, depth + 1, private_scope?, 5)
            {{short_text(to_string(key), 48), safe_item}, any_truncated? or item_truncated?}
          end)

        {Map.new(safe_map), nested_truncated? or length(entries) != length(selected)}

      is_list(value) ->
        selected = Enum.take(value, 5)

        {safe_list, nested_truncated?} =
          Enum.map_reduce(selected, false, fn item, any_truncated? ->
            {safe_item, item_truncated?} = sanitize(item, depth + 1, private_scope?, 5)
            {safe_item, any_truncated? or item_truncated?}
          end)

        {safe_list, nested_truncated? or length(value) > length(selected)}

      true ->
        {short_text(inspect(value), 120), true}
    end
  end

  defp maybe_add(records, nil), do: records
  defp maybe_add(records, record), do: [record | records]

  defp relevance(record, query, terms) do
    name = String.downcase(record["name"])
    id = String.downcase(record["id"])

    encoded =
      Jason.encode!(Map.drop(record, ["_order", "details_truncated"])) |> String.downcase()

    q = String.downcase(query)

    cond do
      id == q ->
        1_000

      name == q ->
        950

      String.contains?(id, q) or String.contains?(name, q) ->
        800

      String.contains?(encoded, q) ->
        650

      true ->
        matches = Enum.count(terms, &String.contains?(encoded, &1))

        if matches == 0,
          do: 0,
          else: 100 + matches * 20 + div(matches * 100, max(length(terms), 1))
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> then(&Regex.scan(~r/[\p{L}\p{N}_-]+/u, &1))
    |> List.flatten()
    |> Enum.reject(&(String.length(&1) < 2))
    |> Enum.uniq()
  end

  defp effective_visibility(row, default) do
    case get(row, "visibility") do
      nil -> default
      value -> if private_visibility?(value), do: "gm_private", else: "public"
    end
  end

  defp scope_visibility(scope) do
    if private_visibility?(scope), do: "gm_private", else: "public"
  end

  defp private_visibility?(visibility) when is_atom(visibility),
    do: private_visibility?(Atom.to_string(visibility))

  defp private_visibility?(visibility) when is_binary(visibility),
    do: visibility in ["gm_private", "private", "hidden"]

  defp private_visibility?(_), do: false

  defp private_key?(key) do
    key = key |> to_string() |> String.downcase()
    key in @private_keys or String.contains?(key, ["private", "hidden", "secret"])
  end

  defp first(map, keys, fallback) do
    Enum.find_value(keys, fallback, fn key ->
      value = get(map, key)
      if is_nil(value) or value == "", do: nil, else: value
    end)
  end

  defp listify(value) when is_list(value), do: value
  defp listify(value) when is_map(value), do: [value]
  defp listify(_), do: []

  defp get(map, key) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(map, fn {candidate, value} ->
          if is_atom(candidate) and Atom.to_string(candidate) == key, do: {:found, value}
        end)
        |> case do
          {:found, value} -> value
          nil -> nil
        end
    end
  end

  defp get(_, _), do: nil

  defp short_text(text, limit) when is_binary(text) do
    if String.length(text) <= limit, do: text, else: String.slice(text, 0, limit) <> "…"
  end

  defp short_text(value, limit) when is_atom(value) or is_number(value),
    do: short_text(to_string(value), limit)

  defp short_text(value, limit), do: short_text(inspect(value), limit)
end
