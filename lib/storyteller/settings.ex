defmodule Storyteller.Settings do
  @moduledoc "Persistent preferences for the local interface and GM behavior."

  alias Storyteller.Repo
  alias Storyteller.Settings.GMModelPreference
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

  def preferred_gm_model do
    case Repo.get(GMModelPreference, 1) do
      %GMModelPreference{model_slug: model_slug} -> model_slug
      nil -> nil
    end
  end

  def set_preferred_gm_model(model_slug) when is_nil(model_slug) or is_binary(model_slug) do
    preference = Repo.get(GMModelPreference, 1) || %GMModelPreference{id: 1}

    preference
    |> GMModelPreference.changeset(%{model_slug: model_slug})
    |> Repo.insert_or_update()
  end

  def set_preferred_gm_model(_model_slug), do: {:error, :invalid_model}

  def supported_ui_locales, do: @locales
end
