defmodule Storyteller.Repo.Migrations.AddGmCharacterActiveDuties do
  use Ecto.Migration

  def up do
    alter table(:play_characters) do
      add :duty_name, :string
      add :duty_place_id, :string
    end

    execute(
      "ALTER TABLE play_characters " <>
        "ADD CONSTRAINT play_characters_campaign_duty_place_fkey " <>
        "FOREIGN KEY (campaign_id, duty_place_id) " <>
        "REFERENCES play_places (campaign_id, place_id)",
      "ALTER TABLE play_characters " <>
        "DROP CONSTRAINT play_characters_campaign_duty_place_fkey"
    )

    create constraint(:play_characters, :play_characters_active_duty_check,
             check: """
             (duty_name IS NULL AND duty_place_id IS NULL) OR
             (role = 'gm' AND duty_name IS NOT NULL AND length(btrim(duty_name)) BETWEEN 1 AND 160
              AND duty_place_id IS NOT NULL AND current_place_id = duty_place_id)
             """
           )
  end

  def down do
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM play_characters WHERE duty_name IS NOT NULL OR duty_place_id IS NOT NULL) THEN
        RAISE EXCEPTION 'cannot remove active duties without deleting saved campaign data';
      END IF;
    END $$;
    """)

    drop constraint(:play_characters, :play_characters_active_duty_check)

    execute(
      "ALTER TABLE play_characters " <>
        "DROP CONSTRAINT play_characters_campaign_duty_place_fkey"
    )

    alter table(:play_characters) do
      remove :duty_place_id
      remove :duty_name
    end
  end
end
