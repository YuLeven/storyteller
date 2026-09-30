defmodule Storyteller.Repo.Migrations.CreatePlayObjectives do
  use Ecto.Migration

  def change do
    create table(:play_objectives) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :objective_id, :string, null: false
      add :title, :string, null: false
      add :details, :text
      add :status, :string, null: false, default: "open"
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_objectives, [:campaign_id, :objective_id])
    create index(:play_objectives, [:campaign_id, :visibility, :status])

    create constraint(:play_objectives, :play_objectives_status_check,
             check: "status IN ('open', 'completed', 'abandoned')"
           )

    create constraint(:play_objectives, :play_objectives_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )
  end
end
