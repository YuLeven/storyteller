defmodule Storyteller.Repo.Migrations.CreateUiLocalePreference do
  use Ecto.Migration

  def change do
    create table(:ui_locale_preferences, primary_key: false) do
      add :id, :smallint, primary_key: true, default: 1
      add :locale, :string, null: false, default: "en"

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:ui_locale_preferences, :ui_locale_preferences_singleton_check,
             check: "id = 1"
           )

    create constraint(:ui_locale_preferences, :ui_locale_preferences_locale_check,
             check: "locale IN ('en', 'es', 'fr')"
           )

    execute(
      "INSERT INTO ui_locale_preferences (id, locale, inserted_at, updated_at) VALUES (1, 'en', NOW(), NOW())",
      "DELETE FROM ui_locale_preferences WHERE id = 1"
    )
  end
end
