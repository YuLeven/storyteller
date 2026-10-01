defmodule Storyteller.Settings.GMModelPreference do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :model_slug]}
  schema "gm_model_preferences" do
    field :model_slug, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [:model_slug])
    |> validate_length(:model_slug, max: 255)
    |> check_constraint(:model_slug, name: :gm_model_preferences_model_slug_check)
  end
end
