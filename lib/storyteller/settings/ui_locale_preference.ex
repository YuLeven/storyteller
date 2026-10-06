defmodule Storyteller.Settings.UILocalePreference do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :locale]}
  schema "ui_locale_preferences" do
    field :locale, :string, default: "en"

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:locale])
    |> validate_required([:locale])
    |> validate_inclusion(:locale, ["en", "es", "fr", "it"])
  end
end
