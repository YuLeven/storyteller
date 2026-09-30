defmodule Storyteller.Play.Objective do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_objectives" do
    field :objective_id, :string
    field :title, :string
    field :details, :string
    field :status, Ecto.Enum, values: [:open, :completed, :abandoned], default: :open
    field :visibility, Ecto.Enum, values: [:public, :gm_private], default: :public

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(objective, attrs) do
    objective
    |> cast(attrs, [:campaign_id, :objective_id, :title, :details, :status, :visibility])
    |> validate_required([:campaign_id, :objective_id, :title, :status, :visibility])
    |> validate_length(:objective_id, min: 1, max: 100)
    |> validate_format(:objective_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:title, min: 1, max: 160)
    |> validate_length(:details, max: 2_000)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint([:campaign_id, :objective_id])
    |> check_constraint(:status, name: :play_objectives_status_check)
    |> check_constraint(:visibility, name: :play_objectives_visibility_check)
  end
end
