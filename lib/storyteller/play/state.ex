defmodule Storyteller.Play.State do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_states" do
    field :revision, :integer, default: 0
    field :event_sequence, :integer, default: 0
    field :public_state, :map, default: %{}
    field :gm_private_state, :map, default: %{}

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:campaign_id, :revision, :event_sequence, :public_state, :gm_private_state])
    |> validate_required([
      :campaign_id,
      :revision,
      :event_sequence,
      :public_state,
      :gm_private_state
    ])
    |> validate_number(:revision, greater_than_or_equal_to: 0)
    |> validate_number(:event_sequence, greater_than_or_equal_to: 0)
    |> validate_map(:public_state)
    |> validate_map(:gm_private_state)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint(:campaign_id)
    |> check_constraint(:revision, name: :play_states_counters_check)
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _ -> add_error(changeset, field, "must be a map")
    end
  end
end
