defmodule Storyteller.Campaigns.AuthoringCorrection do
  @moduledoc "Durable before-and-after record for a post-creation setup correction."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "campaign_authoring_corrections" do
    field :sequence, :integer
    field :reason, :string
    field :before_state, :map
    field :after_state, :map
    field :contains_private_changes, :boolean, default: false

    belongs_to :campaign, Campaign

    field :inserted_at, :utc_datetime_usec
  end

  def changeset(correction, attrs) do
    correction
    |> cast(attrs, [
      :campaign_id,
      :sequence,
      :reason,
      :before_state,
      :after_state,
      :contains_private_changes,
      :inserted_at
    ])
    |> validate_required([
      :campaign_id,
      :sequence,
      :reason,
      :before_state,
      :after_state,
      :contains_private_changes,
      :inserted_at
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> validate_length(:reason, min: 1, max: 1_000)
    |> validate_change(:reason, fn :reason, reason ->
      if String.trim(reason) == [], do: [reason: "can't be blank"], else: []
    end)
    |> validate_change(:before_state, &validate_json_map/2)
    |> validate_change(:after_state, &validate_json_map/2)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint([:campaign_id, :sequence])
  end

  defp validate_json_map(field, value) when is_map(value) do
    case Jason.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= 100_000 -> []
      _ -> [{field, "must be a JSON map under 100 KB"}]
    end
  end

  defp validate_json_map(field, _value), do: [{field, "must be a JSON map"}]
end
