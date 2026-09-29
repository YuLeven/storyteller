defmodule Storyteller.Play.Roll do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Play.Turn

  schema "play_rolls" do
    field :kind, Ecto.Enum, values: [:player_click], default: :player_click
    field :result, :integer
    field :authorized_at, :utc_datetime_usec

    belongs_to :turn, Turn

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(roll, attrs) do
    roll
    |> cast(attrs, [:turn_id, :kind, :result, :authorized_at])
    |> validate_required([:turn_id, :kind, :result, :authorized_at])
    |> validate_number(:result, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> foreign_key_constraint(:turn_id)
    |> unique_constraint(:turn_id)
    |> check_constraint(:kind, name: :play_rolls_kind_check)
    |> check_constraint(:result, name: :play_rolls_d20_result_check)
  end
end
