defmodule Storyteller.Play.Character do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign
  alias Storyteller.Play.VoiceGuidance

  schema "play_characters" do
    field :speaker_id, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:player, :gm]
    field :visible_facts, :map, default: %{}
    field :gm_private_facts, :map, default: %{}
    field :voice_guidance, :map, default: %{}
    field :visible_activity, :string
    field :current_place_id, :string

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [
      :campaign_id,
      :speaker_id,
      :name,
      :role,
      :visible_facts,
      :gm_private_facts,
      :voice_guidance,
      :visible_activity,
      :current_place_id
    ])
    |> validate_required([:campaign_id, :speaker_id, :name, :role])
    |> validate_length(:speaker_id, min: 1, max: 100)
    |> validate_format(:speaker_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:name, min: 1, max: 300)
    |> validate_length(:visible_activity, max: 2_000)
    |> validate_map(:visible_facts)
    |> validate_map(:gm_private_facts)
    |> validate_voice_guidance()
    |> validate_length(:current_place_id, max: 100)
    |> validate_format(:current_place_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:current_place_id,
      name: :play_characters_campaign_current_place_fkey
    )
    |> unique_constraint([:campaign_id, :speaker_id])
    |> unique_constraint(:campaign_id, name: :one_player_character_per_campaign)
    |> check_constraint(:role, name: :play_characters_role_check)
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _ -> add_error(changeset, field, "must be a map")
    end
  end

  defp validate_voice_guidance(changeset) do
    case VoiceGuidance.normalize(get_field(changeset, :voice_guidance)) do
      {:ok, normalized} -> put_change(changeset, :voice_guidance, normalized)
      {:error, _reason} -> add_error(changeset, :voice_guidance, "is invalid")
    end
  end
end
