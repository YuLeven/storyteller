defmodule Storyteller.Campaigns do
  @moduledoc "Campaign and session persistence for the local Storyteller application."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyteller.Campaigns.{Campaign, Session}
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Play.Inventory
  alias Storyteller.Repo

  def list_campaigns do
    session_query = from session in Session, order_by: [desc: session.inserted_at]

    Repo.all(
      from campaign in Campaign,
        order_by: [desc: campaign.updated_at, desc: campaign.inserted_at],
        preload: [sessions: ^session_query]
    )
  end

  def get_campaign(id) do
    case Repo.get(Campaign, id) do
      nil ->
        nil

      campaign ->
        Repo.preload(campaign,
          sessions: from(session in Session, order_by: [desc: session.inserted_at])
        )
    end
  end

  def get_campaign!(id) do
    Repo.get!(Campaign, id)
    |> Repo.preload(sessions: from(session in Session, order_by: [desc: session.inserted_at]))
  end

  def change_campaign(%Campaign{} = campaign, attrs \\ %{}) do
    Campaign.changeset(campaign, attrs)
  end

  @doc "Validates the full reviewable setup without writing any records."
  def validate_campaign_setup(attrs) when is_map(attrs) do
    campaign_attrs = campaign_attrs(attrs)
    campaign_changeset = Campaign.changeset(%Campaign{}, campaign_attrs)

    if campaign_changeset.valid? do
      with {:ok, characters} <-
             normalize_setup_characters(attr(attrs, :gm_characters, attr(attrs, :characters, []))),
           {:ok, panel_fields} <-
             normalize_panel_fields(attr(attrs, :panel_fields, attr(attrs, :panels, []))),
           {:ok, inventory} <-
             normalize_initial_inventory(
               attr(attrs, :inventory, []),
               ["player" | Enum.map(characters, & &1.speaker_id)]
             ),
           {:ok, public_state} <-
             normalize_initial_world(campaign_changeset, attr(attrs, :public_state, %{})) do
        {:ok,
         %{
           campaign_changeset: campaign_changeset,
           campaign: Ecto.Changeset.apply_changes(campaign_changeset),
           public_state: public_state,
           characters: characters,
           panel_fields: panel_fields,
           inventory: inventory,
           raw_attrs: attrs
         }}
      end
    else
      {:error, campaign_changeset}
    end
  end

  def validate_campaign_setup(_attrs), do: {:error, {:setup, "Campaign setup must be a form."}}

  def create_campaign(attrs) do
    with {:ok, setup} <- validate_campaign_setup(attrs) do
      Multi.new()
      |> Multi.insert(:campaign, setup.campaign_changeset)
      |> Multi.insert(:session, fn %{campaign: campaign} ->
        Session.changeset(%Session{}, %{campaign_id: campaign.id, title: "Session 1"})
      end)
      |> Multi.run(:play_state, fn _repo, %{campaign: campaign} ->
        Play.initialize_campaign(campaign, %{
          public_state: setup.public_state,
          characters: setup.characters,
          inventory: setup.inventory,
          player_visible_facts: %{"description" => campaign.player_character}
        })
      end)
      |> Multi.run(:panel_fields, fn repo, %{campaign: campaign} ->
        insert_panel_fields(repo, campaign.id, setup.panel_fields)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{campaign: campaign, session: session}} ->
          {:ok, %{campaign | sessions: [session]}}

        {:error, :campaign, changeset, _changes} ->
          {:error, changeset}

        {:error, :session, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  def start_session(%Campaign{id: campaign_id}, attrs \\ %{}) do
    Multi.new()
    |> Multi.run(:locked_campaign, fn repo, _changes ->
      case repo.one(
             from campaign in Campaign, where: campaign.id == ^campaign_id, lock: "FOR UPDATE"
           ) do
        %Campaign{status: :active} = campaign -> {:ok, campaign}
        %Campaign{status: :archived} -> {:error, :campaign_archived}
        nil -> {:error, :not_found}
      end
    end)
    |> Multi.update_all(
      :complete_previous_session,
      from(session in Session,
        where: session.campaign_id == ^campaign_id and session.status == :active
      ),
      set: [status: :completed, ended_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
    )
    |> Multi.insert(:session, fn %{locked_campaign: campaign} ->
      sequence =
        Repo.aggregate(
          from(session in Session, where: session.campaign_id == ^campaign.id),
          :count
        )

      title = supplied_title(attrs) || "Session #{sequence + 1}"

      Session.changeset(%Session{}, %{campaign_id: campaign.id, title: title})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _changes} -> {:error, changeset}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def get_session(campaign_id, session_id) do
    Repo.get_by(Session, id: session_id, campaign_id: campaign_id)
    |> case do
      nil -> nil
      session -> Repo.preload(session, :campaign)
    end
  end

  def archive_campaign(%Campaign{id: campaign_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Multi.new()
    |> Multi.run(:locked_campaign, fn repo, _changes ->
      case repo.one(
             from campaign in Campaign, where: campaign.id == ^campaign_id, lock: "FOR UPDATE"
           ) do
        nil -> {:error, :not_found}
        campaign -> {:ok, campaign}
      end
    end)
    |> Multi.update_all(
      :complete_active_sessions,
      from(session in Session,
        where: session.campaign_id == ^campaign_id and session.status == :active
      ),
      set: [status: :completed, ended_at: now]
    )
    |> Multi.update(:campaign, fn %{locked_campaign: campaign} ->
      Campaign.changeset(campaign, %{status: :archived})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{campaign: campaign}} -> {:ok, campaign}
      {:error, :campaign, changeset, _changes} -> {:error, changeset}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def restore_campaign(%Campaign{} = campaign) do
    campaign
    |> Campaign.changeset(%{status: :active})
    |> Repo.update()
  end

  defp supplied_title(attrs) do
    attrs
    |> Map.get(:title, Map.get(attrs, "title"))
    |> case do
      title when is_binary(title) -> String.trim(title)
      _ -> ""
    end
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp campaign_attrs(attrs) do
    Map.take(
      attrs,
      [
        :title,
        :premise,
        :setting,
        :tone,
        :narration_language,
        :player_character,
        :status,
        :starting_location,
        :starting_date,
        :world_time,
        :weather
      ]
    )
    |> Map.merge(
      Enum.reduce(
        [
          "title",
          "premise",
          "setting",
          "tone",
          "narration_language",
          "player_character",
          "status",
          "starting_location",
          "starting_date",
          "world_time",
          "weather"
        ],
        %{},
        fn key, acc ->
          if Map.has_key?(attrs, key),
            do: Map.put(acc, String.to_existing_atom(key), Map.get(attrs, key)),
            else: acc
        end
      )
    )
  end

  defp normalize_initial_world(campaign_changeset, initial_state) when is_map(initial_state) do
    location = clean_optional(Ecto.Changeset.get_field(campaign_changeset, :starting_location))
    world_time = clean_optional(Ecto.Changeset.get_field(campaign_changeset, :world_time))
    weather = clean_optional(Ecto.Changeset.get_field(campaign_changeset, :weather))

    state =
      %{
        "location" => location,
        "date" => clean_optional(Ecto.Changeset.get_field(campaign_changeset, :starting_date)),
        "time" => world_time,
        "weather" => weather
      }
      |> Map.merge(stringify_top_level(initial_state))

    case Jason.encode(state) do
      {:ok, encoded} when byte_size(encoded) <= 100_000 -> {:ok, state}
      _ -> {:error, {:setup, "Starting world details must be JSON-safe and under 100 KB."}}
    end
  rescue
    _error -> {:error, {:setup, "Starting world details must be a map."}}
  end

  defp normalize_initial_world(_changeset, _initial_state),
    do: {:error, {:setup, "Starting world details must be a map."}}

  defp normalize_setup_characters(rows) when is_list(rows) or is_map(rows) do
    rows
    |> indexed_rows()
    |> Enum.reject(fn {_index, attrs} -> blank_row?(attrs) end)
    |> case do
      rows when length(rows) > 100 ->
        {:error, {:setup, "Add no more than 100 GM-controlled characters."}}

      rows ->
        rows
        |> Enum.reduce_while({:ok, []}, fn {row_index, attrs}, {:ok, acc} ->
          speaker_id = attrs |> attr(:speaker_id, "") |> trim_string()
          name = attrs |> attr(:name, "") |> trim_string()
          visible = character_facts(attrs, :visible_facts, :visible_facts_text, "description")
          private = character_facts(attrs, :gm_private_facts, :private_notes, "notes")

          cond do
            not valid_speaker_id?(speaker_id) ->
              {:halt,
               {:error,
                {:setup,
                 "GM character #{row_index + 1} needs a stable speaker ID using letters, numbers, colon, underscore, or hyphen."}}}

            speaker_id == "player" ->
              {:halt,
               {:error, {:setup, "The speaker ID 'player' is reserved for the player character."}}}

            Enum.any?(acc, &(&1.speaker_id == speaker_id)) ->
              {:halt, {:error, {:setup, "Each GM character needs a unique speaker ID."}}}

            not is_binary(name) or name == "" or String.length(name) > 300 ->
              {:halt,
               {:error,
                {:setup, "GM character #{row_index + 1} needs a name up to 300 characters."}}}

            not is_map(visible) or not is_map(private) ->
              {:halt, {:error, {:setup, "GM character facts must be maps."}}}

            not json_map?(visible) or not json_map?(private) ->
              {:halt, {:error, {:setup, "GM character facts must be JSON-safe."}}}

            true ->
              {:cont,
               {:ok,
                acc ++
                  [
                    %{
                      speaker_id: speaker_id,
                      name: name,
                      visible_facts: visible,
                      gm_private_facts: private
                    }
                  ]}}
          end
        end)
    end
  end

  defp normalize_setup_characters(_), do: {:error, {:setup, "GM characters must be a list."}}

  defp normalize_panel_fields(rows) when is_list(rows) or is_map(rows) do
    rows
    |> indexed_rows()
    |> Enum.reject(fn {_index, attrs} -> blank_row?(attrs) end)
    |> case do
      rows when length(rows) > 100 ->
        {:error, {:setup, "Add no more than 100 panel fields."}}

      rows ->
        rows
        |> Enum.reduce_while({:ok, []}, fn {row_index, attrs}, {:ok, acc} ->
          if not is_map(attrs) do
            {:halt, {:error, {:setup, "Panel field #{row_index + 1} must be an object."}}}
          else
            panel_attrs =
              Map.new(
                [:key, :panel, :label, :value_type, :unit, :visibility, :initial_value],
                fn key -> {key, attr(attrs, key)} end
              )
              |> Map.put(:position, row_index)

            changeset = PanelField.definition_changeset(panel_attrs)

            cond do
              not changeset.valid? ->
                {:halt,
                 {:error,
                  {:setup,
                   "Panel field #{row_index + 1}: " <>
                     format_changeset_errors(changeset)}}}

              Enum.any?(acc, &(&1.key == Ecto.Changeset.get_field(changeset, :key))) ->
                {:halt, {:error, {:setup, "Each panel field needs a unique key."}}}

              true ->
                {:cont, {:ok, acc ++ [Ecto.Changeset.apply_changes(changeset)]}}
            end
          end
        end)
    end
  end

  defp normalize_panel_fields(_), do: {:error, {:setup, "Panel fields must be a list."}}

  defp normalize_initial_inventory(rows, valid_owner_ids) when is_list(rows) or is_map(rows) do
    rows =
      rows
      |> indexed_rows()
      |> Enum.reject(fn {_index, attrs} -> blank_row?(attrs) end)

    cond do
      length(rows) > 200 ->
        {:error, {:setup, "Add no more than 200 starting items."}}

      true ->
        rows
        |> Enum.reduce_while({:ok, []}, fn {row_index, attrs}, {:ok, acc} ->
          case normalize_initial_item(attrs, row_index) do
            {:ok, item} -> {:cont, {:ok, acc ++ [item]}}
            {:error, message} -> {:halt, {:error, {:setup, message}}}
          end
        end)
        |> case do
          {:ok, items} ->
            case Inventory.normalize_initial(items, valid_owner_ids) do
              {:ok, normalized} ->
                {:ok, normalized}

              {:error, _reason} ->
                {:error, {:setup, "Starting inventory contains an invalid item."}}
            end

          error ->
            error
        end
    end
  end

  defp normalize_initial_inventory(_rows, _valid_owner_ids),
    do: {:error, {:setup, "Starting inventory must be a list."}}

  defp normalize_initial_item(attrs, row_index) when is_map(attrs) do
    name = attr(attrs, :name, "") |> trim_string()
    quantity = normalize_item_quantity(attr(attrs, :quantity))
    unit = normalize_optional_item_text(attr(attrs, :unit), 80)
    category = normalize_optional_item_text(attr(attrs, :category), 100)
    description = normalize_optional_item_text(attr(attrs, :description), 2_000)

    cond do
      name == "" or String.length(name) > 160 ->
        {:error, "Starting item #{row_index + 1} needs a name up to 160 characters."}

      is_nil(quantity) ->
        {:error, "Starting item #{row_index + 1} needs a positive whole-number quantity."}

      unit == :invalid ->
        {:error, "Starting item #{row_index + 1} has an invalid unit (up to 80 characters)."}

      category == :invalid ->
        {:error, "Starting item #{row_index + 1} has an invalid category (up to 100 characters)."}

      description == :invalid ->
        {:error,
         "Starting item #{row_index + 1} has an invalid description (up to 2,000 characters)."}

      true ->
        {:ok,
         %{
           "name" => name,
           "quantity" => quantity,
           "unit" => empty_to_nil(unit),
           "category" => empty_to_nil(category),
           "description" => empty_to_nil(description)
         }}
    end
  end

  defp normalize_initial_item(_attrs, row_index),
    do: {:error, "Starting item #{row_index + 1} must be an object."}

  defp normalize_item_quantity(value) when is_integer(value) and value > 0 and value <= 1_000_000,
    do: value

  defp normalize_item_quantity(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {quantity, ""} when quantity > 0 and quantity <= 1_000_000 -> quantity
      _ -> nil
    end
  end

  defp normalize_item_quantity(_), do: nil

  defp normalize_optional_item_text(value, max_length) when is_binary(value) do
    trimmed = String.trim(value)
    if String.length(trimmed) <= max_length, do: trimmed, else: :invalid
  end

  defp normalize_optional_item_text(nil, _max_length), do: ""
  defp normalize_optional_item_text(_value, _max_length), do: :invalid

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp insert_panel_fields(repo, campaign_id, fields) do
    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, inserted} ->
      attrs = %{
        campaign_id: campaign_id,
        key: field.key,
        panel: field.panel,
        label: field.label,
        value_type: field.value_type,
        unit: field.unit,
        visibility: field.visibility,
        value: field.value,
        position: field.position
      }

      case repo.insert(PanelField.changeset(%PanelField{}, attrs)) do
        {:ok, saved} -> {:cont, {:ok, inserted ++ [saved]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp character_facts(attrs, map_key, text_key, fact_key) do
    case attr(attrs, map_key) do
      facts when is_map(facts) ->
        facts

      _ ->
        case attrs |> attr(text_key, "") |> trim_string() do
          "" -> %{}
          text -> %{fact_key => text}
        end
    end
  end

  defp valid_speaker_id?(id) when is_binary(id),
    do: String.length(id) <= 100 and Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, id)

  defp valid_speaker_id?(_), do: false

  defp json_map?(map) when is_map(map) do
    case Jason.encode(map) do
      {:ok, json} -> byte_size(json) <= 100_000
      _ -> false
    end
  rescue
    _ -> false
  end

  defp json_map?(_), do: false

  defp indexed_rows(rows) when is_list(rows) do
    rows |> Enum.with_index() |> Enum.map(fn {row, index} -> {index, row} end)
  end

  defp indexed_rows(rows) when is_map(rows) do
    rows
    |> Enum.map(fn {key, value} -> {index_value(key), value} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp indexed_rows(_), do: []

  defp index_value(index) when is_integer(index) and index >= 0, do: index

  defp index_value(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} when value >= 0 -> value
      _ -> 1_000_000
    end
  end

  defp index_value(_), do: 1_000_000

  defp blank_row?(attrs) when is_map(attrs) do
    Enum.all?(Map.values(attrs), fn
      nil -> true
      value when is_binary(value) -> String.trim(value) == ""
      _ -> false
    end)
  end

  defp blank_row?(_), do: false

  defp stringify_top_level(map) do
    Map.new(map, fn {key, value} ->
      {if(is_atom(key), do: Atom.to_string(key), else: key), value}
    end)
  end

  defp clean_optional(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean_optional(_), do: nil

  defp trim_string(value) when is_binary(value), do: String.trim(value)
  defp trim_string(_), do: ""

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp attr(map, key, default \\ nil)

  defp attr(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp attr(_map, _key, default), do: default
end
