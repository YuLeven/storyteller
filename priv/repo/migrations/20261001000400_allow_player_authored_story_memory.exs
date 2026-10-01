defmodule Storyteller.Repo.Migrations.AllowPlayerAuthoredStoryMemory do
  use Ecto.Migration

  def up do
    drop constraint(:play_canon_corrections, :play_canon_corrections_kind_check)

    create constraint(:play_canon_corrections, :play_canon_corrections_kind_check,
             check: "kind IN ('inventory', 'resource', 'location', 'memory')"
           )

    alter table(:play_continuity_entries) do
      modify :introduced_by_event_id, :bigint, null: true
      modify :source_event_id, :bigint, null: true
    end

    create constraint(:play_continuity_entries, :play_continuity_entries_source_pair_check,
             check:
               "(visibility = 'public' AND introduced_by_event_id IS NULL AND source_event_id IS NULL) OR " <>
                 "(introduced_by_event_id IS NOT NULL AND source_event_id IS NOT NULL)"
           )
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM play_canon_corrections WHERE kind = 'memory') OR
         EXISTS (SELECT 1 FROM play_continuity_entries WHERE introduced_by_event_id IS NULL OR source_event_id IS NULL) THEN
        RAISE EXCEPTION 'cannot remove player-authored story memory without deleting saved campaign data';
      END IF;
    END $$;
    """)

    drop constraint(:play_continuity_entries, :play_continuity_entries_source_pair_check)

    alter table(:play_continuity_entries) do
      modify :introduced_by_event_id, :bigint, null: false
      modify :source_event_id, :bigint, null: false
    end

    drop constraint(:play_canon_corrections, :play_canon_corrections_kind_check)

    create constraint(:play_canon_corrections, :play_canon_corrections_kind_check,
             check: "kind IN ('inventory', 'resource', 'location')"
           )
  end
end
