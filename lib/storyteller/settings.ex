defmodule Storyteller.Settings do
  @moduledoc "Persistent, local-player interface preferences."

  alias Storyteller.Repo
  alias Storyteller.Settings.UILocalePreference

  @locales ~w(en es fr)

  def ui_locale do
    case Repo.get(UILocalePreference, 1) do
      %UILocalePreference{locale: locale} -> locale
      nil -> "en"
    end
  end

  def set_ui_locale(locale) when locale in @locales do
    preference = Repo.get(UILocalePreference, 1) || %UILocalePreference{id: 1}

    preference
    |> UILocalePreference.changeset(%{locale: locale})
    |> Repo.insert_or_update()
  end

  def set_ui_locale(_locale), do: {:error, :invalid_locale}

  def supported_ui_locales, do: @locales
end
