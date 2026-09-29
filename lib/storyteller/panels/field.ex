defmodule Storyteller.Panels.Field do
  @moduledoc "A typed, campaign-scoped value shown in a configurable panel."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign
  alias Storyteller.Panels

  @value_types [:quantity, :money, :text, :status, :date]
  @visibilities [:public, :gm_private]

  schema "campaign_panel_fields" do
    field :key, :string
    field :panel, :string
    field :label, :string
    field :value_type, Ecto.Enum, values: @value_types
    field :unit, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :value, :map, default: %{}
    field :position, :integer, default: 0
    field :initial_value, :string, virtual: true

    belongs_to :campaign, Campaign

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating or updating a persisted campaign panel field."
  def changeset(field, attrs) do
    field
    |> cast(attrs, [
      :campaign_id,
      :key,
      :panel,
      :label,
      :value_type,
      :unit,
      :visibility,
      :value,
      :position,
      :initial_value
    ])
    |> validate_definition()
    |> validate_required([:campaign_id])
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint([:campaign_id, :key])
  end

  @doc "Changeset for validating a field definition before a campaign has an id."
  def definition_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :key,
      :panel,
      :label,
      :value_type,
      :unit,
      :visibility,
      :position,
      :initial_value
    ])
    |> validate_definition()
  end

  defp validate_definition(changeset) do
    changeset
    |> validate_required([:key, :panel, :label, :value_type, :visibility])
    |> validate_format(:key, ~r/\A[a-z][a-z0-9_:-]*\z/)
    |> validate_length(:key, max: 100)
    |> validate_length(:panel, min: 1, max: 80)
    |> validate_length(:label, min: 1, max: 100)
    |> validate_length(:unit, max: 50)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> cast_and_validate_value()
  end

  defp cast_and_validate_value(changeset) do
    type = get_field(changeset, :value_type)

    raw =
      case get_change(changeset, :value) do
        %{"value" => value} -> value
        %{value: value} -> value
        _ -> get_change(changeset, :initial_value)
      end

    raw =
      if is_nil(raw) or (raw == "" and type in [:quantity, :money]),
        do: default_value(type),
        else: raw

    case Panels.validate_value(type, raw) do
      {:ok, normalized} -> put_change(changeset, :value, %{"value" => normalized})
      {:error, message} -> add_error(changeset, :initial_value, message)
    end
  end

  defp default_value(:quantity), do: "0"
  defp default_value(:money), do: "0"
  defp default_value(:text), do: ""
  defp default_value(:status), do: ""
  defp default_value(:date), do: ""
  defp default_value(_), do: nil
end
