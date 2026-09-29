defmodule StorytellerWeb.CampaignLive.New do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.Campaign

  @impl true
  def mount(_params, _session, socket) do
    changeset = Campaigns.change_campaign(%Campaign{})

    {:ok,
     assign(socket,
       page_title: gettext("New campaign"),
       form: to_form(changeset, as: :campaign),
       reviewed: false,
       draft: nil,
       setup_error: nil,
       character_rows: [],
       panel_rows: []
     )}
  end

  @impl true
  def handle_event("validate", %{"campaign" => attrs}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)

    {:noreply,
     assign(socket,
       form: to_form(changeset, as: :campaign),
       draft: nil,
       setup_error: nil,
       character_rows: rows(attrs, "gm_characters"),
       panel_rows: rows(attrs, "panel_fields")
     )}
  end

  @impl true
  def handle_event("review", %{"campaign" => attrs}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)

    row_assigns = [
      character_rows: rows(attrs, "gm_characters"),
      panel_rows: rows(attrs, "panel_fields")
    ]

    case Campaigns.validate_campaign_setup(attrs) do
      {:ok, setup} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: :campaign),
           draft: setup,
           reviewed: true,
           setup_error: nil,
           character_rows: row_assigns[:character_rows],
           panel_rows: row_assigns[:panel_rows]
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
           reviewed: false,
           draft: nil,
           setup_error: nil,
           character_rows: row_assigns[:character_rows],
           panel_rows: row_assigns[:panel_rows]
         )}

      {:error, {:setup, message}} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
           reviewed: false,
           draft: nil,
           setup_error: setup_error_message(message),
           character_rows: row_assigns[:character_rows],
           panel_rows: row_assigns[:panel_rows]
         )}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, reviewed: false, setup_error: nil)}
  end

  @impl true
  def handle_event("add-character", _params, socket) do
    index = next_index(socket.assigns.character_rows)
    {:noreply, assign(socket, character_rows: socket.assigns.character_rows ++ [{index, %{}}])}
  end

  @impl true
  def handle_event("remove-character", %{"index" => index}, socket) do
    {:noreply, assign(socket, character_rows: remove_row(socket.assigns.character_rows, index))}
  end

  @impl true
  def handle_event("add-panel-field", _params, socket) do
    index = next_index(socket.assigns.panel_rows)
    {:noreply, assign(socket, panel_rows: socket.assigns.panel_rows ++ [{index, %{}}])}
  end

  @impl true
  def handle_event("remove-panel-field", %{"index" => index}, socket) do
    {:noreply, assign(socket, panel_rows: remove_row(socket.assigns.panel_rows, index))}
  end

  @impl true
  def handle_event("create", _params, %{assigns: %{draft: %{raw_attrs: attrs}}} = socket) do
    case Campaigns.create_campaign(attrs) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Campaign created and its first session is ready to resume.")
         )
         |> push_navigate(to: ~p"/campaigns/#{campaign.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           reviewed: false,
           setup_error:
             gettext("The campaign could not be created. Please review the setup and try again."),
           form: to_form(%{changeset | action: :validate}, as: :campaign)
         )}

      {:error, {:setup, message}} ->
        {:noreply, assign(socket, reviewed: false, setup_error: setup_error_message(message))}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           reviewed: false,
           setup_error:
             gettext("The campaign could not be created. Please review the setup and try again.")
         )}
    end
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:noreply, assign(socket, reviewed: false)}
  end

  defp rows(attrs, key) do
    case Map.get(attrs, key, %{}) do
      rows when is_list(rows) ->
        rows |> Enum.with_index() |> Enum.map(fn {row, index} -> {index, row} end)

      rows when is_map(rows) ->
        rows
        |> Enum.map(fn {index, row} -> {parse_index(index), row} end)
        |> Enum.sort_by(&elem(&1, 0))

      _ ->
        []
    end
  end

  defp parse_index(index) when is_integer(index), do: index

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp parse_index(_), do: 0

  defp next_index([]), do: 0
  defp next_index(rows), do: rows |> Enum.map(&elem(&1, 0)) |> Enum.max() |> Kernel.+(1)

  defp remove_row(rows, index) do
    index = parse_index(index)
    Enum.reject(rows, fn {row_index, _row} -> row_index == index end)
  end

  defp setup_error_message("Starting world details must be JSON-safe and under 100 KB.") do
    gettext("Starting world details must be valid data and under 100 KB.")
  end

  defp setup_error_message(_message) do
    gettext("Campaign setup could not be validated. Review the fields and try again.")
  end

  defp row_value(row, key) when is_map(row),
    do: Map.get(row, key, Map.get(row, String.to_existing_atom(key), ""))

  defp row_value(_row, _key), do: ""

  defp panel_type_label(:quantity), do: gettext("Quantity")
  defp panel_type_label(:money), do: gettext("Money")
  defp panel_type_label(:text), do: gettext("Text")
  defp panel_type_label(:status), do: gettext("Status")
  defp panel_type_label(:date), do: gettext("Date")

  defp starting_world(campaign) do
    [campaign.starting_location, campaign.starting_date, campaign.world_time, campaign.weather]
    |> Enum.map(fn value ->
      if is_binary(value) and value != "", do: value, else: gettext("Not set")
    end)
    |> Enum.join(" · ")
  end

  defp panel_initial_value(field) do
    case Map.get(field.value, "value") do
      nil -> gettext("Not set")
      value -> to_string(value)
    end
  end
end
