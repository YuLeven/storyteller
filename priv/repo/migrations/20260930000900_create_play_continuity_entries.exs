defmodule Storyteller.Repo.Migrations.CreatePlayContinuityEntries do
  use Ecto.Migration

  def change do
    create unique_index(:play_events, [:id, :campaign_id],
             name: :play_events_id_campaign_id_index
           )

    create table(:play_continuity_entries) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :entry_id, :string, null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :details, :text, null: false
      add :status, :string, null: false, default: "active"
      add :visibility, :string, null: false
      add :introduced_by_event_id, :bigint, null: false
      add :source_event_id, :bigint, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:play_continuity_entries, [:campaign_id, :entry_id])
    create index(:play_continuity_entries, [:campaign_id, :visibility, :status])
    create index(:play_continuity_entries, [:introduced_by_event_id])
    create index(:play_continuity_entries, [:source_event_id])

    create constraint(:play_continuity_entries, :play_continuity_entries_kind_check,
             check: "kind IN ('fact', 'relationship', 'commitment')"
           )

    create constraint(:play_continuity_entries, :play_continuity_entries_status_check,
             check: "status IN ('active', 'resolved', 'retracted')"
           )

    create constraint(:play_continuity_entries, :play_continuity_entries_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )

    execute(
      "ALTER TABLE play_continuity_entries " <>
        "ADD CONSTRAINT play_continuity_entries_introduced_event_campaign_fkey " <>
        "FOREIGN KEY (introduced_by_event_id, campaign_id) " <>
        "REFERENCES play_events (id, campaign_id) ON DELETE CASCADE",
      "ALTER TABLE play_continuity_entries " <>
        "DROP CONSTRAINT play_continuity_entries_introduced_event_campaign_fkey"
    )

    execute(
      "ALTER TABLE play_continuity_entries " <>
        "ADD CONSTRAINT play_continuity_entries_source_event_campaign_fkey " <>
        "FOREIGN KEY (source_event_id, campaign_id) " <>
        "REFERENCES play_events (id, campaign_id) ON DELETE CASCADE",
      "ALTER TABLE play_continuity_entries " <>
        "DROP CONSTRAINT play_continuity_entries_source_event_campaign_fkey"
    )
  end
end
