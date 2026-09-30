defmodule Storyteller.Play.ContinuityEntry do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign
  alias Storyteller.Play.Event

  schema "play_continuity_entries" do
    field :entry_id, :string
    field :kind, Ecto.Enum, values: [:fact, :relationship, :commitment]
    field :title, :string
    field :details, :string
    field :status, Ecto.Enum, values: [:active, :resolved, :retracted], default: :active
    field :visibility, Ecto.Enum, values: [:public, :gm_private], default: :public

    belongs_to :campaign, Campaign
    belongs_to :introduced_by_event, Event, foreign_key: :introduced_by_event_id
    belongs_to :source_event, Event, foreign_key: :source_event_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :campaign_id,
      :entry_id,
      :kind,
      :title,
      :details,
      :status,
      :visibility,
      :introduced_by_event_id,
      :source_event_id
    ])
    |> validate_required([
      :campaign_id,
      :entry_id,
      :kind,
      :title,
      :details,
      :status,
      :visibility,
      :introduced_by_event_id,
      :source_event_id
    ])
    |> validate_length(:entry_id, min: 1, max: 100)
    |> validate_format(:entry_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:title, min: 1, max: 120)
    |> validate_length(:details, min: 1, max: 500)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:introduced_by_event_id,
      name: :play_continuity_entries_introduced_event_campaign_fkey
    )
    |> foreign_key_constraint(:source_event_id,
      name: :play_continuity_entries_source_event_campaign_fkey
    )
    |> unique_constraint([:campaign_id, :entry_id])
    |> check_constraint(:kind, name: :play_continuity_entries_kind_check)
    |> check_constraint(:status, name: :play_continuity_entries_status_check)
    |> check_constraint(:visibility, name: :play_continuity_entries_visibility_check)
  end
end
