defmodule Storyteller.Repo.Migrations.CreatePlayDomain do
  use Ecto.Migration

  def change do
    create unique_index(:sessions, [:id, :campaign_id], name: :sessions_id_campaign_id_index)

    create table(:play_states) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :revision, :bigint, null: false, default: 0
      add :event_sequence, :bigint, null: false, default: 0
      add :public_state, :map, null: false, default: %{}
      add :gm_private_state, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_states, [:campaign_id])

    create constraint(:play_states, :play_states_counters_check,
             check: "revision >= 0 AND event_sequence >= 0"
           )

    create table(:play_characters) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :speaker_id, :string, null: false
      add :name, :string, null: false
      add :role, :string, null: false
      add :visible_facts, :map, null: false, default: %{}
      add :gm_private_facts, :map, null: false, default: %{}
      add :visible_activity, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_characters, [:campaign_id, :speaker_id])

    create unique_index(:play_characters, [:campaign_id],
             where: "role = 'player'",
             name: :one_player_character_per_campaign
           )

    create index(:play_characters, [:campaign_id, :role])

    create constraint(:play_characters, :play_characters_role_check,
             check: "role IN ('player', 'gm')"
           )

    create table(:play_turns) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :idempotency_key, :string, null: false
      add :request_hash, :string, null: false
      add :player_input, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :resolution_phase, :string, null: false, default: "initial"
      add :roll_request, :map
      add :attempts, :integer, null: false, default: 0
      add :resolution_started_at, :utc_datetime_usec
      add :failure_code, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_turns, [:campaign_id, :idempotency_key])

    create unique_index(:play_turns, [:id, :campaign_id, :session_id],
             name: :play_turns_id_campaign_session_index
           )

    create unique_index(:play_turns, [:campaign_id],
             where: "status IN ('pending', 'resolving', 'awaiting_roll')",
             name: :one_open_turn_per_campaign
           )

    create index(:play_turns, [:session_id, :inserted_at])

    create constraint(:play_turns, :play_turns_status_check,
             check:
               "status IN ('pending', 'resolving', 'awaiting_roll', 'failed', 'superseded', 'completed')"
           )

    create constraint(:play_turns, :play_turns_phase_check,
             check: "resolution_phase IN ('initial', 'after_roll')"
           )

    create constraint(:play_turns, :play_turns_attempts_check, check: "attempts >= 0")

    create table(:play_rolls) do
      add :turn_id, references(:play_turns, on_delete: :delete_all), null: false
      add :kind, :string, null: false, default: "player_click"
      add :result, :smallint, null: false
      add :authorized_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:play_rolls, [:turn_id])
    create constraint(:play_rolls, :play_rolls_kind_check, check: "kind IN ('player_click')")

    create constraint(:play_rolls, :play_rolls_d20_result_check,
             check: "result >= 1 AND result <= 20"
           )

    create table(:play_events) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :turn_id, references(:play_turns, on_delete: :delete_all), null: false
      add :sequence, :bigint, null: false
      add :event_type, :string, null: false
      add :visibility, :string, null: false, default: "public"
      add :speaker_id, :string
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:play_events, [:campaign_id, :sequence])
    create index(:play_events, [:campaign_id, :session_id, :sequence])
    create index(:play_events, [:turn_id, :sequence])

    create constraint(:play_events, :play_events_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )

    create constraint(:play_events, :play_events_type_check,
             check:
               "event_type IN ('player_action', 'gm_narration', 'npc_dialogue', 'character_activity', 'roll_request', 'player_roll', 'state_change')"
           )

    create constraint(:play_events, :play_events_sequence_check, check: "sequence > 0")

    execute(
      "ALTER TABLE play_turns ADD CONSTRAINT play_turns_session_campaign_fkey " <>
        "FOREIGN KEY (session_id, campaign_id) REFERENCES sessions (id, campaign_id) ON DELETE CASCADE",
      "ALTER TABLE play_turns DROP CONSTRAINT play_turns_session_campaign_fkey"
    )

    execute(
      "ALTER TABLE play_events ADD CONSTRAINT play_events_turn_session_campaign_fkey " <>
        "FOREIGN KEY (turn_id, campaign_id, session_id) REFERENCES play_turns (id, campaign_id, session_id) ON DELETE CASCADE",
      "ALTER TABLE play_events DROP CONSTRAINT play_events_turn_session_campaign_fkey"
    )

    execute(
      "CREATE FUNCTION storyteller_fail_play_turns_for_closed_session() RETURNS trigger AS $$ " <>
        "BEGIN " <>
        "IF OLD.status = 'active' AND NEW.status = 'completed' THEN " <>
        "UPDATE play_turns SET status = 'failed', failure_code = 'session_closed', " <>
        "resolution_started_at = NULL, attempts = attempts + 1, updated_at = now() " <>
        "WHERE session_id = NEW.id AND status IN ('pending', 'resolving', 'awaiting_roll'); " <>
        "END IF; RETURN NEW; END; $$ LANGUAGE plpgsql",
      "DROP FUNCTION storyteller_fail_play_turns_for_closed_session()"
    )

    execute(
      "CREATE TRIGGER play_turns_session_closed AFTER UPDATE OF status ON sessions " <>
        "FOR EACH ROW EXECUTE FUNCTION storyteller_fail_play_turns_for_closed_session()",
      "DROP TRIGGER play_turns_session_closed ON sessions"
    )

    execute(
      "CREATE FUNCTION storyteller_fail_play_turns_for_archived_campaign() RETURNS trigger AS $$ " <>
        "BEGIN " <>
        "IF OLD.status = 'active' AND NEW.status = 'archived' THEN " <>
        "UPDATE play_turns SET status = 'failed', failure_code = 'campaign_archived', " <>
        "resolution_started_at = NULL, attempts = attempts + 1, updated_at = now() " <>
        "WHERE campaign_id = NEW.id AND status IN ('pending', 'resolving', 'awaiting_roll'); " <>
        "END IF; RETURN NEW; END; $$ LANGUAGE plpgsql",
      "DROP FUNCTION storyteller_fail_play_turns_for_archived_campaign()"
    )

    execute(
      "CREATE TRIGGER play_turns_campaign_archived AFTER UPDATE OF status ON campaigns " <>
        "FOR EACH ROW EXECUTE FUNCTION storyteller_fail_play_turns_for_archived_campaign()",
      "DROP TRIGGER play_turns_campaign_archived ON campaigns"
    )
  end
end
