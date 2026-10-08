defmodule Storyteller.Campaigns.Campaign do
  @moduledoc "A persistent, independent story world owned by the local player."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.{Integration, Session}

  @required_fields [
    :title,
    :premise,
    :setting,
    :tone,
    :narration_language,
    :player_character_name,
    :player_character
  ]
  @narration_languages ["English", "Spanish", "French"]

  schema "campaigns" do
    field :title, :string
    field :premise, :string
    field :setting, :string
    field :tone, :string
    field :narration_language, :string, default: "English"
    field :player_character_name, :string
    field :player_character, :string
    field :integrations, :map, default: %{}
    field :starting_location, :string, virtual: true
    field :starting_date, :string, virtual: true
    field :world_time, :string, virtual: true
    field :weather, :string, virtual: true
    field :status, Ecto.Enum, values: [:active, :archived], default: :active

    has_many :sessions, Session, preload_order: [desc: :inserted_at]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(
      attrs,
      @required_fields ++
        [:status, :starting_location, :starting_date, :world_time, :weather, :integrations]
    )
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 2, max: 100)
    |> validate_length(:premise, max: 10_000)
    |> validate_length(:setting, max: 500)
    |> validate_length(:tone, max: 300)
    |> validate_length(:player_character_name, max: 300)
    |> validate_length(:player_character, max: 300)
    |> validate_length(:starting_location, max: 500)
    |> validate_length(:starting_date, max: 100)
    |> validate_length(:world_time, max: 300)
    |> validate_length(:weather, max: 500)
    |> validate_inclusion(:narration_language, @narration_languages)
    |> validate_integrations()
  end

  defp validate_integrations(changeset) do
    case Integration.normalize_all(Ecto.Changeset.get_field(changeset, :integrations, %{})) do
      {:ok, normalized} ->
        Ecto.Changeset.put_change(changeset, :integrations, normalized)

      {:error, %Ecto.Changeset{} = invalid} ->
        Ecto.Changeset.add_error(changeset, :integrations, integration_error(invalid))

      {:error, :too_many_integrations} ->
        Ecto.Changeset.add_error(
          changeset,
          :integrations,
          "add no more than 12 companion projects"
        )

      {:error, :too_many_instructions} ->
        Ecto.Changeset.add_error(
          changeset,
          :integrations,
          "keep total companion instructions under 10,000 bytes"
        )

      {:error, _reason} ->
        Ecto.Changeset.add_error(
          changeset,
          :integrations,
          "contains an invalid companion project"
        )
    end
  end

  defp integration_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
