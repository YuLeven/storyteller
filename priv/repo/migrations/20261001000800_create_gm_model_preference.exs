defmodule Storyteller.Repo.Migrations.CreateGMModelPreference do
  use Ecto.Migration

  def change do
    create table(:gm_model_preferences, primary_key: false) do
      add :id, :smallint, primary_key: true, default: 1
      add :model_slug, :string

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:gm_model_preferences, :gm_model_preferences_singleton_check,
             check: "id = 1"
           )

    create constraint(:gm_model_preferences, :gm_model_preferences_model_slug_check,
             check: "model_slug IS NULL OR (length(btrim(model_slug)) BETWEEN 1 AND 255)"
           )

    execute(
      "INSERT INTO gm_model_preferences (id, model_slug, inserted_at, updated_at) VALUES (1, NULL, NOW(), NOW())",
      "DELETE FROM gm_model_preferences WHERE id = 1"
    )
  end
end
