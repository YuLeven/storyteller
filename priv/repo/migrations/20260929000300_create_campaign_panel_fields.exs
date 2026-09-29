defmodule Storyteller.Repo.Migrations.CreateCampaignPanelFields do
  use Ecto.Migration

  def change do
    create table(:campaign_panel_fields) do
      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :panel, :string, null: false
      add :label, :string, null: false
      add :value_type, :string, null: false
      add :unit, :string
      add :visibility, :string, null: false, default: "public"
      add :value, :map, null: false, default: %{}
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:campaign_panel_fields, [:campaign_id, :key])
    create index(:campaign_panel_fields, [:campaign_id, :panel, :position])

    create constraint(:campaign_panel_fields, :campaign_panel_fields_type_check,
             check: "value_type IN ('quantity', 'money', 'text', 'status', 'date')"
           )

    create constraint(:campaign_panel_fields, :campaign_panel_fields_visibility_check,
             check: "visibility IN ('public', 'gm_private')"
           )

    create constraint(:campaign_panel_fields, :campaign_panel_fields_position_check,
             check: "position >= 0"
           )
  end
end
