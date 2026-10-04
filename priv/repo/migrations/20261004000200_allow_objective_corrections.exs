defmodule Storyteller.Repo.Migrations.AllowObjectiveCorrections do
  use Ecto.Migration

  def up do
    drop constraint(:play_canon_corrections, :play_canon_corrections_kind_check)

    create constraint(:play_canon_corrections, :play_canon_corrections_kind_check,
             check:
               "kind IN ('inventory', 'resource', 'location', 'memory', 'world', 'place', 'travel_connection', 'objective')"
           )
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM play_canon_corrections WHERE kind = 'objective') THEN
        RAISE EXCEPTION 'cannot remove objective corrections without deleting saved campaign data';
      END IF;
    END $$;
    """)

    drop constraint(:play_canon_corrections, :play_canon_corrections_kind_check)

    create constraint(:play_canon_corrections, :play_canon_corrections_kind_check,
             check:
               "kind IN ('inventory', 'resource', 'location', 'memory', 'world', 'place', 'travel_connection')"
           )
  end
end
