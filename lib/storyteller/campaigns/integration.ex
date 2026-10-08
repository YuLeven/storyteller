defmodule Storyteller.Campaigns.Integration do
  @moduledoc "A campaign companion project with optional MCP and website links."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :mcp_endpoint_url, :string
    field :instructions, :string
    field :site_label, :string
    field :site_url, :string
    field :enabled, :boolean, default: true
  end

  @fields ~w(name mcp_endpoint_url instructions site_label site_url enabled)a
  @max_name_chars 100
  @max_instructions_chars 10_000
  @max_total_instruction_bytes 10_000
  @max_url_chars 2_048

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, @fields)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: @max_name_chars)
    |> validate_length(:instructions, max: @max_instructions_chars)
    |> validate_length(:site_label, max: @max_name_chars)
    |> validate_length(:mcp_endpoint_url, max: @max_url_chars)
    |> validate_length(:site_url, max: @max_url_chars)
    |> validate_change(:mcp_endpoint_url, &validate_http_url/2)
    |> validate_change(:site_url, &validate_http_url/2)
    |> validate_companion_fields()
  end

  def normalize_all(integrations) when is_map(integrations) do
    cond do
      map_size(integrations) > 12 ->
        {:error, :too_many_integrations}

      true ->
        result =
          Enum.reduce_while(integrations, {:ok, %{}}, fn {id, attrs}, {:ok, normalized} ->
            valid_attrs? = is_map(attrs)
            attrs = if valid_attrs?, do: normalize_site_label(attrs), else: %{}
            changeset = changeset(%__MODULE__{}, attrs)

            cond do
              not valid_id?(id) ->
                {:halt, {:error, :invalid_integration}}

              not valid_attrs? ->
                {:halt, {:error, :invalid_integration}}

              not changeset.valid? ->
                {:halt, {:error, changeset}}

              true ->
                entry =
                  changeset
                  |> apply_changes()
                  |> Map.from_struct()
                  |> Map.take(@fields)
                  |> Map.update!(:name, &String.trim/1)
                  |> Map.update!(:instructions, &trim_or_empty/1)
                  |> Map.update!(:mcp_endpoint_url, &trim_or_nil/1)
                  |> Map.update!(:site_url, &trim_or_nil/1)
                  |> Map.update!(:site_label, &trim_or_nil/1)

                {:cont, {:ok, Map.put(normalized, id, entry)}}
            end
          end)

        case result do
          {:ok, normalized} ->
            instruction_bytes =
              normalized
              |> Map.values()
              |> Enum.reduce(0, &(byte_size(&1.instructions || "") + &2))

            if instruction_bytes <= @max_total_instruction_bytes,
              do: {:ok, normalized},
              else: {:error, :too_many_instructions}

          error ->
            error
        end
    end
  end

  def normalize_all(_), do: {:error, :invalid_integrations}

  def normalize_backup(integrations) when is_map(integrations), do: normalize_all(integrations)
  def normalize_backup(_), do: {:error, :invalid_integrations}

  defp validate_http_url(_field, value) when value in [nil, ""], do: []

  defp validate_http_url(field, value) do
    uri = URI.parse(String.trim(value))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_nil(uri.fragment) do
      []
    else
      [{field, "must be an HTTP or HTTPS URL without embedded credentials or a fragment"}]
    end
  rescue
    _error -> [{field, "must be an HTTP or HTTPS URL"}]
  end

  defp validate_companion_fields(changeset) do
    mcp_url = get_field(changeset, :mcp_endpoint_url)
    site_url = get_field(changeset, :site_url)
    site_label = get_field(changeset, :site_label)
    instructions = get_field(changeset, :instructions)

    changeset
    |> then(fn current ->
      if blank?(mcp_url) and blank?(site_url),
        do: add_error(current, :name, "add an MCP endpoint or a site link"),
        else: current
    end)
    |> then(fn current ->
      if blank?(site_url) and not blank?(site_label),
        do: add_error(current, :site_label, "requires a site URL"),
        else: current
    end)
    |> then(fn current ->
      if blank?(mcp_url) and not blank?(instructions),
        do: add_error(current, :instructions, "requires an MCP endpoint"),
        else: current
    end)
  end

  defp normalize_site_label(attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    site_url = input_value(attrs, :site_url)
    site_label = input_value(attrs, :site_label)
    name = input_value(attrs, :name)

    if not blank?(site_url) and blank?(site_label),
      do: Map.put(attrs, "site_label", name),
      else: attrs
  end

  defp input_value(attrs, key), do: Map.get(attrs, Atom.to_string(key), Map.get(attrs, key))

  defp valid_id?(id) when is_binary(id),
    do: byte_size(id) in 1..40 and Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, id)

  defp valid_id?(_), do: false

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""
  defp trim_or_empty(value) when is_binary(value), do: String.trim(value)
  defp trim_or_empty(_), do: ""
  defp trim_or_nil(value) when is_binary(value), do: String.trim(value) |> empty_to_nil()
  defp trim_or_nil(_), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
