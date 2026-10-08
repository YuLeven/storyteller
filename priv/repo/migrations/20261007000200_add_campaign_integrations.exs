defmodule Storyteller.Repo.Migrations.AddCampaignIntegrations do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :integrations, :map, null: false, default: %{}
    end
  end
end
