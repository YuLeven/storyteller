defmodule Storyteller.Repo.Migrations.AddItalianUiLocale do
  use Ecto.Migration

  def up do
    drop constraint(:ui_locale_preferences, :ui_locale_preferences_locale_check)

    create constraint(:ui_locale_preferences, :ui_locale_preferences_locale_check,
             check: "locale IN ('en', 'es', 'fr', 'it')"
           )
  end

  def down do
    execute("UPDATE ui_locale_preferences SET locale = 'en' WHERE locale = 'it'")

    drop constraint(:ui_locale_preferences, :ui_locale_preferences_locale_check)

    create constraint(:ui_locale_preferences, :ui_locale_preferences_locale_check,
             check: "locale IN ('en', 'es', 'fr')"
           )
  end
end
