defmodule Storyteller.Play.Event do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.{Campaign, Session}
  alias Storyteller.Play.Turn

  schema "play_events" do
    field :sequence, :integer

    field :event_type, Ecto.Enum,
      values: [
        :player_action,
        :gm_narration,
        :npc_dialogue,
        :character_activity,
        :roll_request,
        :player_roll,
        :state_change
      ]

    field :visibility, Ecto.Enum, values: [:public, :gm_private], default: :public
    field :speaker_id, :string
    field :payload, :map, default: %{}

    belongs_to :campaign, Campaign
    belongs_to :session, Session
    belongs_to :turn, Turn

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :campaign_id,
      :session_id,
      :turn_id,
      :sequence,
      :event_type,
      :visibility,
      :speaker_id,
      :payload
    ])
    |> validate_required([
      :campaign_id,
      :session_id,
      :turn_id,
      :sequence,
      :event_type,
      :visibility,
      :payload
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> validate_length(:speaker_id, max: 100)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:turn_id)
    |> foreign_key_constraint(:turn_id, name: :play_events_turn_session_campaign_fkey)
    |> unique_constraint([:campaign_id, :sequence])
    |> check_constraint(:visibility, name: :play_events_visibility_check)
    |> check_constraint(:event_type, name: :play_events_type_check)
    |> check_constraint(:sequence, name: :play_events_sequence_check)
  end
end
