defmodule Storyteller.Play.State do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_states" do
    field :revision, :integer, default: 0
    field :event_sequence, :integer, default: 0
    field :elapsed_world_minutes, :integer, default: 0
    field :elapsed_world_anchor_minutes, :integer, default: 0
    field :elapsed_world_anchor, :map, default: %{}
    field :public_state, :map, default: %{}
    field :gm_private_state, :map, default: %{}
    field :public_history_summary, :string, default: ""
    field :gm_private_history_summary, :string, default: ""

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [
      :campaign_id,
      :revision,
      :event_sequence,
      :elapsed_world_minutes,
      :elapsed_world_anchor_minutes,
      :elapsed_world_anchor,
      :public_state,
      :gm_private_state,
      :public_history_summary,
      :gm_private_history_summary
    ])
    |> validate_required([
      :campaign_id,
      :revision,
      :event_sequence,
      :elapsed_world_minutes,
      :elapsed_world_anchor_minutes,
      :elapsed_world_anchor,
      :public_state,
      :gm_private_state
    ])
    |> validate_number(:revision, greater_than_or_equal_to: 0)
    |> validate_number(:event_sequence, greater_than_or_equal_to: 0)
    |> validate_number(:elapsed_world_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:elapsed_world_anchor_minutes, greater_than_or_equal_to: 0)
    |> validate_anchor_clock()
    |> validate_map(:elapsed_world_anchor)
    |> validate_map(:public_state)
    |> validate_map(:gm_private_state)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint(:campaign_id)
    |> check_constraint(:revision, name: :play_states_counters_check)
    |> check_constraint(:elapsed_world_minutes, name: :play_states_elapsed_world_minutes_check)
    |> check_constraint(:elapsed_world_anchor_minutes, name: :play_states_elapsed_anchor_check)
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _ -> add_error(changeset, field, "must be a map")
    end
  end

  defp validate_anchor_clock(changeset) do
    anchor_minutes = get_field(changeset, :elapsed_world_anchor_minutes)
    elapsed_minutes = get_field(changeset, :elapsed_world_minutes)

    if is_integer(anchor_minutes) and is_integer(elapsed_minutes) and
         anchor_minutes <= elapsed_minutes do
      changeset
    else
      add_error(changeset, :elapsed_world_anchor_minutes, "must not exceed elapsed world time")
    end
  end
end
