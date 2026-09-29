defmodule Storyteller.Repo.Migrations.CreateCampaignsAndSessions do
  use Ecto.Migration

  def change do
    create table(:campaigns) do
      add :title, :string, null: false
      add :premise, :text, null: false
      add :setting, :text, null: false
      add :tone, :text, null: false
      add :narration_language, :string, null: false, default: "English"
      add :player_character, :text, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:campaigns, :campaigns_status_check,
             check: "status IN ('active', 'archived')"
           )

    create table(:sessions) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :status, :string, null: false, default: "active"
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:sessions, :sessions_status_check,
             check: "status IN ('active', 'completed')"
           )

    create index(:sessions, [:campaign_id, :inserted_at])

    create unique_index(:sessions, [:campaign_id],
             where: "status = 'active'",
             name: :one_active_session_per_campaign
           )
  end
end
