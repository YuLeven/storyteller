defmodule Storyteller.Repo.Migrations.CreateCampaignAuthoringCorrections do
  use Ecto.Migration

  def change do
    create table(:campaign_authoring_corrections) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :reason, :text, null: false
      add :before_state, :map, null: false
      add :after_state, :map, null: false
      add :contains_private_changes, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:campaign_authoring_corrections, [:campaign_id, :sequence])
    create index(:campaign_authoring_corrections, [:campaign_id, :inserted_at])
  end
end
