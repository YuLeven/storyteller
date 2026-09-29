defmodule Storyteller.Play.Turn do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.{Campaign, Session}

  schema "play_turns" do
    field :idempotency_key, :string
    field :request_hash, :string
    field :player_input, :string

    field :status,
          Ecto.Enum,
          values: [:pending, :resolving, :awaiting_roll, :failed, :superseded, :completed]

    field :resolution_phase, Ecto.Enum, values: [:initial, :after_roll], default: :initial
    field :roll_request, :map
    field :attempts, :integer, default: 0
    field :resolution_started_at, :utc_datetime_usec
    field :failure_code, :string

    belongs_to :campaign, Campaign
    belongs_to :session, Session

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [
      :campaign_id,
      :session_id,
      :idempotency_key,
      :request_hash,
      :player_input,
      :status,
      :resolution_phase,
      :roll_request,
      :attempts,
      :resolution_started_at,
      :failure_code
    ])
    |> validate_required([
      :campaign_id,
      :session_id,
      :idempotency_key,
      :request_hash,
      :player_input,
      :status,
      :resolution_phase,
      :attempts
    ])
    |> validate_length(:idempotency_key, min: 1, max: 128)
    |> validate_length(:player_input, min: 1, max: 20_000)
    |> validate_length(:request_hash, is: 64)
    |> validate_length(:failure_code, max: 80)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:session_id, name: :play_turns_session_campaign_fkey)
    |> unique_constraint([:campaign_id, :idempotency_key])
    |> unique_constraint(:campaign_id, name: :one_open_turn_per_campaign)
    |> check_constraint(:status, name: :play_turns_status_check)
    |> check_constraint(:resolution_phase, name: :play_turns_phase_check)
    |> check_constraint(:attempts, name: :play_turns_attempts_check)
  end
end
