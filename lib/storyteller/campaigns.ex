defmodule Storyteller.Campaigns do
  @moduledoc "Campaign and session persistence for the local Storyteller application."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyteller.Campaigns.{AuthoringCorrection, Campaign, Session}
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Play.{Character, VoiceGuidance}
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
    Campaign.changeset(campaign, legacy_player_name_attrs(campaign, attrs))
  end

  def list_gm_characters(campaign_id) do
    Repo.all(
      from character in Character,
        where: character.campaign_id == ^campaign_id and character.role == :gm,
        order_by: [asc: character.name, asc: character.speaker_id]
    )
  end

  @doc "Returns only the safe summary of public setup corrections for player-facing HTML."
  def list_public_authoring_corrections(campaign_id) do
    Repo.all(
      from correction in AuthoringCorrection,
        where:
          correction.campaign_id == ^campaign_id and
            correction.contains_private_changes == false,
        order_by: [desc: correction.sequence]
    )
    |> Enum.map(fn correction ->
      %{
        sequence: correction.sequence,
        reason: correction.reason,
        inserted_at: correction.inserted_at,
        summary_categories: public_correction_categories(correction.before_state)
      }
    end)
  end

  @doc "Atomically records and applies an auditable post-creation setup correction."
  def update_campaign_authoring(%Campaign{id: campaign_id}, attrs) when is_map(attrs) do
    Repo.transaction(fn -> apply_campaign_authoring_correction(campaign_id, attrs) end)
    |> case do
      {:ok, campaign} -> {:ok, campaign}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_campaign_authoring(_campaign, _attrs), do: {:error, :invalid_authoring}

  defp apply_campaign_authoring_correction(campaign_id, attrs) do
    campaign =
      Repo.one(
        from campaign in Campaign,
          where: campaign.id == ^campaign_id,
          lock: "FOR UPDATE"
      )

    if campaign do
      changeset = Campaign.changeset(campaign, authoring_campaign_attrs(attrs))

      unless changeset.valid?, do: Repo.rollback(changeset)

      with {:ok, voice_updates} <- normalize_character_voice_updates(campaign_id, attrs),
           {:ok, fact_updates} <- normalize_character_fact_updates(campaign_id, attrs) do
        characters =
          Repo.all(
            from character in Character,
              where: character.campaign_id == ^campaign_id,
              order_by: [asc: character.speaker_id],
              lock: "FOR UPDATE"
          )

        plan = authoring_change_plan(campaign, characters, changeset, voice_updates, fact_updates)

        if map_size(plan.before_state) == 0 do
          campaign
        else
          reason = normalized_correction_reason(attr(attrs, :correction_reason))
          if is_nil(reason), do: Repo.rollback(:invalid_correction_reason)

          updated_campaign = persist_campaign_correction!(campaign, characters, changeset, plan)
          sequence = next_correction_sequence(campaign_id)

          %AuthoringCorrection{}
          |> AuthoringCorrection.changeset(%{
            campaign_id: campaign_id,
            sequence: sequence,
            reason: reason,
            before_state: plan.before_state,
            after_state: plan.after_state,
            contains_private_changes: plan.contains_private_changes,
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
          })
          |> insert_authoring_correction!()

          updated_campaign
        end
      else
        {:error, reason} when reason in [:invalid_voice_guidance, :invalid_authoring_details] ->
          Repo.rollback(reason)

        {:error, _reason} ->
          Repo.rollback(:invalid_authoring_details)
      end
    else
      Repo.rollback(:not_found)
    end
  end

  defp authoring_change_plan(campaign, characters, changeset, voice_updates, fact_updates) do
    by_speaker = Map.new(characters, &{&1.speaker_id, &1})
    updated_campaign = Ecto.Changeset.apply_changes(changeset)

    {campaign_before, campaign_after} =
      Enum.reduce(changeset.changes, {%{}, %{}}, fn {field, new_value}, {before, after_map} ->
        old_value = Map.fetch!(campaign, field)
        diff_values(before, after_map, Atom.to_string(field), old_value, new_value)
      end)

    {player_before, player_after, player_attrs} =
      player_character_diff(Map.get(by_speaker, "player"), campaign, updated_campaign, changeset)

    {gm_before, gm_after, gm_updates, private?} =
      gm_character_diffs(by_speaker, voice_updates, fact_updates)

    before_state =
      %{}
      |> put_nonempty("campaign", campaign_before)
      |> put_nonempty("player_character", player_before)
      |> put_nonempty("gm_characters", gm_before)

    after_state =
      %{}
      |> put_nonempty("campaign", campaign_after)
      |> put_nonempty("player_character", player_after)
      |> put_nonempty("gm_characters", gm_after)

    %{
      before_state: before_state,
      after_state: after_state,
      player_attrs: player_attrs,
      gm_updates: gm_updates,
      contains_private_changes: private?
    }
  end

  defp player_character_diff(nil, _campaign, _updated_campaign, changeset) do
    if Map.has_key?(changeset.changes, :player_character_name) or
         Map.has_key?(changeset.changes, :player_character) do
      Repo.rollback(:invalid_player_character)
    end

    {%{}, %{}, %{}}
  end

  defp player_character_diff(player, _campaign, updated_campaign, changeset) do
    {before, after_map, attrs} =
      Enum.reduce(
        [player_character_name: :name, player_character: :description],
        {%{}, %{}, %{}},
        fn {campaign_field, character_field}, {before, after_map, attrs} ->
          if Map.has_key?(changeset.changes, campaign_field) do
            {old_value, new_value} =
              case character_field do
                :name ->
                  {player.name, updated_campaign.player_character_name}

                :description ->
                  {Map.get(player.visible_facts || %{}, "description"),
                   updated_campaign.player_character}
              end

            key = Atom.to_string(character_field)

            {before, after_map} = diff_values(before, after_map, key, old_value, new_value)

            attrs =
              if old_value == new_value do
                attrs
              else
                case character_field do
                  :name ->
                    Map.put(attrs, :name, new_value)

                  :description ->
                    Map.put(
                      attrs,
                      :visible_facts,
                      Map.put(player.visible_facts || %{}, "description", new_value)
                    )
                end
              end

            {before, after_map, attrs}
          else
            {before, after_map, attrs}
          end
        end
      )

    {before, after_map, attrs}
  end

  defp gm_character_diffs(by_speaker, voice_updates, fact_updates) do
    voices = Map.new(voice_updates)
    facts = Map.new(fact_updates)
    speakers = Enum.uniq(Map.keys(voices) ++ Map.keys(facts))

    Enum.reduce(speakers, {%{}, %{}, %{}, false}, fn speaker_id,
                                                     {before_all, after_all, updates_all,
                                                      private?} ->
      character = Map.fetch!(by_speaker, speaker_id)
      old_voice = character.voice_guidance || %{}
      new_voice = Map.get(voices, speaker_id, old_voice)
      fact_edits = Map.get(facts, speaker_id, %{})
      old_visible = character.visible_facts || %{}
      old_private = character.gm_private_facts || %{}
      new_visible = update_fact_text(old_visible, "description", fact_edits, :visible_facts_text)
      new_private = update_fact_text(old_private, "notes", fact_edits, :private_notes)

      {voice_before, voice_after_map} = map_diff(old_voice, new_voice)

      {visible_before, visible_after_map} =
        diff_one_key(old_visible, new_visible, "description")

      {private_before, private_after_map} = diff_one_key(old_private, new_private, "notes")

      before_map =
        %{}
        |> put_nonempty("voice_guidance", voice_before)
        |> put_nonempty("visible_facts", visible_before)
        |> put_nonempty("gm_private_facts", private_before)

      after_map =
        %{}
        |> put_nonempty("voice_guidance", voice_after_map)
        |> put_nonempty("visible_facts", visible_after_map)
        |> put_nonempty("gm_private_facts", private_after_map)

      update_attrs =
        %{}
        |> maybe_put(:voice_guidance, voice_before != %{}, new_voice)
        |> maybe_put(:visible_facts, visible_before != %{}, new_visible)
        |> maybe_put(:gm_private_facts, private_before != %{}, new_private)

      before_all = put_nonempty(before_all, speaker_id, before_map)
      after_all = put_nonempty(after_all, speaker_id, after_map)

      updates_all =
        if map_size(update_attrs) == 0,
          do: updates_all,
          else: Map.put(updates_all, speaker_id, update_attrs)

      private? =
        private? or map_size(private_before) > 0 or map_size(voice_before) > 0

      {before_all, after_all, updates_all, private?}
    end)
  end

  defp diff_one_key(before_map, after_map, key) do
    diff_values(%{}, %{}, key, Map.get(before_map, key), Map.get(after_map, key))
  end

  defp map_diff(before_map, after_map) do
    keys = Enum.uniq(Map.keys(before_map) ++ Map.keys(after_map))

    Enum.reduce(keys, {%{}, %{}}, fn key, {before, after_values} ->
      diff_values(before, after_values, key, Map.get(before_map, key), Map.get(after_map, key))
    end)
  end

  defp diff_values(before, after_map, _key, value, value), do: {before, after_map}

  defp diff_values(before, after_map, key, old, new),
    do: {Map.put(before, key, old), Map.put(after_map, key, new)}

  defp put_nonempty(map, _key, value) when map_size(value) == 0, do: map
  defp put_nonempty(map, key, value), do: Map.put(map, key, value)

  defp normalized_correction_reason(reason) when is_binary(reason) do
    normalized = String.trim(reason)
    if String.length(normalized) in 1..1_000, do: normalized, else: nil
  end

  defp normalized_correction_reason(_), do: nil

  defp persist_campaign_correction!(campaign, characters, changeset, plan) do
    updated_campaign =
      if map_size(changeset.changes) == 0 do
        campaign
      else
        case Repo.update(changeset) do
          {:ok, updated} -> updated
          {:error, failed_changeset} -> Repo.rollback(failed_changeset)
        end
      end

    by_speaker = Map.new(characters, &{&1.speaker_id, &1})

    if map_size(plan.player_attrs) > 0 do
      player = Map.get(by_speaker, "player") || Repo.rollback(:invalid_player_character)

      case Repo.update(Character.changeset(player, plan.player_attrs)) do
        {:ok, _updated} -> :ok
        {:error, _changeset} -> Repo.rollback(:invalid_player_character)
      end
    end

    Enum.each(plan.gm_updates, fn {speaker_id, update_attrs} ->
      character = Map.get(by_speaker, speaker_id) || Repo.rollback(:invalid_character)

      case Repo.update(Character.changeset(character, update_attrs)) do
        {:ok, _updated} -> :ok
        {:error, _changeset} -> Repo.rollback(:invalid_character)
      end
    end)

    updated_campaign
  end

  defp next_correction_sequence(campaign_id) do
    (Repo.one(
       from correction in AuthoringCorrection,
         where: correction.campaign_id == ^campaign_id,
         select: max(correction.sequence)
     ) || 0) + 1
  end

  defp insert_authoring_correction!(changeset) do
    case Repo.insert(changeset) do
      {:ok, correction} -> correction
      {:error, _changeset} -> Repo.rollback(:correction_record_failed)
    end
  end

  defp public_correction_categories(before_state) do
    []
    |> maybe_add_category(Map.has_key?(before_state, "campaign"), "campaign_setup")
    |> maybe_add_category(Map.has_key?(before_state, "player_character"), "player_character")
    |> maybe_add_category(has_public_gm_facts?(before_state), "character_details")
  end

  defp has_public_gm_facts?(%{"gm_characters" => characters}) do
    Enum.any?(characters, fn {_speaker, changes} -> Map.has_key?(changes, "visible_facts") end)
  end

  defp has_public_gm_facts?(_), do: false

  defp maybe_add_category(categories, true, category), do: categories ++ [category]
  defp maybe_add_category(categories, false, _category), do: categories

  @doc "Validates the full reviewable setup without writing any records."
  def validate_campaign_setup(attrs) when is_map(attrs) do
    campaign_attrs = campaign_attrs(attrs)
    campaign_changeset = Campaign.changeset(%Campaign{}, campaign_attrs)

    if campaign_changeset.valid? do
      with {:ok, characters} <-
             normalize_setup_characters(attr(attrs, :gm_characters, attr(attrs, :characters, []))),
           {:ok, player_visible_facts} <-
             normalize_player_character_details(attr(attrs, :player_character_details, [])),
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
           player_visible_facts: player_visible_facts,
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
          player_visible_facts:
            Map.put(setup.player_visible_facts, "description", campaign.player_character)
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
    attrs =
      Map.take(
        attrs,
        [
          :title,
          :premise,
          :setting,
          :tone,
          :narration_language,
          :player_character_name,
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
            "player_character_name",
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

    legacy_player_name_attrs(%Campaign{}, attrs)
  end

  defp authoring_campaign_attrs(attrs) do
    attrs =
      Enum.reduce(
        [
          :title,
          :premise,
          :setting,
          :tone,
          :narration_language,
          :player_character_name,
          :player_character
        ],
        %{},
        fn key, acc ->
          string_key = Atom.to_string(key)

          cond do
            Map.has_key?(attrs, key) -> Map.put(acc, key, Map.get(attrs, key))
            Map.has_key?(attrs, string_key) -> Map.put(acc, key, Map.get(attrs, string_key))
            true -> acc
          end
        end
      )

    legacy_player_name_attrs(%Campaign{}, attrs)
  end

  defp legacy_player_name_attrs(%Campaign{player_character_name: nil}, attrs) do
    if has_attr?(attrs, :player_character) and not has_attr?(attrs, :player_character_name) do
      Map.put(attrs, :player_character_name, attr(attrs, :player_character))
    else
      attrs
    end
  end

  defp legacy_player_name_attrs(_campaign, attrs), do: attrs

  defp maybe_put(map, _key, false, _value), do: map
  defp maybe_put(map, key, true, value), do: Map.put(map, key, value)

  defp normalize_character_voice_updates(campaign_id, attrs) do
    supplied = attr(attrs, :character_voice_guidance, %{})
    known_speakers = list_gm_characters(campaign_id) |> MapSet.new(& &1.speaker_id)

    cond do
      not is_map(supplied) ->
        {:error, :invalid_voice_guidance}

      map_size(supplied) > 100 ->
        {:error, :invalid_voice_guidance}

      true ->
        Enum.reduce_while(supplied, {:ok, []}, fn {speaker_id, notes}, {:ok, acc} ->
          speaker_id = if is_atom(speaker_id), do: Atom.to_string(speaker_id), else: speaker_id

          case VoiceGuidance.normalize(notes) do
            {:ok, normalized} ->
              if is_binary(speaker_id) and String.length(speaker_id) <= 100 and
                   MapSet.member?(known_speakers, speaker_id) do
                {:cont, {:ok, [{speaker_id, normalized} | acc]}}
              else
                {:halt, {:error, :invalid_voice_guidance}}
              end

            _ ->
              {:halt, {:error, :invalid_voice_guidance}}
          end
        end)
    end
  end

  defp normalize_character_fact_updates(campaign_id, attrs) do
    supplied = attr(attrs, :gm_character_setup, %{})
    known_speakers = list_gm_characters(campaign_id) |> MapSet.new(& &1.speaker_id)

    cond do
      not is_map(supplied) or map_size(supplied) > 100 ->
        {:error, :invalid_authoring_details}

      true ->
        Enum.reduce_while(supplied, {:ok, []}, fn {speaker_id, row}, {:ok, acc} ->
          speaker_id = if is_atom(speaker_id), do: Atom.to_string(speaker_id), else: speaker_id
          keys = if is_map(row), do: Enum.map(Map.keys(row), &key_name/1), else: []

          cond do
            not is_binary(speaker_id) or not MapSet.member?(known_speakers, speaker_id) ->
              {:halt, {:error, :invalid_authoring_details}}

            not is_map(row) or length(keys) != length(Enum.uniq(keys)) or
                Enum.any?(keys, &(&1 not in ["visible_facts_text", "private_notes"])) ->
              {:halt, {:error, :invalid_authoring_details}}

            true ->
              with {:ok, visible} <-
                     normalize_authoring_fact_text(row, :visible_facts_text),
                   {:ok, private} <- normalize_authoring_fact_text(row, :private_notes) do
                edits =
                  %{}
                  |> maybe_put(:visible_facts_text, visible)
                  |> maybe_put(:private_notes, private)

                {:cont,
                 {:ok, if(map_size(edits) == 0, do: acc, else: [{speaker_id, edits} | acc])}}
              else
                _ -> {:halt, {:error, :invalid_authoring_details}}
              end
          end
        end)
    end
  end

  defp normalize_authoring_fact_text(row, key) do
    if has_attr?(row, key) do
      value = attr(row, key)

      if is_binary(value) and String.valid?(value) and String.length(String.trim(value)) <= 5_000 do
        {:ok, String.trim(value)}
      else
        {:error, :invalid_authoring_details}
      end
    else
      {:ok, nil}
    end
  end

  defp update_fact_text(facts, fact_key, edits, edit_key) do
    if Map.has_key?(edits, edit_key) do
      case Map.fetch!(edits, edit_key) do
        "" -> Map.delete(facts, fact_key)
        value -> Map.put(facts, fact_key, value)
      end
    else
      facts
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp has_attr?(map, key) do
    Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))
  end

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(_key), do: nil

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
          supplied_speaker_id = attrs |> attr(:speaker_id, "") |> trim_string()
          name = attrs |> attr(:name, "") |> trim_string()
          visible = character_facts(attrs, :visible_facts, :visible_facts_text, "description")
          private = character_facts(attrs, :gm_private_facts, :private_notes, "notes")
          voice_guidance = attr(attrs, :voice_guidance, %{})

          normalized_voice_guidance = VoiceGuidance.normalize(voice_guidance)

          speaker_id =
            if supplied_speaker_id == "" and name != "" and String.length(name) <= 300 do
              generated_speaker_id(name, row_index, acc)
            else
              supplied_speaker_id
            end

          cond do
            not is_binary(name) or name == "" or String.length(name) > 300 ->
              {:halt,
               {:error,
                {:setup, "GM character #{row_index + 1} needs a name up to 300 characters."}}}

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

            not is_map(visible) or not is_map(private) ->
              {:halt, {:error, {:setup, "GM character facts must be maps."}}}

            match?({:error, _}, normalized_voice_guidance) ->
              {:halt,
               {:error,
                {:setup,
                 "Voice notes need up to 280 characters per field and 1,200 characters total."}}}

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
                      gm_private_facts: private,
                      voice_guidance: elem(normalized_voice_guidance, 1)
                    }
                  ]}}
          end
        end)
    end
  end

  defp normalize_setup_characters(_), do: {:error, {:setup, "GM characters must be a list."}}

  defp generated_speaker_id(name, row_index, existing_characters) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "_")
      |> String.trim("_")
      |> case do
        "" -> "gm_character_#{row_index + 1}"
        slug -> String.slice(slug, 0, 88)
      end
      |> case do
        "player" -> "gm_player"
        slug -> slug
      end

    unique_speaker_id(base, existing_characters, 1)
  end

  defp unique_speaker_id(base, existing_characters, suffix) do
    candidate = if suffix == 1, do: base, else: "#{base}_#{suffix}"

    if Enum.any?(existing_characters, &(&1.speaker_id == candidate)) do
      unique_speaker_id(base, existing_characters, suffix + 1)
    else
      candidate
    end
  end

  defp normalize_player_character_details(rows) when is_list(rows) or is_map(rows) do
    rows = indexed_rows(rows)

    cond do
      length(rows) > 50 ->
        {:error, {:setup, "Add no more than 50 player character details."}}

      true ->
        rows = Enum.reject(rows, fn {_index, attrs} -> blank_row?(attrs) end)

        Enum.reduce_while(rows, {:ok, {%{}, MapSet.new()}}, fn {_index, attrs},
                                                               {:ok, {facts, labels}} ->
          label = attrs |> attr(:label, "") |> trim_string()
          value = attrs |> attr(:value, "") |> trim_string()
          normalized_label = String.downcase(label)

          cond do
            not is_map(attrs) ->
              {:halt, {:error, {:setup, "Player character detail rows must be objects."}}}

            label == "" or String.length(label) > 80 ->
              {:halt,
               {:error,
                {:setup, "Every player character detail needs a label up to 80 characters."}}}

            normalized_label == "description" ->
              {:halt,
               {:error,
                {:setup, "The label 'description' is reserved for the character summary."}}}

            MapSet.member?(labels, normalized_label) ->
              {:halt, {:error, {:setup, "Player character detail labels must be unique."}}}

            value == "" or String.length(value) > 500 ->
              {:halt,
               {:error,
                {:setup, "Every player character detail needs a value up to 500 characters."}}}

            true ->
              {:cont, {:ok, {Map.put(facts, label, value), MapSet.put(labels, normalized_label)}}}
          end
        end)
        |> case do
          {:ok, {facts, _labels}} -> {:ok, facts}
          {:error, _reason} = error -> error
        end
    end
  end

  defp normalize_player_character_details(_rows),
    do: {:error, {:setup, "Player character details must be a list."}}

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
