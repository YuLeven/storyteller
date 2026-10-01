defmodule Storyteller.CampaignBackup do
  @moduledoc """
  Portable, sensitive JSON backup for one campaign and its complete play history.

  Backups include GM-private canon. Authentication credentials are deliberately
  outside this module and are never exported or imported.
  """

  import Ecto.Query, warn: false

  alias Storyteller.Campaigns.{AuthoringCorrection, Campaign, Session}
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play.{Character, ContinuityEntry, Event, Objective, Place, Roll, State, Turn}
  alias Storyteller.Play.Inventory
  alias Storyteller.Play.VoiceGuidance
  alias Storyteller.Repo

  @format "storyteller.campaign-backup"
  @version 3
  @legacy_version 1
  @previous_version 2
  @max_bytes 52_428_800
  @max_state_bytes 1_000_000
  @turn_statuses [:pending, :resolving, :awaiting_roll, :failed, :superseded, :completed]
  @event_types [
    :player_action,
    :player_question,
    :time_passage,
    :gm_narration,
    :npc_dialogue,
    :character_activity,
    :roll_request,
    :player_roll,
    :state_change
  ]

  @doc "Encodes a complete campaign backup. The result contains GM-private material."
  def export(campaign_id) do
    result =
      if Repo.in_transaction?() or sandbox_repo?() do
        build_backup(campaign_id)
      else
        case Repo.transaction(fn ->
               Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
               build_backup(campaign_id)
             end) do
          {:ok, backup_result} -> backup_result
          {:error, _reason} -> {:error, :backup_unavailable}
        end
      end

    case result do
      {:ok, backup} -> encode_backup(backup)
      error -> error
    end
  end

  defp encode_backup(backup) do
    case Jason.encode(backup, pretty: true) do
      {:ok, binary} when byte_size(binary) <= @max_bytes -> {:ok, binary}
      _ -> {:error, :backup_too_large}
    end
  end

  defp sandbox_repo?, do: Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox

  @doc "Validates a complete backup, then atomically imports it as a new campaign."
  def import(binary) when is_binary(binary) and byte_size(binary) <= @max_bytes do
    with {:ok, decoded} <- Jason.decode(binary),
         {:ok, backup} <- validate_backup(decoded) do
      insert_backup(backup)
    else
      _ -> {:error, :invalid_backup}
    end
  rescue
    _ -> {:error, :invalid_backup}
  end

  def import(_), do: {:error, :invalid_backup}

  defp build_backup(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil ->
        {:error, :not_found}

      campaign ->
        sessions = Repo.all(from(session in Session, where: session.campaign_id == ^campaign_id))
        session_refs = sessions |> ordered() |> refs("session")
        sessions_by_id = Map.new(session_refs, fn {session, ref} -> {session.id, ref} end)

        turns = Repo.all(from(turn in Turn, where: turn.campaign_id == ^campaign_id))
        turn_refs = turns |> ordered() |> refs("turn")
        turns_by_id = Map.new(turn_refs, fn {turn, ref} -> {turn.id, ref} end)

        events = Repo.all(from(event in Event, where: event.campaign_id == ^campaign_id))
        events_by_id = Map.new(events, &{&1.id, &1.sequence})

        with %State{} = state <- Repo.get_by(State, campaign_id: campaign_id) do
          backup = %{
            "format" => @format,
            "schema_version" => @version,
            "data_classification" => "sensitive_gm_private_campaign_data",
            "exported_at" =>
              encode_datetime(DateTime.utc_now() |> DateTime.truncate(:microsecond)),
            "campaign" => export_campaign(campaign),
            "sessions" => Enum.map(session_refs, &export_session(elem(&1, 0), elem(&1, 1))),
            "state" => export_state(state),
            "characters" =>
              Repo.all(from(character in Character, where: character.campaign_id == ^campaign_id))
              |> Enum.map(&export_character(&1, campaign)),
            "places" =>
              Repo.all(from(place in Place, where: place.campaign_id == ^campaign_id))
              |> Enum.map(&export_place/1),
            "panels" =>
              Repo.all(from(panel in PanelField, where: panel.campaign_id == ^campaign_id))
              |> Enum.map(&export_panel/1),
            "objectives" =>
              Repo.all(from(objective in Objective, where: objective.campaign_id == ^campaign_id))
              |> Enum.map(&export_objective/1),
            "turns" =>
              Enum.map(turn_refs, fn {turn, ref} ->
                export_turn(turn, ref, Map.fetch!(sessions_by_id, turn.session_id))
              end),
            "events" =>
              events
              |> Enum.sort_by(& &1.sequence)
              |> Enum.map(fn event ->
                export_event(
                  event,
                  Map.fetch!(sessions_by_id, event.session_id),
                  Map.fetch!(turns_by_id, event.turn_id)
                )
              end),
            "rolls" =>
              Repo.all(
                from(roll in Roll,
                  join: turn in Turn,
                  on: turn.id == roll.turn_id,
                  where: turn.campaign_id == ^campaign_id
                )
              )
              |> Enum.map(&export_roll(&1, Map.fetch!(turns_by_id, &1.turn_id))),
            "authoring_corrections" =>
              Repo.all(
                from(correction in AuthoringCorrection,
                  where: correction.campaign_id == ^campaign_id,
                  order_by: [asc: correction.sequence]
                )
              )
              |> Enum.map(&export_authoring_correction/1),
            "continuity_entries" =>
              Repo.all(from(entry in ContinuityEntry, where: entry.campaign_id == ^campaign_id))
              |> Enum.map(fn entry ->
                export_continuity(
                  entry,
                  Map.fetch!(events_by_id, entry.introduced_by_event_id),
                  Map.fetch!(events_by_id, entry.source_event_id)
                )
              end)
          }

          {:ok, backup}
        else
          _ -> {:error, :campaign_incomplete}
        end
    end
  end

  defp export_campaign(campaign) do
    %{
      "title" => campaign.title,
      "premise" => campaign.premise,
      "setting" => campaign.setting,
      "tone" => campaign.tone,
      "narration_language" => campaign.narration_language,
      "player_character_name" => campaign.player_character_name,
      "player_character" => campaign.player_character,
      "status" => Atom.to_string(campaign.status),
      "inserted_at" => encode_datetime(campaign.inserted_at),
      "updated_at" => encode_datetime(campaign.updated_at)
    }
  end

  defp export_session(session, ref) do
    %{
      "ref" => ref,
      "title" => session.title,
      "status" => Atom.to_string(session.status),
      "ended_at" => encode_datetime(session.ended_at),
      "inserted_at" => encode_datetime(session.inserted_at),
      "updated_at" => encode_datetime(session.updated_at)
    }
  end

  defp export_state(state) do
    %{
      "revision" => state.revision,
      "event_sequence" => state.event_sequence,
      "public_state" => state.public_state,
      "gm_private_state" => state.gm_private_state,
      "public_history_summary" => state.public_history_summary,
      "gm_private_history_summary" => state.gm_private_history_summary,
      "inserted_at" => encode_datetime(state.inserted_at),
      "updated_at" => encode_datetime(state.updated_at)
    }
  end

  defp export_character(character, campaign) do
    %{
      "speaker_id" => character.speaker_id,
      "name" =>
        if(character.speaker_id == "player",
          do: campaign.player_character_name,
          else: character.name
        ),
      "role" => Atom.to_string(character.role),
      "visible_facts" => character.visible_facts,
      "gm_private_facts" => character.gm_private_facts,
      "voice_guidance" => character.voice_guidance,
      "visible_activity" => character.visible_activity,
      "current_place_id" => character.current_place_id,
      "inserted_at" => encode_datetime(character.inserted_at),
      "updated_at" => encode_datetime(character.updated_at)
    }
  end

  defp export_place(place) do
    %{
      "place_id" => place.place_id,
      "name" => place.name,
      "description" => place.description,
      "visibility" => Atom.to_string(place.visibility),
      "facts" => place.facts,
      "inserted_at" => encode_datetime(place.inserted_at),
      "updated_at" => encode_datetime(place.updated_at)
    }
  end

  defp export_panel(panel) do
    %{
      "key" => panel.key,
      "panel" => panel.panel,
      "label" => panel.label,
      "value_type" => Atom.to_string(panel.value_type),
      "unit" => panel.unit,
      "visibility" => Atom.to_string(panel.visibility),
      "value" => panel.value,
      "position" => panel.position,
      "inserted_at" => encode_datetime(panel.inserted_at),
      "updated_at" => encode_datetime(panel.updated_at)
    }
  end

  defp export_objective(objective) do
    %{
      "objective_id" => objective.objective_id,
      "title" => objective.title,
      "details" => objective.details,
      "status" => Atom.to_string(objective.status),
      "visibility" => Atom.to_string(objective.visibility),
      "inserted_at" => encode_datetime(objective.inserted_at),
      "updated_at" => encode_datetime(objective.updated_at)
    }
  end

  defp export_turn(turn, ref, session_ref) do
    %{
      "ref" => ref,
      "session_ref" => session_ref,
      "idempotency_key" => turn.idempotency_key,
      "player_input" => turn.player_input,
      "intent" => Atom.to_string(turn.intent),
      "status" => Atom.to_string(turn.status),
      "resolution_phase" => Atom.to_string(turn.resolution_phase),
      "roll_request" => turn.roll_request,
      "attempts" => turn.attempts,
      "resolution_started_at" => encode_datetime(turn.resolution_started_at),
      "failure_code" => turn.failure_code,
      "failure_stage" => if(turn.failure_stage, do: Atom.to_string(turn.failure_stage)),
      "inserted_at" => encode_datetime(turn.inserted_at),
      "updated_at" => encode_datetime(turn.updated_at)
    }
  end

  defp export_event(event, session_ref, turn_ref) do
    %{
      "sequence" => event.sequence,
      "session_ref" => session_ref,
      "turn_ref" => turn_ref,
      "event_type" => Atom.to_string(event.event_type),
      "visibility" => Atom.to_string(event.visibility),
      "speaker_id" => event.speaker_id,
      "payload" => event.payload,
      "game_time" => event.game_time,
      "inserted_at" => encode_datetime(event.inserted_at)
    }
  end

  defp export_roll(roll, turn_ref) do
    %{
      "turn_ref" => turn_ref,
      "kind" => Atom.to_string(roll.kind),
      "result" => roll.result,
      "authorized_at" => encode_datetime(roll.authorized_at),
      "inserted_at" => encode_datetime(roll.inserted_at)
    }
  end

  defp export_continuity(entry, introduced_sequence, source_sequence) do
    %{
      "entry_id" => entry.entry_id,
      "kind" => Atom.to_string(entry.kind),
      "title" => entry.title,
      "details" => entry.details,
      "status" => Atom.to_string(entry.status),
      "visibility" => Atom.to_string(entry.visibility),
      "introduced_event_sequence" => introduced_sequence,
      "source_event_sequence" => source_sequence,
      "inserted_at" => encode_datetime(entry.inserted_at),
      "updated_at" => encode_datetime(entry.updated_at)
    }
  end

  defp export_authoring_correction(correction) do
    %{
      "sequence" => correction.sequence,
      "reason" => correction.reason,
      "before_state" => correction.before_state,
      "after_state" => correction.after_state,
      "contains_private_changes" => correction.contains_private_changes,
      "inserted_at" => encode_datetime(correction.inserted_at)
    }
  end

  defp validate_backup(backup) when is_map(backup) do
    with :ok <-
           exact_keys(
             backup,
             root_backup_keys(backup["schema_version"]),
             :root
           ),
         true <- backup["format"] == @format,
         true <- backup["schema_version"] in [@legacy_version, @previous_version, @version],
         true <- backup["data_classification"] == "sensitive_gm_private_campaign_data",
         {:ok, _exported_at} <- parse_datetime(backup["exported_at"], false),
         {:ok, campaign} <- validate_campaign(backup["campaign"]),
         {:ok, sessions} <- validate_sessions(backup["sessions"]),
         :ok <- validate_campaign_sessions(campaign, sessions),
         {:ok, characters} <- validate_characters(backup["characters"]),
         {campaign, characters} <- normalize_player_character_name(campaign, characters),
         {:ok, places} <- validate_places(backup["places"]),
         :ok <- validate_character_places(characters, places),
         {:ok, state} <- validate_state(backup["state"], characters),
         {:ok, panels} <- validate_panels(backup["panels"]),
         {:ok, objectives} <- validate_objectives(backup["objectives"]),
         {:ok, turns} <- validate_turns(backup["turns"], sessions, backup["schema_version"]),
         :ok <- validate_open_turns(campaign, sessions, turns),
         {:ok, events} <- validate_events(backup["events"], sessions, turns),
         :ok <- validate_event_sequence(state, events),
         {:ok, rolls} <- validate_rolls(backup["rolls"], turns),
         {:ok, continuity} <- validate_continuity(backup["continuity_entries"], events),
         {:ok, corrections} <-
           validate_authoring_corrections(Map.get(backup, "authoring_corrections", [])) do
      {:ok,
       %{
         campaign: campaign,
         sessions: sessions,
         state: state,
         characters: characters,
         places: places,
         panels: panels,
         objectives: objectives,
         turns: turns,
         events: events,
         rolls: rolls,
         continuity_entries: continuity,
         authoring_corrections: corrections
       }}
    else
      _ -> {:error, :invalid_backup}
    end
  end

  defp validate_backup(_), do: {:error, :invalid_backup}

  defp root_backup_keys(@legacy_version), do: root_backup_keys()

  defp root_backup_keys(version) when version in [@previous_version, @version],
    do: root_backup_keys() ++ ["authoring_corrections"]

  defp root_backup_keys(_), do: []

  defp root_backup_keys do
    ~w(format schema_version data_classification exported_at campaign sessions state characters places panels objectives turns events rolls continuity_entries)
  end

  defp validate_campaign(map) do
    with :ok <-
           exact_keys(
             map,
             if(Map.has_key?(map, "player_character_name"),
               do:
                 ~w(title premise setting tone narration_language player_character_name player_character status inserted_at updated_at),
               else:
                 ~w(title premise setting tone narration_language player_character status inserted_at updated_at)
             ),
             :campaign
           ),
         {:ok, title} <- text(map["title"], 2, 100),
         {:ok, premise} <- text(map["premise"], 0, 10_000),
         {:ok, setting} <- text(map["setting"], 0, 500),
         {:ok, tone} <- text(map["tone"], 0, 300),
         {:ok, language} <- choice(map["narration_language"], ~w(English Spanish French)),
         {:ok, player_character_name} <-
           if(Map.has_key?(map, "player_character_name"),
             do: text(map["player_character_name"], 1, 300),
             else: {:ok, nil}
           ),
         {:ok, player_character} <- text(map["player_character"], 1, 300),
         {:ok, status} <- enum(map["status"], ~w(active archived)),
         {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
         {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
      {:ok,
       %{
         title: title,
         premise: premise,
         setting: setting,
         tone: tone,
         narration_language: language,
         player_character_name: player_character_name,
         player_character: player_character,
         status: status,
         inserted_at: inserted_at,
         updated_at: updated_at
       }}
    end
  end

  defp validate_sessions(rows) when is_list(rows) and length(rows) in 1..1_000_000 do
    with {:ok, sessions} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(ref title status ended_at inserted_at updated_at),
                      :session
                    ),
                  {:ok, ref} <- reference(map["ref"], "session"),
                  {:ok, title} <- text(map["title"], 1, 100),
                  {:ok, status} <- enum(map["status"], ~w(active completed)),
                  {:ok, ended_at} <- parse_datetime(map["ended_at"], true),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false),
                  true <-
                    (status == :active and is_nil(ended_at)) or
                      (status == :completed and not is_nil(ended_at)) do
               {:ok,
                %{
                  ref: ref,
                  title: title,
                  status: status,
                  ended_at: ended_at,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(sessions, & &1.ref) do
      {:ok, sessions}
    end
  end

  defp validate_sessions(_), do: {:error, :invalid_backup}

  defp validate_campaign_sessions(campaign, sessions) do
    active_count = Enum.count(sessions, &(&1.status == :active))

    if active_count <= 1 and
         ((campaign.status == :active and active_count == 1) or
            (campaign.status == :archived and active_count == 0)),
       do: :ok,
       else: {:error, :invalid_backup}
  end

  defp validate_state(map, characters) do
    with :ok <-
           exact_keys(
             map,
             ~w(revision event_sequence public_state gm_private_state public_history_summary gm_private_history_summary inserted_at updated_at),
             :state
           ),
         true <- is_integer(map["revision"]) and map["revision"] >= 0,
         true <- is_integer(map["event_sequence"]) and map["event_sequence"] >= 0,
         {:ok, public_state} <- json_map(map["public_state"], @max_state_bytes),
         {:ok, private_state} <- json_map(map["gm_private_state"], @max_state_bytes),
         {:ok, public_summary} <- text(map["public_history_summary"], 0, 6_000),
         {:ok, private_summary} <- text(map["gm_private_history_summary"], 0, 6_000),
         {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
         {:ok, updated_at} <- parse_datetime(map["updated_at"], false),
         :ok <- validate_inventory_state(public_state, private_state, characters) do
      {:ok,
       %{
         revision: map["revision"],
         event_sequence: map["event_sequence"],
         public_state: public_state,
         gm_private_state: private_state,
         public_history_summary: public_summary,
         gm_private_history_summary: private_summary,
         inserted_at: inserted_at,
         updated_at: updated_at
       }}
    end
  end

  defp validate_inventory_state(public_state, private_state, characters) do
    owners = Enum.map(characters, & &1.speaker_id)
    public_items = Map.get(public_state, "inventory", [])
    private_items = Map.get(private_state, "inventory", [])

    with {:ok, normalized} <- Inventory.normalize_initial(public_items ++ private_items, owners),
         true <- normalized == public_items ++ private_items,
         true <- Enum.all?(public_items, &(is_map(&1) and Map.get(&1, "visibility") == "public")),
         true <-
           Enum.all?(private_items, &(is_map(&1) and Map.get(&1, "visibility") == "gm_private")) do
      :ok
    else
      _ -> {:error, :invalid_backup}
    end
  end

  defp validate_characters(rows) when is_list(rows) and length(rows) in 1..500 do
    with {:ok, characters} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      if(Map.has_key?(map, "voice_guidance"),
                        do:
                          ~w(speaker_id name role visible_facts gm_private_facts voice_guidance visible_activity current_place_id inserted_at updated_at),
                        else:
                          ~w(speaker_id name role visible_facts gm_private_facts visible_activity current_place_id inserted_at updated_at)
                      ),
                      :character
                    ),
                  {:ok, speaker_id} <- stable_id(map["speaker_id"], 100),
                  {:ok, name} <- text(map["name"], 1, 300),
                  {:ok, role} <- enum(map["role"], ~w(player gm)),
                  {:ok, visible_facts} <- json_map(map["visible_facts"], 100_000),
                  {:ok, private_facts} <- json_map(map["gm_private_facts"], 100_000),
                  {:ok, voice_guidance} <-
                    VoiceGuidance.normalize(Map.get(map, "voice_guidance", %{})),
                  {:ok, activity} <- optional_text(map["visible_activity"], 2_000),
                  {:ok, place_id} <- optional_stable_id(map["current_place_id"], 100),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
               {:ok,
                %{
                  speaker_id: speaker_id,
                  name: name,
                  role: role,
                  visible_facts: visible_facts,
                  gm_private_facts: private_facts,
                  voice_guidance: voice_guidance,
                  visible_activity: activity,
                  current_place_id: place_id,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(characters, & &1.speaker_id),
         true <- Enum.count(characters, &(&1.role == :player)) == 1 do
      {:ok, characters}
    end
  end

  defp validate_characters(_), do: {:error, :invalid_backup}

  defp normalize_player_character_name(campaign, characters) do
    player = Enum.find(characters, &(&1.role == :player))
    player_name = campaign.player_character_name || player.name

    campaign = Map.put(campaign, :player_character_name, player_name)

    characters =
      Enum.map(characters, fn
        %{role: :player} = character -> Map.put(character, :name, player_name)
        character -> character
      end)

    {campaign, characters}
  end

  defp validate_places(rows) when is_list(rows) and length(rows) <= 5_000 do
    with {:ok, places} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(place_id name description visibility facts inserted_at updated_at),
                      :place
                    ),
                  {:ok, place_id} <- stable_id(map["place_id"], 100),
                  {:ok, name} <- text(map["name"], 1, 300),
                  {:ok, description} <- optional_text(map["description"], 10_000),
                  {:ok, visibility} <- enum(map["visibility"], ~w(public gm_private)),
                  {:ok, facts} <- json_map(map["facts"], 100_000),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
               {:ok,
                %{
                  place_id: place_id,
                  name: name,
                  description: description,
                  visibility: visibility,
                  facts: facts,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(places, & &1.place_id) do
      {:ok, places}
    end
  end

  defp validate_places(_), do: {:error, :invalid_backup}

  defp validate_character_places(characters, places) do
    place_ids = MapSet.new(places, & &1.place_id)

    if Enum.all?(
         characters,
         &(is_nil(&1.current_place_id) or MapSet.member?(place_ids, &1.current_place_id))
       ),
       do: :ok,
       else: {:error, :invalid_backup}
  end

  defp validate_panels(rows) when is_list(rows) and length(rows) <= 1_000 do
    with {:ok, panels} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(key panel label value_type unit visibility value position inserted_at updated_at),
                      :panel
                    ),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false),
                  true <- is_map(map["value"]) do
               attrs = %{
                 key: map["key"],
                 panel: map["panel"],
                 label: map["label"],
                 value_type: map["value_type"],
                 unit: map["unit"],
                 visibility: map["visibility"],
                 value: map["value"],
                 position: map["position"]
               }

               changeset = PanelField.definition_changeset(attrs)

               if changeset.valid? do
                 field = Ecto.Changeset.apply_changes(changeset)
                 {:ok, %{field | inserted_at: inserted_at, updated_at: updated_at}}
               else
                 {:error, :invalid_backup}
               end
             end
           end),
         :ok <- unique_by(panels, & &1.key) do
      {:ok, panels}
    end
  end

  defp validate_panels(_), do: {:error, :invalid_backup}

  defp validate_objectives(rows) when is_list(rows) and length(rows) <= 5_000 do
    with {:ok, objectives} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(objective_id title details status visibility inserted_at updated_at),
                      :objective
                    ),
                  {:ok, objective_id} <- stable_id(map["objective_id"], 100),
                  {:ok, title} <- text(map["title"], 1, 160),
                  {:ok, details} <- optional_text(map["details"], 2_000),
                  {:ok, status} <- enum(map["status"], ~w(open completed abandoned)),
                  {:ok, visibility} <- enum(map["visibility"], ~w(public gm_private)),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
               {:ok,
                %{
                  objective_id: objective_id,
                  title: title,
                  details: details,
                  status: status,
                  visibility: visibility,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(objectives, & &1.objective_id) do
      {:ok, objectives}
    end
  end

  defp validate_objectives(_), do: {:error, :invalid_backup}

  defp validate_turns(rows, sessions, version)
       when is_list(rows) and length(rows) <= 100_000 do
    session_refs = MapSet.new(sessions, & &1.ref)

    with {:ok, turns} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(map, turn_backup_keys(version), :turn),
                  {:ok, ref} <- reference(map["ref"], "turn"),
                  {:ok, session_ref} <- reference(map["session_ref"], "session"),
                  true <- MapSet.member?(session_refs, session_ref),
                  {:ok, idempotency_key} <- text(map["idempotency_key"], 1, 128),
                  {:ok, player_input} <- text(map["player_input"], 1, 20_000),
                  {:ok, intent} <-
                    enum(
                      Map.get(map, "intent", "action"),
                      ~w(action question time_passage opening_scene)
                    ),
                  {:ok, status} <-
                    enum(map["status"], Enum.map(@turn_statuses, &Atom.to_string/1)),
                  {:ok, phase} <- enum(map["resolution_phase"], ~w(initial after_roll)),
                  {:ok, roll_request} <- optional_json_map(map["roll_request"], 100_000),
                  true <- is_integer(map["attempts"]) and map["attempts"] >= 0,
                  {:ok, resolution_started_at} <-
                    parse_datetime(map["resolution_started_at"], true),
                  {:ok, failure_code} <- optional_text(map["failure_code"], 80),
                  {:ok, failure_stage} <-
                    optional_enum(
                      Map.get(map, "failure_stage"),
                      ~w(context provider response_decoding proposal_validation commit)
                    ),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
               {:ok,
                %{
                  ref: ref,
                  session_ref: session_ref,
                  idempotency_key: idempotency_key,
                  player_input: player_input,
                  intent: intent,
                  status: status,
                  resolution_phase: phase,
                  roll_request: roll_request,
                  attempts: map["attempts"],
                  resolution_started_at: resolution_started_at,
                  failure_code: failure_code,
                  failure_stage: failure_stage,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(turns, & &1.ref),
         :ok <- unique_by(turns, & &1.idempotency_key),
         true <- Enum.count(turns, &(&1.status in [:pending, :resolving, :awaiting_roll])) <= 1 do
      {:ok, turns}
    end
  end

  defp validate_turns(_, _, _), do: {:error, :invalid_backup}

  defp turn_backup_keys(@legacy_version),
    do:
      ~w(ref session_ref idempotency_key player_input status resolution_phase roll_request attempts resolution_started_at failure_code inserted_at updated_at)

  defp turn_backup_keys(@previous_version),
    do:
      ~w(ref session_ref idempotency_key player_input intent status resolution_phase roll_request attempts resolution_started_at failure_code inserted_at updated_at)

  defp turn_backup_keys(@version), do: turn_backup_keys(@previous_version) ++ ["failure_stage"]

  defp optional_enum(nil, _allowed), do: {:ok, nil}
  defp optional_enum(value, allowed), do: enum(value, allowed)

  defp validate_open_turns(campaign, sessions, turns) do
    sessions_by_ref = Map.new(sessions, &{&1.ref, &1})
    open_turns = Enum.filter(turns, &(&1.status in [:pending, :resolving, :awaiting_roll]))

    if open_turns == [] or
         (campaign.status == :active and
            Enum.all?(open_turns, fn turn ->
              Map.fetch!(sessions_by_ref, turn.session_ref).status == :active
            end)),
       do: :ok,
       else: {:error, :invalid_backup}
  end

  defp validate_events(rows, sessions, turns) when is_list(rows) and length(rows) <= 500_000 do
    session_refs = MapSet.new(sessions, & &1.ref)
    turns_by_ref = Map.new(turns, &{&1.ref, &1})

    with {:ok, events} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(sequence session_ref turn_ref event_type visibility speaker_id payload game_time inserted_at),
                      :event
                    ),
                  true <- is_integer(map["sequence"]) and map["sequence"] > 0,
                  {:ok, session_ref} <- reference(map["session_ref"], "session"),
                  true <- MapSet.member?(session_refs, session_ref),
                  {:ok, turn_ref} <- reference(map["turn_ref"], "turn"),
                  %{} = turn <- Map.get(turns_by_ref, turn_ref),
                  true <- turn.session_ref == session_ref,
                  {:ok, event_type} <-
                    enum(map["event_type"], Enum.map(@event_types, &Atom.to_string/1)),
                  {:ok, visibility} <- enum(map["visibility"], ~w(public gm_private)),
                  {:ok, speaker_id} <- optional_stable_id(map["speaker_id"], 100),
                  {:ok, payload} <- json_map(map["payload"], 100_000),
                  {:ok, game_time} <- optional_json_map(map["game_time"], 10_000),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false) do
               {:ok,
                %{
                  sequence: map["sequence"],
                  session_ref: session_ref,
                  turn_ref: turn_ref,
                  event_type: event_type,
                  visibility: visibility,
                  speaker_id: speaker_id,
                  payload: payload,
                  game_time: game_time,
                  inserted_at: inserted_at
                }}
             end
           end),
         :ok <- unique_by(events, & &1.sequence) do
      {:ok, events}
    end
  end

  defp validate_events(_, _, _), do: {:error, :invalid_backup}

  defp validate_event_sequence(state, events) do
    max_sequence = Enum.reduce(events, 0, &max(&1.sequence, &2))
    if state.event_sequence >= max_sequence, do: :ok, else: {:error, :invalid_backup}
  end

  defp validate_rolls(rows, turns) when is_list(rows) and length(rows) <= 100_000 do
    turn_refs = MapSet.new(turns, & &1.ref)

    with {:ok, rolls} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(map, ~w(turn_ref kind result authorized_at inserted_at), :roll),
                  {:ok, turn_ref} <- reference(map["turn_ref"], "turn"),
                  true <- MapSet.member?(turn_refs, turn_ref),
                  {:ok, kind} <- enum(map["kind"], ~w(player_click)),
                  true <- is_integer(map["result"]) and map["result"] in 1..20,
                  {:ok, authorized_at} <- parse_datetime(map["authorized_at"], false),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false) do
               {:ok,
                %{
                  turn_ref: turn_ref,
                  kind: kind,
                  result: map["result"],
                  authorized_at: authorized_at,
                  inserted_at: inserted_at
                }}
             end
           end),
         :ok <- unique_by(rolls, & &1.turn_ref) do
      {:ok, rolls}
    end
  end

  defp validate_rolls(_, _), do: {:error, :invalid_backup}

  defp validate_continuity(rows, events) when is_list(rows) and length(rows) <= 100 do
    sequences = MapSet.new(events, & &1.sequence)

    with {:ok, entries} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(entry_id kind title details status visibility introduced_event_sequence source_event_sequence inserted_at updated_at),
                      :continuity
                    ),
                  {:ok, entry_id} <- stable_id(map["entry_id"], 100),
                  {:ok, kind} <- enum(map["kind"], ~w(fact relationship commitment)),
                  {:ok, title} <- text(map["title"], 1, 120),
                  {:ok, details} <- text(map["details"], 1, 500),
                  {:ok, status} <- enum(map["status"], ~w(active resolved retracted)),
                  {:ok, visibility} <- enum(map["visibility"], ~w(public gm_private)),
                  introduced when is_integer(introduced) and introduced > 0 <-
                    map["introduced_event_sequence"],
                  source when is_integer(source) and source > 0 <- map["source_event_sequence"],
                  true <-
                    MapSet.member?(sequences, introduced) and MapSet.member?(sequences, source),
                  true <- source >= introduced,
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  {:ok, updated_at} <- parse_datetime(map["updated_at"], false) do
               {:ok,
                %{
                  entry_id: entry_id,
                  kind: kind,
                  title: title,
                  details: details,
                  status: status,
                  visibility: visibility,
                  introduced_event_sequence: introduced,
                  source_event_sequence: source,
                  inserted_at: inserted_at,
                  updated_at: updated_at
                }}
             end
           end),
         :ok <- unique_by(entries, & &1.entry_id) do
      {:ok, entries}
    end
  end

  defp validate_continuity(_, _), do: {:error, :invalid_backup}

  defp validate_authoring_corrections(rows) when is_list(rows) and length(rows) <= 100_000 do
    with {:ok, corrections} <-
           map_rows(rows, fn map ->
             with :ok <-
                    exact_keys(
                      map,
                      ~w(sequence reason before_state after_state contains_private_changes inserted_at),
                      :authoring_correction
                    ),
                  sequence when is_integer(sequence) and sequence in 1..1_000_000 <-
                    map["sequence"],
                  {:ok, reason} <- text(map["reason"], 1, 1_000),
                  true <- String.trim(reason) == reason,
                  {:ok, before_state} <- validate_authoring_state(map["before_state"]),
                  {:ok, after_state} <- validate_authoring_state(map["after_state"]),
                  true <-
                    authoring_state_paths(before_state) == authoring_state_paths(after_state),
                  private? when is_boolean(private?) <- map["contains_private_changes"],
                  true <- private? == private_authoring_state?(before_state),
                  {:ok, inserted_at} <- parse_datetime(map["inserted_at"], false),
                  true <- authoring_state_paths(before_state) != [] do
               {:ok,
                %{
                  sequence: sequence,
                  reason: reason,
                  before_state: before_state,
                  after_state: after_state,
                  contains_private_changes: private?,
                  inserted_at: inserted_at
                }}
             end
           end),
         :ok <- unique_by(corrections, & &1.sequence) do
      {:ok, Enum.sort_by(corrections, & &1.sequence)}
    end
  end

  defp validate_authoring_corrections(_), do: {:error, :invalid_backup}

  defp validate_authoring_state(state) when is_map(state) do
    with true <-
           Enum.all?(Map.keys(state), &(&1 in ~w(campaign player_character gm_characters))),
         true <- map_size(state) > 0,
         true <- valid_campaign_correction_fields?(Map.get(state, "campaign", %{})),
         true <- valid_character_correction_fields?(Map.get(state, "player_character", %{})),
         true <- valid_gm_correction_fields?(Map.get(state, "gm_characters", %{})) do
      {:ok, state}
    else
      _ -> {:error, :invalid_backup}
    end
  end

  defp validate_authoring_state(_), do: {:error, :invalid_backup}

  defp valid_campaign_correction_fields?(fields) when is_map(fields) do
    Enum.all?(fields, fn {key, value} ->
      key in ~w(title premise setting tone narration_language player_character_name player_character) and
        correction_value?(value)
    end)
  end

  defp valid_campaign_correction_fields?(_), do: false

  defp valid_character_correction_fields?(fields) when is_map(fields) do
    Enum.all?(fields, fn {key, value} ->
      key in ~w(name description) and correction_value?(value)
    end)
  end

  defp valid_character_correction_fields?(_), do: false

  defp valid_gm_correction_fields?(characters) when is_map(characters) do
    Enum.all?(characters, fn {speaker_id, sections} ->
      with {:ok, _speaker_id} <- stable_id(speaker_id, 100),
           true <- speaker_id != "player",
           true <- is_map(sections),
           true <-
             Enum.all?(sections, fn {section, fields} ->
               allowed_fields =
                 case section do
                   "visible_facts" -> ["description"]
                   "gm_private_facts" -> ["notes"]
                   "voice_guidance" -> Storyteller.Play.VoiceGuidance.fields()
                   _ -> []
                 end

               is_map(fields) and map_size(fields) > 0 and
                 Enum.all?(fields, fn {key, value} ->
                   key in allowed_fields and correction_value?(value)
                 end)
             end) do
        map_size(sections) > 0
      else
        _ -> false
      end
    end)
  end

  defp valid_gm_correction_fields?(_), do: false

  defp correction_value?(nil), do: true

  defp correction_value?(value),
    do: is_binary(value) and String.valid?(value) and String.length(value) <= 10_000

  defp private_authoring_state?(%{"gm_characters" => characters}) do
    Enum.any?(characters, fn {_speaker, sections} ->
      Map.has_key?(sections, "gm_private_facts") or Map.has_key?(sections, "voice_guidance")
    end)
  end

  defp private_authoring_state?(_), do: false

  defp authoring_state_paths(state) do
    flatten_authoring_paths(state, []) |> Enum.sort()
  end

  defp flatten_authoring_paths(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      if is_map(value),
        do: flatten_authoring_paths(value, prefix ++ [key]),
        else: [prefix ++ [key]]
    end)
  end

  defp insert_backup(backup) do
    Repo.transaction(fn ->
      campaign = insert_campaign!(backup.campaign)
      insert_authoring_corrections!(campaign.id, backup.authoring_corrections)
      sessions_by_ref = insert_sessions!(campaign.id, backup.sessions)
      insert_state!(campaign.id, backup.state)
      insert_places!(campaign.id, backup.places)
      insert_characters!(campaign.id, backup.characters)
      insert_panels!(campaign.id, backup.panels)
      insert_objectives!(campaign.id, backup.objectives)
      turns_by_ref = insert_turns!(campaign.id, sessions_by_ref, backup.turns)

      events_by_sequence =
        insert_events!(campaign.id, sessions_by_ref, turns_by_ref, backup.events)

      insert_rolls!(turns_by_ref, backup.rolls)
      insert_continuity!(campaign.id, events_by_sequence, backup.continuity_entries)
      campaign
    end)
    |> case do
      {:ok, campaign} -> {:ok, campaign}
      {:error, _reason} -> {:error, :import_failed}
    end
  end

  defp insert_authoring_corrections!(campaign_id, corrections) do
    Enum.each(corrections, fn correction ->
      attrs = Map.put(correction, :campaign_id, campaign_id)

      %AuthoringCorrection{inserted_at: correction.inserted_at}
      |> AuthoringCorrection.changeset(Map.drop(attrs, [:inserted_at]))
      |> insert_or_rollback!()
    end)
  end

  defp insert_campaign!(attrs) do
    %Campaign{inserted_at: attrs.inserted_at, updated_at: attrs.updated_at}
    |> Campaign.changeset(Map.drop(attrs, [:inserted_at, :updated_at]))
    |> insert_or_rollback!()
  end

  defp insert_sessions!(campaign_id, sessions) do
    Map.new(sessions, fn session ->
      changeset =
        %Session{inserted_at: session.inserted_at, updated_at: session.updated_at}
        |> Session.changeset(
          Map.merge(Map.drop(session, [:ref, :inserted_at, :updated_at]), %{
            campaign_id: campaign_id
          })
        )

      {session.ref, insert_or_rollback!(changeset)}
    end)
  end

  defp insert_state!(campaign_id, state) do
    attrs = Map.put(state, :campaign_id, campaign_id)

    %State{inserted_at: state.inserted_at, updated_at: state.updated_at}
    |> State.changeset(Map.drop(attrs, [:inserted_at, :updated_at]))
    |> insert_or_rollback!()
  end

  defp insert_places!(campaign_id, places) do
    Enum.each(places, fn place ->
      attrs = Map.put(place, :campaign_id, campaign_id)

      %Place{inserted_at: place.inserted_at, updated_at: place.updated_at}
      |> Place.changeset(Map.drop(attrs, [:inserted_at, :updated_at]))
      |> insert_or_rollback!()
    end)
  end

  defp insert_characters!(campaign_id, characters) do
    Enum.each(characters, fn character ->
      attrs = Map.put(character, :campaign_id, campaign_id)

      %Character{inserted_at: character.inserted_at, updated_at: character.updated_at}
      |> Character.changeset(Map.drop(attrs, [:inserted_at, :updated_at]))
      |> insert_or_rollback!()
    end)
  end

  defp insert_panels!(campaign_id, panels) do
    Enum.each(panels, fn panel ->
      attrs =
        panel
        |> Map.from_struct()
        |> Map.merge(%{campaign_id: campaign_id})
        |> Map.drop([:id, :__meta__, :initial_value])

      %PanelField{inserted_at: panel.inserted_at, updated_at: panel.updated_at}
      |> PanelField.changeset(attrs)
      |> insert_or_rollback!()
    end)
  end

  defp insert_objectives!(campaign_id, objectives) do
    Enum.each(objectives, fn objective ->
      attrs = Map.put(objective, :campaign_id, campaign_id)

      %Objective{inserted_at: objective.inserted_at, updated_at: objective.updated_at}
      |> Objective.changeset(Map.drop(attrs, [:inserted_at, :updated_at]))
      |> insert_or_rollback!()
    end)
  end

  defp insert_turns!(campaign_id, sessions_by_ref, turns) do
    Map.new(turns, fn turn ->
      interrupted? = turn.status in [:pending, :resolving]
      status = if interrupted?, do: :failed, else: turn.status

      failure_code =
        if interrupted?, do: "backup_interrupted", else: turn.failure_code

      attempts = if interrupted?, do: turn.attempts + 1, else: turn.attempts

      attrs = %{
        campaign_id: campaign_id,
        session_id: Map.fetch!(sessions_by_ref, turn.session_ref).id,
        idempotency_key: turn.idempotency_key,
        request_hash:
          request_hash(
            Map.fetch!(sessions_by_ref, turn.session_ref).id,
            turn.player_input,
            turn.intent
          ),
        player_input: turn.player_input,
        intent: turn.intent,
        status: status,
        resolution_phase: turn.resolution_phase,
        roll_request: turn.roll_request,
        attempts: attempts,
        resolution_started_at: if(interrupted?, do: nil, else: turn.resolution_started_at),
        failure_code: failure_code,
        failure_stage: if(interrupted?, do: nil, else: turn.failure_stage)
      }

      turn_struct = %Turn{inserted_at: turn.inserted_at, updated_at: turn.updated_at}
      {turn.ref, turn_struct |> Turn.changeset(attrs) |> insert_or_rollback!()}
    end)
  end

  defp insert_events!(campaign_id, sessions_by_ref, turns_by_ref, events) do
    Map.new(events, fn event ->
      attrs = %{
        campaign_id: campaign_id,
        session_id: Map.fetch!(sessions_by_ref, event.session_ref).id,
        turn_id: Map.fetch!(turns_by_ref, event.turn_ref).id,
        sequence: event.sequence,
        event_type: event.event_type,
        visibility: event.visibility,
        speaker_id: event.speaker_id,
        payload: event.payload,
        game_time: event.game_time
      }

      changeset = %Event{inserted_at: event.inserted_at} |> Event.changeset(attrs)
      {event.sequence, insert_or_rollback!(changeset)}
    end)
  end

  defp insert_rolls!(turns_by_ref, rolls) do
    Enum.each(rolls, fn roll ->
      attrs = %{
        turn_id: Map.fetch!(turns_by_ref, roll.turn_ref).id,
        kind: roll.kind,
        result: roll.result,
        authorized_at: roll.authorized_at
      }

      %Roll{inserted_at: roll.inserted_at}
      |> Roll.changeset(attrs)
      |> insert_or_rollback!()
    end)
  end

  defp insert_continuity!(campaign_id, events_by_sequence, entries) do
    Enum.each(entries, fn entry ->
      attrs = %{
        campaign_id: campaign_id,
        entry_id: entry.entry_id,
        kind: entry.kind,
        title: entry.title,
        details: entry.details,
        status: entry.status,
        visibility: entry.visibility,
        introduced_by_event_id:
          Map.fetch!(events_by_sequence, entry.introduced_event_sequence).id,
        source_event_id: Map.fetch!(events_by_sequence, entry.source_event_sequence).id
      }

      %ContinuityEntry{inserted_at: entry.inserted_at, updated_at: entry.updated_at}
      |> ContinuityEntry.changeset(attrs)
      |> insert_or_rollback!()
    end)
  end

  defp insert_or_rollback!(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, _changeset} -> Repo.rollback(:invalid_backup)
    end
  end

  defp request_hash(session_id, input, :action) do
    :crypto.hash(:sha256, "#{session_id}\0#{input}") |> Base.encode16(case: :lower)
  end

  defp request_hash(session_id, input, intent) do
    :crypto.hash(:sha256, "#{session_id}\0#{intent}\0#{input}") |> Base.encode16(case: :lower)
  end

  defp refs(records, prefix) do
    records
    |> Enum.with_index(1)
    |> Enum.map(fn {record, index} -> {record, "#{prefix}-#{index}"} end)
  end

  defp ordered(records), do: Enum.sort_by(records, &{&1.inserted_at, &1.id})

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp parse_datetime(nil, true), do: {:ok, nil}

  defp parse_datetime(value, _nullable) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, %DateTime{utc_offset: 0, std_offset: 0} = datetime, 0} ->
        {:ok, DateTime.truncate(datetime, :microsecond)}

      _ ->
        {:error, :invalid_backup}
    end
  end

  defp parse_datetime(_, _), do: {:error, :invalid_backup}

  defp exact_keys(map, expected, _context) when is_map(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(expected), do: :ok, else: {:error, :invalid_backup}
  end

  defp exact_keys(_, _, _), do: {:error, :invalid_backup}

  defp map_rows(rows, fun) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case fun.(row) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        _ -> {:halt, {:error, :invalid_backup}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp unique_by(rows, fun) do
    values = Enum.map(rows, fun)
    if length(values) == length(Enum.uniq(values)), do: :ok, else: {:error, :invalid_backup}
  end

  defp enum(value, allowed) when is_binary(value) do
    if value in allowed,
      do: {:ok, String.to_existing_atom(value)},
      else: {:error, :invalid_backup}
  rescue
    ArgumentError -> {:error, :invalid_backup}
  end

  defp enum(_, _), do: {:error, :invalid_backup}

  defp choice(value, allowed) when is_binary(value) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_backup}
  end

  defp choice(_, _), do: {:error, :invalid_backup}

  defp reference(value, prefix) when is_binary(value) do
    if Regex.match?(~r/\A#{prefix}-[1-9][0-9]*\z/, value),
      do: {:ok, value},
      else: {:error, :invalid_backup}
  end

  defp reference(_, _), do: {:error, :invalid_backup}

  defp stable_id(value, max) when is_binary(value) do
    if String.length(value) in 1..max and Regex.match?(~r/\A[a-zA-Z0-9:_-]+\z/, value),
      do: {:ok, value},
      else: {:error, :invalid_backup}
  end

  defp stable_id(_, _), do: {:error, :invalid_backup}

  defp optional_stable_id(nil, _max), do: {:ok, nil}
  defp optional_stable_id(value, max), do: stable_id(value, max)

  defp text(value, min, max) when is_binary(value) do
    if String.valid?(value) and String.length(value) in min..max,
      do: {:ok, value},
      else: {:error, :invalid_backup}
  end

  defp text(_, _, _), do: {:error, :invalid_backup}

  defp optional_text(nil, _max), do: {:ok, nil}
  defp optional_text(value, max), do: text(value, 0, max)

  defp json_map(map, max_bytes) when is_map(map) do
    case Jason.encode(map) do
      {:ok, binary} when byte_size(binary) <= max_bytes ->
        if Enum.all?(Map.keys(map), &is_binary/1), do: {:ok, map}, else: {:error, :invalid_backup}

      _ ->
        {:error, :invalid_backup}
    end
  end

  defp json_map(_, _), do: {:error, :invalid_backup}

  defp optional_json_map(nil, _max), do: {:ok, nil}
  defp optional_json_map(value, max), do: json_map(value, max)
end
