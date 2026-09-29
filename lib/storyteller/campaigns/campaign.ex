defmodule Storyteller.Campaigns.Campaign do
  @moduledoc "A persistent, independent story world owned by the local player."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Session

  @required_fields [:title, :premise, :setting, :tone, :narration_language, :player_character]
  @narration_languages ["English", "Spanish", "French"]

  schema "campaigns" do
    field :title, :string
    field :premise, :string
    field :setting, :string
    field :tone, :string
    field :narration_language, :string, default: "English"
    field :player_character, :string
    field :status, Ecto.Enum, values: [:active, :archived], default: :active

    has_many :sessions, Session, preload_order: [desc: :inserted_at]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @required_fields ++ [:status])
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 2, max: 100)
    |> validate_length(:premise, max: 10_000)
    |> validate_length(:setting, max: 500)
    |> validate_length(:tone, max: 300)
    |> validate_length(:player_character, max: 300)
    |> validate_inclusion(:narration_language, @narration_languages)
  end
end
