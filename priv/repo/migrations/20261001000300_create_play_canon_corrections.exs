defmodule Storyteller.Repo.Migrations.CreatePlayCanonCorrections do
  use Ecto.Migration

  def change do
    create table(:play_canon_corrections) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :kind, :string, null: false
      add :target_id, :string, null: false
      add :expected_revision, :bigint, null: false
      add :reason, :text, null: false
      add :before_state, :map, null: false
      add :after_state, :map, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:play_canon_corrections, [:campaign_id, :sequence])
    create index(:play_canon_corrections, [:campaign_id, :inserted_at])

    create constraint(:play_canon_corrections, :play_canon_corrections_sequence_check,
             check: "sequence > 0"
           )

    create constraint(:play_canon_corrections, :play_canon_corrections_kind_check,
             check: "kind IN ('inventory', 'resource', 'location')"
           )

    create constraint(:play_canon_corrections, :play_canon_corrections_revision_check,
             check: "expected_revision >= 0"
           )
  end
end
