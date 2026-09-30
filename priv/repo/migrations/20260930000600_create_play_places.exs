defmodule Storyteller.Repo.Migrations.CreatePlayPlaces do
  use Ecto.Migration

  def change do
    create table(:play_places) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :place_id, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :visibility, :string, null: false, default: "public"
      add :facts, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_places, [:campaign_id, :place_id])
    create index(:play_places, [:campaign_id, :visibility])

    create constraint(:play_places, :play_places_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )

    alter table(:play_characters) do
      add :current_place_id, :string
    end

    create index(:play_characters, [:campaign_id, :current_place_id],
             where: "current_place_id IS NOT NULL"
           )

    execute(
      "ALTER TABLE play_characters " <>
        "ADD CONSTRAINT play_characters_campaign_current_place_fkey " <>
        "FOREIGN KEY (campaign_id, current_place_id) " <>
        "REFERENCES play_places (campaign_id, place_id)",
      "ALTER TABLE play_characters " <>
        "DROP CONSTRAINT play_characters_campaign_current_place_fkey"
    )
  end
end
