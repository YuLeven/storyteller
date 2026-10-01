defmodule Storyteller.Repo.Migrations.CreatePlayPlaceConnections do
  use Ecto.Migration

  def change do
    create table(:play_place_connections) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :place_a_id, :string, null: false
      add :place_b_id, :string, null: false
      add :travel_minutes, :integer, null: false
      add :scene_relevance, :text
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_place_connections, [:campaign_id, :place_a_id, :place_b_id])
    create index(:play_place_connections, [:campaign_id, :visibility])

    create constraint(:play_place_connections, :play_place_connections_distinct_places_check,
             check: "place_a_id <> place_b_id"
           )

    create constraint(:play_place_connections, :play_place_connections_duration_check,
             check: "travel_minutes BETWEEN 1 AND 10080"
           )

    create constraint(:play_place_connections, :play_place_connections_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )

    execute(
      "ALTER TABLE play_place_connections " <>
        "ADD CONSTRAINT play_place_connections_campaign_place_a_fkey " <>
        "FOREIGN KEY (campaign_id, place_a_id) " <>
        "REFERENCES play_places (campaign_id, place_id)",
      "ALTER TABLE play_place_connections " <>
        "DROP CONSTRAINT play_place_connections_campaign_place_a_fkey"
    )

    execute(
      "ALTER TABLE play_place_connections " <>
        "ADD CONSTRAINT play_place_connections_campaign_place_b_fkey " <>
        "FOREIGN KEY (campaign_id, place_b_id) " <>
        "REFERENCES play_places (campaign_id, place_id)",
      "ALTER TABLE play_place_connections " <>
        "DROP CONSTRAINT play_place_connections_campaign_place_b_fkey"
    )
  end
end
