defmodule Storyteller.Repo.Migrations.AddGmCharacterDutyReleaseThreshold do
  use Ecto.Migration

  def up do
    alter table(:play_characters) do
      add :duty_release_at_world_minute, :integer
    end

    create constraint(:play_characters, :play_characters_duty_release_check,
             check: "duty_release_at_world_minute IS NULL OR duty_release_at_world_minute >= 0"
           )

    drop constraint(:play_characters, :play_characters_active_duty_check)

    create constraint(:play_characters, :play_characters_active_duty_check,
             check: """
             (duty_name IS NULL AND duty_place_id IS NULL AND duty_release_at_world_minute IS NULL) OR
             (role = 'gm' AND duty_name IS NOT NULL AND length(btrim(duty_name)) BETWEEN 1 AND 160
              AND duty_place_id IS NOT NULL)
             """
           )
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (
        SELECT 1 FROM play_characters
        WHERE duty_release_at_world_minute IS NOT NULL
           OR (duty_name IS NOT NULL AND duty_place_id IS DISTINCT FROM current_place_id)
      ) THEN
        RAISE EXCEPTION 'cannot remove timed or completed duties without deleting saved campaign data';
      END IF;
    END $$;
    """)

    drop constraint(:play_characters, :play_characters_active_duty_check)
    drop constraint(:play_characters, :play_characters_duty_release_check)

    alter table(:play_characters) do
      remove :duty_release_at_world_minute
    end

    create constraint(:play_characters, :play_characters_active_duty_check,
             check: """
             (duty_name IS NULL AND duty_place_id IS NULL) OR
             (role = 'gm' AND duty_name IS NOT NULL AND length(btrim(duty_name)) BETWEEN 1 AND 160
              AND duty_place_id IS NOT NULL AND current_place_id = duty_place_id)
             """
           )
  end
end
