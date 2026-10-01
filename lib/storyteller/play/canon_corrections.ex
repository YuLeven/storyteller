defmodule Storyteller.Play.CanonCorrections do
  @moduledoc """
  Applies explicit out-of-character corrections to tracked, player-visible canon.

  Corrections are revision-checked and serialized against turn creation. They do
  not create fictional events or advance world time; accepted snapshots are kept
  in a separate audit table.
  """

  import Ecto.Query, warn: false

  alias Storyteller.Campaigns.{Campaign, Session}
  alias Storyteller.Panels
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play.{CanonCorrection, Character, Inventory, Place, State, Turn}
  alias Storyteller.Repo

  @active_turn_statuses [:pending, :resolving, :awaiting_roll]
  @max_corrections 20

  @doc "Returns only correction choices already visible to the player."
  def options(campaign_id, session_id) do
    with %Campaign{status: :active} = campaign <- Repo.get(Campaign, campaign_id),
         %Session{status: :active} <-
           Repo.get_by(Session, id: session_id, campaign_id: campaign_id),
         %State{} = state <- Repo.get_by(State, campaign_id: campaign_id),
         {:ok, panel_projection} <- Panels.public_projection(campaign_id) do
      places =
        Repo.all(
          from place in Place,
            where: place.campaign_id == ^campaign_id and place.visibility == :public,
            order_by: [asc: place.name, asc: place.place_id]
        )

      place_ids = MapSet.new(places, & &1.place_id)

      characters =
        Repo.all(
          from character in Character,
            where: character.campaign_id == ^campaign_id,
            order_by: [asc: character.inserted_at, asc: character.id]
        )
        |> Enum.filter(fn character ->
          character.role == :player or MapSet.member?(place_ids, character.current_place_id)
        end)
        |> Enum.map(fn character ->
          %{
            id: character.speaker_id,
            name: public_character_name(character, campaign),
            place_id:
              if(MapSet.member?(place_ids, character.current_place_id),
                do: character.current_place_id,
                else: nil
              )
          }
        end)

      owner_ids = MapSet.new(characters, & &1.id)
      owners_by_id = Map.new(characters, &{&1.id, &1.name})

      inventory =
        state.public_state
        |> Map.get("inventory", [])
        |> Inventory.public_projection()
        |> Enum.map(fn item ->
          %{
            id: item["id"],
            name: item["name"],
            quantity: item["quantity"],
            unit: item["unit"],
            owner_name: Map.get(owners_by_id, item["owner_id"]),
            owner_is_known?: MapSet.member?(owner_ids, item["owner_id"])
          }
        end)

      resources =
        Enum.flat_map(panel_projection.panels, fn panel ->
          Enum.map(panel.fields, fn field ->
            Map.merge(field, %{panel: panel.name})
          end)
        end)

      {:ok,
       %{
         revision: state.revision,
         inventory: inventory,
         owners: [%{id: "party", name: "Party"} | characters],
         resources: resources,
         characters: characters,
         places: Enum.map(places, &%{id: &1.place_id, name: &1.name})
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  @doc "Returns concise out-of-character receipts; before/after snapshots stay in the audit record."
  def list_receipts(campaign_id) do
    Repo.all(
      from correction in CanonCorrection,
        where: correction.campaign_id == ^campaign_id,
        order_by: [desc: correction.sequence],
        limit: ^@max_corrections
    )
    |> Enum.map(fn correction ->
      before = receipt_snapshot(correction.kind, correction.before_state)
      after_snapshot = receipt_snapshot(correction.kind, correction.after_state)

      %{
        sequence: correction.sequence,
        kind: correction.kind,
        target_label: receipt_target_label(correction.kind, after_snapshot || before),
        before: before,
        after: after_snapshot,
        reason: correction.reason,
        inserted_at: correction.inserted_at
      }
    end)
  end

  defp receipt_snapshot("inventory", %{"item" => item}) when is_map(item) do
    %{name: item["name"], quantity: item["quantity"], unit: item["unit"]}
  end

  defp receipt_snapshot("inventory", _snapshot), do: nil

  defp receipt_snapshot("resource", snapshot) when is_map(snapshot) do
    %{label: snapshot["label"], value: snapshot["value"], unit: snapshot["unit"]}
  end

  defp receipt_snapshot("location", snapshot) when is_map(snapshot) do
    %{character_name: snapshot["character_name"], place_name: snapshot["place_name"]}
  end

  defp receipt_snapshot(_kind, _snapshot), do: nil

  defp receipt_target_label("inventory", %{name: name}), do: name
  defp receipt_target_label("resource", %{label: label}), do: label
  defp receipt_target_label("location", %{character_name: name}), do: name
  defp receipt_target_label(_kind, _snapshot), do: nil

  @doc "Applies one explicit correction, rejecting stale or in-flight campaign state."
  def correct(campaign_id, session_id, attrs) when is_map(attrs) do
    result =
      Repo.transaction(fn ->
        campaign = Repo.get(Campaign, campaign_id)
        session = Repo.get_by(Session, id: session_id, campaign_id: campaign_id)

        unless match?(%Campaign{status: :active}, campaign) and
                 match?(%Session{status: :active}, session),
               do: Repo.rollback(:unavailable)

        state =
          Repo.one!(
            from state in State,
              where: state.campaign_id == ^campaign_id,
              lock: "FOR UPDATE"
          )

        if has_active_turn?(campaign_id), do: Repo.rollback(:turn_in_progress)

        expected_revision = attr(attrs, :expected_revision)

        if parse_revision(expected_revision) != state.revision,
          do: Repo.rollback(:stale_correction)

        reason = normalize_reason(attr(attrs, :reason))
        if is_nil(reason), do: Repo.rollback(:invalid_reason)

        kind = normalize_kind(attr(attrs, :kind))
        target_id = attr(attrs, :target_id)
        values = attr(attrs, :values)

        with {:ok, target_id, before_state, after_state, apply} <-
               plan_correction(kind, target_id, values, campaign_id, state),
             {:ok, updated_state} <- apply.(state) do
          updated_state =
            updated_state
            |> State.changeset(%{revision: state.revision + 1})
            |> Repo.update!()

          sequence = next_sequence(campaign_id)

          %CanonCorrection{}
          |> CanonCorrection.changeset(%{
            campaign_id: campaign_id,
            sequence: sequence,
            kind: Atom.to_string(kind),
            target_id: target_id,
            expected_revision: state.revision,
            reason: reason,
            before_state: before_state,
            after_state: after_state,
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          })
          |> insert_correction!()

          %{revision: updated_state.revision, sequence: sequence}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, receipt} -> {:ok, receipt}
      {:error, reason} -> {:error, reason}
    end
  rescue
    Ecto.NoResultsError -> {:error, :unavailable}
  end

  def correct(_campaign_id, _session_id, _attrs), do: {:error, :invalid_correction}

  defp plan_correction(:inventory, target_id, values, campaign_id, state) do
    inventory = Map.get(state.public_state, "inventory", [])
    owners = public_owner_ids(campaign_id)
    action = attr(values, :action)

    case action do
      "add" -> add_item(inventory, values, owners)
      "set" -> set_item(inventory, target_id, values, owners)
      "remove" -> remove_item(inventory, target_id)
      _ -> {:error, :invalid_correction}
    end
  end

  defp plan_correction(:resource, target_id, values, campaign_id, _state) do
    field = Repo.get_by(PanelField, campaign_id: campaign_id, key: target_id, visibility: :public)

    with %PanelField{} <- field,
         raw_value when not is_nil(raw_value) <- attr(values, :value),
         {:ok, normalized} <- Panels.validate_value(field, raw_value) do
      after_storage = %{"value" => normalized}

      if field.value == after_storage do
        {:error, :no_change}
      else
        before_state = resource_snapshot(field, field.value)
        after_state = resource_snapshot(field, after_storage)

        update = fn state ->
          case field |> PanelField.changeset(%{value: after_storage}) |> Repo.update() do
            {:ok, _field} -> {:ok, state}
            {:error, _changeset} -> {:error, :invalid_correction}
          end
        end

        {:ok, field.key, before_state, after_state, update}
      end
    else
      nil -> {:error, :invalid_correction}
      {:error, _reason} -> {:error, :invalid_value}
      _ -> {:error, :not_found}
    end
  end

  defp plan_correction(:location, target_id, values, campaign_id, _state) do
    characters = public_characters(campaign_id)
    places = public_places(campaign_id)
    character = Enum.find(characters, &(&1.speaker_id == target_id))
    destination_id = attr(values, :place_id)
    destination = Enum.find(places, &(&1.place_id == destination_id))
    campaign = Repo.get!(Campaign, campaign_id)

    with %Character{} <- character,
         %Place{} <- destination do
      previous_place = Enum.find(places, &(&1.place_id == character.current_place_id))

      if character.current_place_id == destination.place_id do
        {:error, :no_change}
      else
        before_state = %{
          "character_name" => public_character_name(character, campaign),
          "place_id" => previous_place && previous_place.place_id,
          "place_name" => previous_place && previous_place.name
        }

        after_state = %{
          "character_name" => public_character_name(character, campaign),
          "place_id" => destination.place_id,
          "place_name" => destination.name
        }

        update = fn state ->
          case character
               |> Character.changeset(%{current_place_id: destination.place_id})
               |> Repo.update() do
            {:ok, _character} -> {:ok, state}
            {:error, _changeset} -> {:error, :invalid_correction}
          end
        end

        {:ok, character.speaker_id, before_state, after_state, update}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp plan_correction(_kind, _target_id, _values, _campaign_id, _state),
    do: {:error, :invalid_correction}

  defp add_item(inventory, values, owners) do
    if length(inventory) >= 200 do
      {:error, :invalid_value}
    else
      id = "correction-" <> Ecto.UUID.generate()
      owner_id = normalize_owner_id(attr(values, :owner_id)) || "player"

      candidate = %{
        "id" => id,
        "name" => attr(values, :name),
        "quantity" => parse_integer(attr(values, :quantity)),
        "unit" => blank_to_nil(attr(values, :unit)),
        "owner_id" => owner_id,
        "visibility" => "public",
        "properties" => %{}
      }

      case Inventory.normalize_initial([candidate], owners) do
        {:ok, [item]} ->
          if Enum.any?(inventory, &(attr(&1, :id) == item["id"])) do
            {:error, :invalid_value}
          else
            before_state = %{"item" => nil}
            after_state = %{"item" => item}
            next_inventory = inventory ++ [item]
            update = fn state -> put_public_inventory(state, next_inventory) end
            {:ok, item["id"], before_state, after_state, update}
          end

        _ ->
          {:error, :invalid_value}
      end
    end
  end

  defp set_item(inventory, target_id, values, owners) when is_binary(target_id) do
    case find_public_item(inventory, target_id) do
      nil ->
        {:error, :not_found}

      item ->
        quantity = parse_nonnegative_integer(attr(values, :quantity))
        owner_id = normalize_owner_id(attr(values, :owner_id))
        owner_id = if owner_id in [nil, ""], do: item["owner_id"], else: owner_id

        cond do
          is_nil(quantity) ->
            {:error, :invalid_value}

          quantity == 0 ->
            remove_item(inventory, target_id)

          true ->
            updated_item = Map.merge(item, %{"quantity" => quantity, "owner_id" => owner_id})

            validation_owners = owners |> MapSet.new() |> MapSet.put(item["owner_id"])

            case Inventory.normalize_initial([updated_item], validation_owners) do
              {:ok, [normalized]} ->
                next_inventory =
                  Enum.map(inventory, fn current ->
                    if current["id"] == target_id, do: normalized, else: current
                  end)

                if item == normalized do
                  {:error, :no_change}
                else
                  before_state = %{"item" => item}
                  after_state = %{"item" => normalized}
                  update = fn state -> put_public_inventory(state, next_inventory) end
                  {:ok, target_id, before_state, after_state, update}
                end

              _ ->
                {:error, :invalid_value}
            end
        end
    end
  end

  defp set_item(_inventory, _target_id, _values, _owners), do: {:error, :not_found}

  defp remove_item(inventory, target_id) when is_binary(target_id) do
    case find_public_item(inventory, target_id) do
      nil ->
        {:error, :not_found}

      item ->
        next_inventory = Enum.reject(inventory, &(&1["id"] == target_id))
        before_state = %{"item" => item}
        after_state = %{"item" => nil}
        update = fn state -> put_public_inventory(state, next_inventory) end
        {:ok, target_id, before_state, after_state, update}
    end
  end

  defp remove_item(_inventory, _target_id), do: {:error, :not_found}

  defp find_public_item(inventory, item_id) do
    Enum.find(inventory, fn item ->
      is_map(item) and attr(item, :id) == item_id and attr(item, :visibility) != "gm_private"
    end)
  end

  defp put_public_inventory(state, inventory) do
    case State.changeset(state, %{
           public_state: Map.put(state.public_state, "inventory", inventory)
         })
         |> Repo.update() do
      {:ok, updated_state} -> {:ok, updated_state}
      {:error, _changeset} -> {:error, :invalid_correction}
    end
  end

  defp resource_snapshot(field, storage) do
    %{
      "key" => field.key,
      "label" => field.label,
      "type" => Atom.to_string(field.value_type),
      "unit" => field.unit,
      "value" => storage_value(storage)
    }
  end

  defp storage_value(%{"value" => value}), do: value
  defp storage_value(%{value: value}), do: value
  defp storage_value(_), do: nil

  defp public_owner_ids(campaign_id) do
    ["party" | Enum.map(public_characters(campaign_id), & &1.speaker_id)]
  end

  defp public_character_name(%Character{speaker_id: "player"}, campaign),
    do: campaign.player_character_name

  defp public_character_name(%Character{} = character, _campaign), do: character.name

  defp public_characters(campaign_id) do
    places = public_places(campaign_id)
    place_ids = MapSet.new(places, & &1.place_id)

    Repo.all(from character in Character, where: character.campaign_id == ^campaign_id)
    |> Enum.filter(fn character ->
      character.role == :player or MapSet.member?(place_ids, character.current_place_id)
    end)
  end

  defp public_places(campaign_id) do
    Repo.all(
      from place in Place,
        where: place.campaign_id == ^campaign_id and place.visibility == :public
    )
  end

  defp has_active_turn?(campaign_id) do
    Repo.exists?(
      from turn in Turn,
        where: turn.campaign_id == ^campaign_id and turn.status in ^@active_turn_statuses
    )
  end

  defp next_sequence(campaign_id) do
    (Repo.one(
       from correction in CanonCorrection,
         where: correction.campaign_id == ^campaign_id,
         select: max(correction.sequence)
     ) || 0) + 1
  end

  defp insert_correction!(changeset) do
    case Repo.insert(changeset) do
      {:ok, correction} -> correction
      {:error, _changeset} -> Repo.rollback(:invalid_correction)
    end
  end

  defp parse_revision(value) when is_integer(value) and value >= 0, do: value

  defp parse_revision(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp parse_revision(_), do: nil

  defp normalize_kind("inventory"), do: :inventory
  defp normalize_kind(:inventory), do: :inventory
  defp normalize_kind("resource"), do: :resource
  defp normalize_kind(:resource), do: :resource
  defp normalize_kind("location"), do: :location
  defp normalize_kind(:location), do: :location
  defp normalize_kind(_), do: nil

  defp normalize_reason(value) when is_binary(value) do
    value = String.trim(value)
    if value != "" and String.length(value) <= 1_000, do: value
  end

  defp normalize_reason(_), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp parse_nonnegative_integer(value) do
    case parse_integer(value) do
      parsed when is_integer(parsed) and parsed >= 0 and parsed <= 1_000_000 -> parsed
      _ -> nil
    end
  end

  defp normalize_owner_id(value) when is_binary(value), do: String.trim(value)
  defp normalize_owner_id(_), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp attr(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp attr(_, _), do: nil
end
