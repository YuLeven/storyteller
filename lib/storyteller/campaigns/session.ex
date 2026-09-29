defmodule Storyteller.Campaigns.Session do
  @moduledoc "A resumable play segment within one campaign's continuous history."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "sessions" do
    field :title, :string
    field :status, Ecto.Enum, values: [:active, :completed], default: :active
    field :ended_at, :utc_datetime_usec

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:campaign_id, :title, :status, :ended_at])
    |> validate_required([:campaign_id, :title])
    |> validate_length(:title, min: 1, max: 100)
    |> foreign_key_constraint(:campaign_id)
    |> check_constraint(:status, name: :sessions_status_check)
    |> unique_constraint(:campaign_id, name: :one_active_session_per_campaign)
  end
end
