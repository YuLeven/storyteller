defmodule Storyteller.Panels do
  @moduledoc "Typed campaign panels, safe public projections, and scoped value updates."

  import Ecto.Query, warn: false

  alias Storyteller.Campaigns.Campaign
  alias Storyteller.Panels.Field
  alias Storyteller.Repo

  @value_types [:quantity, :money, :text, :status, :date]
  @max_text_length 2_000
  @max_money_input_bytes 80
  @max_money_exponent 40
  @max_money_value_chars 40

  def list_fields(campaign_id) do
    Repo.all(
      from field in Field,
        where: field.campaign_id == ^campaign_id,
        order_by: [asc: field.position, asc: field.id]
    )
  end

  @doc "Returns grouped panel fields with GM-only values entirely omitted."
  def public_projection(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil ->
        {:error, :not_found}

      _campaign ->
        panels =
          campaign_id
          |> list_fields()
          |> Enum.filter(&(&1.visibility == :public))
          |> Enum.group_by(& &1.panel)
          |> Enum.map(fn {panel_name, fields} ->
            %{
              name: panel_name,
              fields:
                Enum.map(fields, fn field ->
                  %{
                    key: field.key,
                    label: field.label,
                    type: field.value_type,
                    unit: field.unit,
                    value: value_from_storage(field.value)
                  }
                end)
            }
          end)
          |> Enum.sort_by(& &1.name)

        {:ok, %{campaign_id: campaign_id, panels: panels}}
    end
  end

  @doc "Validates and normalizes a proposed value for a known panel type."
  def validate_value(%Field{value_type: type}, value), do: validate_value(type, value)

  def validate_value(type, value) when is_binary(type) do
    case Enum.find(@value_types, &(Atom.to_string(&1) == type)) do
      nil -> {:error, "is not a supported panel type"}
      atom -> validate_value(atom, value)
    end
  end

  def validate_value(:quantity, value) do
    with {:ok, integer} <- parse_integer(value),
         true <- integer >= 0 do
      {:ok, integer}
    else
      _ -> {:error, "must be a whole number of zero or greater"}
    end
  end

  def validate_value(:money, value) do
    with {:ok, decimal} <- parse_decimal(value),
         true <- finite_decimal?(decimal),
         true <- bounded_money_decimal?(decimal),
         true <- Decimal.compare(decimal, Decimal.new(0)) != :lt,
         normalized <- Decimal.to_string(Decimal.normalize(decimal), :normal),
         true <- byte_size(normalized) <= @max_money_value_chars do
      {:ok, normalized}
    else
      _ -> {:error, "must be a nonnegative amount"}
    end
  end

  def validate_value(type, value) when type in [:text, :status] do
    max_length = if type == :status, do: 100, else: @max_text_length

    cond do
      not is_binary(value) -> {:error, "must be text"}
      formula_like?(value) -> {:error, "formulas are not supported"}
      String.length(value) > max_length -> {:error, "is too long"}
      true -> {:ok, value}
    end
  end

  def validate_value(:date, value) when value in [nil, ""], do: {:ok, nil}

  def validate_value(:date, %Date{} = date), do: {:ok, Date.to_iso8601(date)}

  def validate_value(:date, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, Date.to_iso8601(date)}
      _ -> {:error, "must be a valid ISO date (YYYY-MM-DD)"}
    end
  end

  def validate_value(_type, _value), do: {:error, "is not a supported panel type"}

  @doc "Applies a signed numeric change to a canonical quantity or money value."
  def apply_delta(%Field{value_type: :quantity}, current, delta) when is_integer(delta) do
    with {:ok, current} <- validate_value(:quantity, current),
         true <- delta != 0,
         {:ok, next} <- validate_value(:quantity, current + delta) do
      {:ok, current, delta, next}
    else
      false -> {:error, :zero_delta}
      {:error, _reason} -> {:error, :invalid_result}
    end
  end

  def apply_delta(%Field{value_type: :money}, current, delta) when is_binary(delta) do
    with {:ok, current} <- validate_value(:money, current),
         {:ok, delta} <- parse_signed_decimal(delta),
         false <- Decimal.compare(delta, Decimal.new(0)) == :eq,
         next <- Decimal.add(Decimal.new(current), delta),
         {:ok, next} <- validate_value(:money, next) do
      normalized_delta = Decimal.to_string(Decimal.normalize(delta), :normal)
      {:ok, current, normalized_delta, next}
    else
      true -> {:error, :zero_delta}
      _ -> {:error, :invalid_result}
    end
  end

  def apply_delta(_field, _current, _delta), do: {:error, :invalid_delta}

  @doc """
  Low-level scoped value update for a field key within one campaign.

  This helper does not create a play event. Future GM-turn code should validate
  with `validate_value/2` and apply the field change together with its audit
  event in the same transaction rather than using this helper by itself.
  """
  def update_value(campaign_id, key, value) when is_integer(campaign_id) and is_binary(key) do
    case Repo.get_by(Field, campaign_id: campaign_id, key: key) do
      nil ->
        {:error, :not_found}

      field ->
        case validate_value(field, value) do
          {:ok, normalized} ->
            field
            |> Field.changeset(%{value: %{"value" => normalized}})
            |> Repo.update()

          {:error, message} ->
            {:error,
             Field.changeset(field, %{})
             |> Ecto.Changeset.add_error(:initial_value, message)}
        end
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse_integer(_), do: :error

  defp parse_decimal(%Decimal{} = value), do: {:ok, value}

  defp parse_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp parse_decimal(value)
       when is_binary(value) and byte_size(value) <= @max_money_input_bytes do
    case Decimal.parse(String.trim(value)) do
      {%Decimal{} = decimal, ""} -> {:ok, decimal}
      _ -> :error
    end
  end

  defp parse_decimal(value) when is_binary(value), do: :error

  defp parse_decimal(value) when is_float(value) do
    if value == value and abs(value) < 1.0e100 do
      {:ok, Decimal.from_float(value)}
    else
      :error
    end
  end

  defp parse_decimal(_), do: :error

  defp parse_signed_decimal(value) when is_binary(value) and byte_size(value) <= 40 do
    case Decimal.parse(String.trim(value)) do
      {%Decimal{} = decimal, ""} ->
        if finite_decimal?(decimal) and bounded_money_decimal?(decimal) do
          normalized = Decimal.to_string(Decimal.normalize(decimal), :normal)

          if byte_size(normalized) <= @max_money_value_chars,
            do: {:ok, decimal},
            else: {:error, :invalid_decimal}
        else
          {:error, :invalid_decimal}
        end

      _ ->
        {:error, :invalid_decimal}
    end
  end

  defp parse_signed_decimal(_), do: {:error, :invalid_decimal}

  defp bounded_money_decimal?(%Decimal{exp: exponent})
       when is_integer(exponent) and abs(exponent) <= @max_money_exponent,
       do: true

  defp bounded_money_decimal?(_), do: false

  defp formula_like?(value), do: String.starts_with?(String.trim_leading(value), "=")

  defp finite_decimal?(%Decimal{coef: coefficient}) when is_integer(coefficient), do: true
  defp finite_decimal?(_), do: false

  defp value_from_storage(%{"value" => value}), do: value
  defp value_from_storage(%{value: value}), do: value
  defp value_from_storage(_), do: nil
end
