defmodule Storyteller.Play.Character do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_characters" do
    field :speaker_id, :string
    field :name, :string
    field :role, Ecto.Enum, values: [:player, :gm]
    field :visible_facts, :map, default: %{}
    field :gm_private_facts, :map, default: %{}
    field :visible_activity, :string

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
      :visible_activity
    ])
    |> validate_required([:campaign_id, :speaker_id, :name, :role])
    |> validate_length(:speaker_id, min: 1, max: 100)
    |> validate_format(:speaker_id, ~r/\A[a-zA-Z0-9:_-]+\z/)
    |> validate_length(:name, min: 1, max: 300)
    |> validate_length(:visible_activity, max: 2_000)
    |> validate_map(:visible_facts)
    |> validate_map(:gm_private_facts)
    |> foreign_key_constraint(:campaign_id)
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
end
