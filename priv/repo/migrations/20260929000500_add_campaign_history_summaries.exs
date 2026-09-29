defmodule Storyteller.Repo.Migrations.AddCampaignHistorySummaries do
  use Ecto.Migration

  def change do
    alter table(:play_states) do
      add :public_history_summary, :text, null: false, default: ""
      add :gm_private_history_summary, :text, null: false, default: ""
    end
  end
end
