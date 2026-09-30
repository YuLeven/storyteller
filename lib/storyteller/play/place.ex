defmodule Storyteller.Play.Place do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_places" do
    field :place_id, :string
    field :name, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: [:public, :gm_private], default: :public
    field :facts, :map, default: %{}

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(place, attrs) do
    place
    |> cast(attrs, [:campaign_id, :place_id, :name, :description, :visibility, :facts])
    |> validate_required([:campaign_id, :place_id, :name, :visibility, :facts])
    |> validate_length(:place_id, min: 1, max: 100)
    |> validate_format(:place_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:name, min: 1, max: 300)
    |> validate_length(:description, max: 10_000)
    |> validate_map(:facts)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint([:campaign_id, :place_id])
    |> check_constraint(:visibility, name: :play_places_visibility_check)
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _ -> add_error(changeset, field, "must be a map")
    end
  end
end
