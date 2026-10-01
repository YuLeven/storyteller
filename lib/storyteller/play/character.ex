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
    field :duty_name, :string
    field :duty_place_id, :string
    field :duty_release_at_world_minute, :integer

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
      :current_place_id,
      :duty_name,
      :duty_place_id,
      :duty_release_at_world_minute
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
    |> validate_active_duty()
    |> validate_number(:duty_release_at_world_minute, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:current_place_id,
      name: :play_characters_campaign_current_place_fkey
    )
    |> foreign_key_constraint(:duty_place_id,
      name: :play_characters_campaign_duty_place_fkey
    )
    |> check_constraint(:duty_name, name: :play_characters_active_duty_check)
    |> check_constraint(:duty_release_at_world_minute,
      name: :play_characters_duty_release_check
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

  defp validate_active_duty(changeset) do
    duty_name = get_field(changeset, :duty_name)
    duty_place_id = get_field(changeset, :duty_place_id)
    release_at = get_field(changeset, :duty_release_at_world_minute)

    cond do
      is_nil(duty_name) and is_nil(duty_place_id) and is_nil(release_at) ->
        changeset

      get_field(changeset, :role) != :gm ->
        add_error(changeset, :duty_name, "is only available for GM-controlled characters")

      not is_binary(duty_name) or String.trim(duty_name) == "" or
          String.length(duty_name) > 160 ->
        add_error(changeset, :duty_name, "must be a name up to 160 characters")

      not is_binary(duty_place_id) or String.trim(duty_place_id) == "" ->
        add_error(changeset, :duty_place_id, "must name the place where the duty was assigned")

      not is_nil(release_at) and (not is_integer(release_at) or release_at < 0) ->
        add_error(changeset, :duty_release_at_world_minute, "must be a non-negative world minute")

      true ->
        changeset
    end
  end
end
