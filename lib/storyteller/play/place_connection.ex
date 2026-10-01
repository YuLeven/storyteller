defmodule Storyteller.Play.PlaceConnection do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_place_connections" do
    field :place_a_id, :string
    field :place_b_id, :string
    field :travel_minutes, :integer
    field :scene_relevance, :string
    field :visibility, Ecto.Enum, values: [:public, :gm_private], default: :public

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :campaign_id,
      :place_a_id,
      :place_b_id,
      :travel_minutes,
      :scene_relevance,
      :visibility
    ])
    |> validate_required([
      :campaign_id,
      :place_a_id,
      :place_b_id,
      :travel_minutes,
      :visibility
    ])
    |> validate_length(:place_a_id, min: 1, max: 100)
    |> validate_format(:place_a_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:place_b_id, min: 1, max: 100)
    |> validate_format(:place_b_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_number(:travel_minutes,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10_080
    )
    |> validate_length(:scene_relevance, max: 1_000)
    |> validate_distinct_places()
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:place_a_id,
      name: :play_place_connections_campaign_place_a_fkey
    )
    |> foreign_key_constraint(:place_b_id,
      name: :play_place_connections_campaign_place_b_fkey
    )
    |> unique_constraint([:campaign_id, :place_a_id, :place_b_id])
    |> check_constraint(:travel_minutes, name: :play_place_connections_duration_check)
    |> check_constraint(:visibility, name: :play_place_connections_visibility_check)
  end

  defp validate_distinct_places(changeset) do
    if get_field(changeset, :place_a_id) == get_field(changeset, :place_b_id),
      do: add_error(changeset, :place_b_id, "must refer to a different place"),
      else: changeset
  end
end
