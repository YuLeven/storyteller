defmodule Storyteller.Repo.Migrations.ReconcilePlayLifecycle do
  use Ecto.Migration

  @moduledoc """
  Installs Play invariants on development databases that applied the first Play
  migration while it was still being drafted. Fresh databases already receive
  these objects from CreatePlayDomain, so every operation here is idempotent.
  """

  def up do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'play_events'::regclass
          AND conname = 'play_events_sequence_check'
      ) THEN
        ALTER TABLE play_events
          ADD CONSTRAINT play_events_sequence_check CHECK (sequence > 0);
      END IF;
    END;
    $$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyteller_fail_play_turns_for_closed_session()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.status = 'active' AND NEW.status = 'completed' THEN
        UPDATE play_turns
        SET status = 'failed', failure_code = 'session_closed',
            resolution_started_at = NULL, attempts = attempts + 1,
            updated_at = now()
        WHERE session_id = NEW.id
          AND status IN ('pending', 'resolving', 'awaiting_roll');
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'sessions'::regclass
          AND tgname = 'play_turns_session_closed'
      ) THEN
        CREATE TRIGGER play_turns_session_closed
        AFTER UPDATE OF status ON sessions
        FOR EACH ROW
        EXECUTE FUNCTION storyteller_fail_play_turns_for_closed_session();
      END IF;
    END;
    $$;
    """)

    execute("""
    CREATE OR REPLACE FUNCTION storyteller_fail_play_turns_for_archived_campaign()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.status = 'active' AND NEW.status = 'archived' THEN
        UPDATE play_turns
        SET status = 'failed', failure_code = 'campaign_archived',
            resolution_started_at = NULL, attempts = attempts + 1,
            updated_at = now()
        WHERE campaign_id = NEW.id
          AND status IN ('pending', 'resolving', 'awaiting_roll');
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'campaigns'::regclass
          AND tgname = 'play_turns_campaign_archived'
      ) THEN
        CREATE TRIGGER play_turns_campaign_archived
        AFTER UPDATE OF status ON campaigns
        FOR EACH ROW
        EXECUTE FUNCTION storyteller_fail_play_turns_for_archived_campaign();
      END IF;
    END;
    $$;
    """)
  end

  # The base Play migration also defines these invariants. Removing them during
  # rollback would leave an applied base migration with an unsafe schema.
  def down, do: :ok
end
