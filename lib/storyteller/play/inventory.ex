defmodule Storyteller.Play.Inventory do
  @moduledoc """
  Validates and applies canonical campaign inventory operations.

  Operations use JSON-shaped maps. Add an item with `%{"type" => "add", "item" => item,
  "reason" => reason}`, transfer a whole stack with `%{"type" => "transfer",
  "item_id" => id, "owner_id" => owner, "reason" => reason}`, or consume part of a
  stack with `%{"type" => "consume", "item_id" => id, "quantity" => n,
  "reason" => reason}`. Validation is all-or-nothing: callers should only apply the
  returned normalized operations after the entire proposal succeeds.
  """

  @max_items 200
  @max_changes 50
  @max_id_length 100
  @max_name_length 160
  @max_text_length 2_000
  @max_quantity 1_000_000
  @max_property_nodes 256
  @max_property_depth 8

  @item_keys ~w(id name quantity unit category description owner_id visibility properties)

  @doc "Validate a list of inventory operations against current inventory and owners."
  def validate_changes(changes, inventory, valid_owner_ids) do
    with {:ok, owners} <- normalize_owner_ids(valid_owner_ids),
         {:ok, inventory} <- validate_inventory(inventory, owners),
         :ok <- validate_changes_list(changes),
         {:ok, normalized} <- normalize_changes(changes, inventory, owners) do
      {:ok, normalized}
    end
  end

  @doc "Validate and normalize the campaign's initial inventory."
  def normalize_initial(items, valid_owner_ids) do
    with {:ok, owners} <- normalize_owner_ids(valid_owner_ids),
         true <- is_list(items) and length(items) <= @max_items do
      items =
        items
        |> Enum.with_index()
        |> Enum.map(fn
          {item, index} when is_map(item) ->
            item
            |> put_default("id", initial_id(item, index))
            |> put_default("owner_id", "player")
            |> put_default("visibility", "public")
            |> put_default("properties", %{})

          {other, _index} ->
            other
        end)

      case validate_inventory(items, owners) do
        {:ok, normalized} -> {:ok, normalized}
        error -> error
      end
    else
      false -> {:error, :invalid_inventory}
      {:error, _} = error -> error
    end
  end

  @doc "Apply previously validated operations and return the canonical inventory list."
  def apply_changes(inventory, changes) when is_list(inventory) and is_list(changes) do
    Enum.reduce(changes, inventory, &apply_change/2)
  end

  def apply_changes(inventory, _changes) when is_list(inventory), do: inventory
  def apply_changes(_inventory, _changes), do: []

  @doc "Return only player-visible items."
  def public_projection(inventory) when is_list(inventory) do
    Enum.filter(inventory, fn item -> is_map(item) and get(item, "visibility") != "gm_private" end)
  end

  def public_projection(_inventory), do: []

  defp normalize_owner_ids(owner_ids) when is_list(owner_ids) do
    trimmed =
      Enum.map(owner_ids, fn id ->
        if is_binary(id) and String.valid?(id), do: String.trim(id), else: id
      end)

    if Enum.all?(trimmed, &valid_id?/1) do
      {:ok, MapSet.new(trimmed)}
    else
      {:error, :invalid_owner_ids}
    end
  end

  defp normalize_owner_ids(%MapSet{} = owner_ids),
    do: normalize_owner_ids(MapSet.to_list(owner_ids))

  defp normalize_owner_ids(owner_ids) when is_map(owner_ids) do
    normalize_owner_ids(Map.keys(owner_ids))
  end

  defp normalize_owner_ids(_), do: {:error, :invalid_owner_ids}

  defp validate_inventory(inventory, owners)
       when is_list(inventory) and length(inventory) <= @max_items do
    Enum.reduce_while(inventory, {:ok, [], MapSet.new()}, fn item, {:ok, acc, ids} ->
      with {:ok, normalized} <- normalize_item(item, owners),
           false <- MapSet.member?(ids, normalized["id"]) do
        {:cont, {:ok, [normalized | acc], MapSet.put(ids, normalized["id"])}}
      else
        true -> {:halt, {:error, :duplicate_item_id}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed, _ids} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp validate_inventory(_inventory, _owners), do: {:error, :invalid_inventory}

  defp validate_changes_list(changes) when is_list(changes) and length(changes) <= @max_changes,
    do: :ok

  defp validate_changes_list(_), do: {:error, :invalid_changes}

  defp normalize_changes(changes, inventory, owners) do
    Enum.reduce_while(changes, {:ok, [], inventory}, fn change, {:ok, acc, current} ->
      with {:ok, normalized} <- normalize_change(change, current, owners),
           {:ok, updated} <- apply_checked(current, normalized) do
        {:cont, {:ok, [normalized | acc], updated}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed, _inventory} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp normalize_change(change, inventory, owners) when is_map(change) do
    case get(change, "type") do
      "add" -> normalize_add(change, owners)
      "transfer" -> normalize_transfer(change, inventory, owners)
      "consume" -> normalize_consume(change, inventory)
      _ -> {:error, :invalid_operation}
    end
  end

  defp normalize_change(_change, _inventory, _owners), do: {:error, :invalid_operation}

  defp normalize_add(change, owners) do
    with :ok <- only_keys(change, ~w(type item reason)),
         {:ok, reason} <- reason(change),
         {:ok, item} <- normalize_item(get(change, "item"), owners) do
      {:ok,
       %{"type" => "add", "item" => item, "reason" => reason, "visibility" => item["visibility"]}}
    end
  end

  defp normalize_transfer(change, inventory, owners) do
    with :ok <- only_keys(change, ~w(type item_id owner_id reason)),
         {:ok, reason} <- reason(change),
         {:ok, id} <- required_id(change, "item_id"),
         {:ok, owner_id} <- required_id(change, "owner_id"),
         :ok <- valid_owner(owner_id, owners),
         {:ok, item} <- find_item(inventory, id) do
      {:ok,
       %{
         "type" => "transfer",
         "item_id" => id,
         "item_name" => item["name"],
         "quantity" => item["quantity"],
         "unit" => item["unit"],
         "owner_id" => owner_id,
         "reason" => reason,
         "visibility" => item["visibility"]
       }}
    end
  end

  defp normalize_consume(change, inventory) do
    with :ok <- only_keys(change, ~w(type item_id quantity reason)),
         {:ok, reason} <- reason(change),
         {:ok, id} <- required_id(change, "item_id"),
         {:ok, quantity} <- required_quantity(change, "quantity"),
         {:ok, item} <- find_item(inventory, id),
         true <- quantity <= item["quantity"] do
      {:ok,
       %{
         "type" => "consume",
         "item_id" => id,
         "item_name" => item["name"],
         "quantity" => quantity,
         "unit" => item["unit"],
         "reason" => reason,
         "visibility" => item["visibility"]
       }}
    else
      false -> {:error, :insufficient_quantity}
      {:error, _} = error -> error
    end
  end

  defp normalize_item(item, owners) when is_map(item) do
    with :ok <- only_keys(item, @item_keys),
         {:ok, id} <- required_id(item, "id"),
         {:ok, name} <- required_text(item, "name", @max_name_length),
         {:ok, quantity} <- required_quantity(item, "quantity"),
         {:ok, owner_id} <- required_id(item, "owner_id"),
         :ok <- valid_owner(owner_id, owners),
         {:ok, visibility} <- normalize_visibility(get(item, "visibility")),
         {:ok, unit} <- optional_text(item, "unit", 80),
         {:ok, category} <- optional_text(item, "category", 100),
         {:ok, description} <- optional_text(item, "description", @max_text_length),
         {:ok, properties} <- normalize_properties(get(item, "properties")) do
      normalized = %{
        "id" => id,
        "name" => name,
        "quantity" => quantity,
        "owner_id" => owner_id,
        "visibility" => visibility,
        "properties" => properties
      }

      normalized = maybe_put(normalized, "unit", unit)
      normalized = maybe_put(normalized, "category", category)
      normalized = maybe_put(normalized, "description", description)
      {:ok, normalized}
    end
  end

  defp normalize_item(_item, _owners), do: {:error, :invalid_item}

  defp normalize_visibility(nil), do: {:ok, "public"}
  defp normalize_visibility("public"), do: {:ok, "public"}
  defp normalize_visibility("gm_private"), do: {:ok, "gm_private"}
  defp normalize_visibility(_), do: {:error, :invalid_visibility}

  defp normalize_properties(nil), do: {:ok, %{}}

  defp normalize_properties(properties) when is_map(properties) do
    case validate_json_value(properties, 0, 0) do
      {:ok, _nodes} -> {:ok, properties}
      :error -> {:error, :invalid_properties}
    end
  end

  defp normalize_properties(_), do: {:error, :invalid_properties}

  defp validate_json_value(_value, depth, _nodes) when depth > @max_property_depth, do: :error
  defp validate_json_value(_value, _depth, nodes) when nodes >= @max_property_nodes, do: :error

  defp validate_json_value(value, _depth, nodes) when is_binary(value),
    do: if(String.valid?(value), do: {:ok, nodes + 1}, else: :error)

  defp validate_json_value(value, _depth, nodes)
       when is_integer(value) or is_float(value) or is_boolean(value),
       do: {:ok, nodes + 1}

  defp validate_json_value(nil, _depth, nodes), do: {:ok, nodes + 1}

  defp validate_json_value(value, depth, nodes) when is_list(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn item, {:ok, count} ->
      case validate_json_value(item, depth + 1, count) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp validate_json_value(value, depth, nodes) when is_map(value) do
    Enum.reduce_while(value, {:ok, nodes + 1}, fn {key, item}, {:ok, count} ->
      if is_binary(key) and String.valid?(key) do
        case validate_json_value(item, depth + 1, count) do
          {:ok, updated} -> {:cont, {:ok, updated}}
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
        if valid_id?(value), do: {:ok, String.trim(value)}, else: {:error, :invalid_id}

      _ ->
        {:error, :invalid_id}
    end
  end

  defp valid_id?(value) when is_binary(value) do
    String.valid?(value) and String.trim(value) != "" and String.length(value) <= @max_id_length
  end

  defp valid_id?(_), do: false

  defp required_text(map, key, max_length) do
    case get(map, key) do
      value when is_binary(value) ->
        if String.valid?(value) do
          trimmed = String.trim(value)

          if trimmed != "" and String.length(trimmed) <= max_length,
            do: {:ok, trimmed},
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
          trimmed = String.trim(value)

          if trimmed == "" or String.length(trimmed) > max_length,
            do: {:error, :invalid_text},
            else: {:ok, trimmed}
        else
          {:error, :invalid_text}
        end

      _ ->
        {:error, :invalid_text}
    end
  end

  defp required_quantity(map, key) do
    case get(map, key) do
      value when is_integer(value) and value > 0 and value <= @max_quantity -> {:ok, value}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp reason(map), do: required_text(map, "reason", 1_000)

  defp valid_owner("party", _owners), do: :ok

  defp valid_owner(owner_id, owners),
    do: if(MapSet.member?(owners, owner_id), do: :ok, else: {:error, :invalid_owner})

  defp find_item(inventory, id) do
    case Enum.find(inventory, &(get(&1, "id") == id)) do
      nil -> {:error, :item_not_found}
      item -> {:ok, item}
    end
  end

  defp apply_checked(inventory, %{"type" => "add", "item" => item}) do
    if Enum.any?(inventory, &(get(&1, "id") == item["id"])),
      do: {:error, :duplicate_item_id},
      else: {:ok, inventory ++ [item]}
  end

  defp apply_checked(inventory, %{"type" => "transfer", "item_id" => id, "owner_id" => owner_id}) do
    {:ok,
     Enum.map(inventory, fn item ->
       if item["id"] == id, do: Map.put(item, "owner_id", owner_id), else: item
     end)}
  end

  defp apply_checked(inventory, %{"type" => "consume", "item_id" => id, "quantity" => quantity}) do
    item = Enum.find(inventory, &(&1["id"] == id))

    case item do
      %{"quantity" => current_quantity} when current_quantity >= quantity ->
        if current_quantity == quantity do
          {:ok, Enum.reject(inventory, &(&1["id"] == id))}
        else
          {:ok,
           Enum.map(inventory, fn current ->
             if current["id"] == id,
               do: Map.update!(current, "quantity", &(&1 - quantity)),
               else: current
           end)}
        end

      _ ->
        {:error, :item_not_found}
    end
  end

  defp apply_change(%{"type" => "add", "item" => item} = change, inventory) when is_map(item) do
    apply_validated_change(change, inventory)
  end

  defp apply_change(
         %{"type" => "transfer", "item_id" => id, "owner_id" => owner_id} = change,
         inventory
       )
       when is_binary(id) and is_binary(owner_id) do
    apply_validated_change(change, inventory)
  end

  defp apply_change(
         %{"type" => "consume", "item_id" => id, "quantity" => quantity} = change,
         inventory
       )
       when is_binary(id) and is_integer(quantity) and quantity > 0 do
    apply_validated_change(change, inventory)
  end

  defp apply_change(_change, inventory), do: inventory

  defp apply_validated_change(change, inventory) do
    case apply_checked(inventory, change) do
      {:ok, updated} -> updated
      {:error, _reason} -> inventory
    end
  end

  defp only_keys(map, allowed) do
    normalized = Enum.map(Map.keys(map), &normalize_key/1)

    if Enum.all?(normalized, &(&1 in allowed)) and
         length(Enum.uniq(normalized)) == length(normalized),
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
  defp atom_key("item"), do: :item
  defp atom_key("item_id"), do: :item_id
  defp atom_key("id"), do: :id
  defp atom_key("name"), do: :name
  defp atom_key("quantity"), do: :quantity
  defp atom_key("unit"), do: :unit
  defp atom_key("category"), do: :category
  defp atom_key("description"), do: :description
  defp atom_key("owner_id"), do: :owner_id
  defp atom_key("visibility"), do: :visibility
  defp atom_key("properties"), do: :properties
  defp atom_key("reason"), do: :reason
  defp atom_key(_), do: nil

  defp put_default(map, key, value) do
    if Map.has_key?(map, key) or Map.has_key?(map, atom_key(key)),
      do: map,
      else: Map.put(map, key, value)
  end

  defp initial_id(item, index) do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({index, item})) |> Base.encode16(case: :lower)

    "initial-" <> binary_part(digest, 0, 24)
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_), do: nil
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
