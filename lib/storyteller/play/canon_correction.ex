defmodule Storyteller.Play.CanonCorrection do
  @moduledoc "Durable audit record for an out-of-character correction to public campaign canon."

  use Ecto.Schema
  import Ecto.Changeset

  alias Storyteller.Campaigns.Campaign

  schema "play_canon_corrections" do
    field :sequence, :integer
    field :kind, :string
    field :target_id, :string
    field :expected_revision, :integer
    field :reason, :string
    field :before_state, :map
    field :after_state, :map

    belongs_to :campaign, Campaign

    field :inserted_at, :utc_datetime_usec
  end

  def changeset(correction, attrs) do
    correction
    |> cast(attrs, [
      :campaign_id,
      :sequence,
      :kind,
      :target_id,
      :expected_revision,
      :reason,
      :before_state,
      :after_state,
      :inserted_at
    ])
    |> validate_required([
      :campaign_id,
      :sequence,
      :kind,
      :target_id,
      :expected_revision,
      :reason,
      :before_state,
      :after_state,
      :inserted_at
    ])
    |> validate_inclusion(:kind, ~w(inventory resource location memory world))
    |> validate_number(:sequence, greater_than: 0)
    |> validate_number(:expected_revision, greater_than_or_equal_to: 0)
    |> validate_length(:target_id, min: 1, max: 100)
    |> validate_length(:reason, min: 1, max: 1_000)
    |> validate_change(:reason, fn :reason, reason ->
      if String.trim(reason) == [], do: [reason: "can't be blank"], else: []
    end)
    |> validate_map_size(:before_state)
    |> validate_map_size(:after_state)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint([:campaign_id, :sequence])
  end

  defp validate_map_size(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) ->
        case Jason.encode(value) do
          {:ok, encoded} when byte_size(encoded) <= 100_000 -> changeset
          _ -> add_error(changeset, field, "must be a JSON map under 100 KB")
        end

      _ ->
        add_error(changeset, field, "must be a JSON map")
    end
  end
end
