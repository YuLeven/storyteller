defmodule StorytellerWeb.CampaignLive.New do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.Campaign
  alias Storyteller.Play.VoiceGuidance

  @impl true
  def mount(_params, _session, socket) do
    changeset = Campaigns.change_campaign(%Campaign{})

    {:ok,
     assign(socket,
       page_title: gettext("New campaign"),
       form: to_form(changeset, as: :campaign),
       step: 1,
       reviewed: false,
       draft: nil,
       setup_error: nil,
       character_rows: [],
       player_detail_rows: [],
       panel_rows: [],
       inventory_rows: []
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
       player_detail_rows: rows(attrs, "player_character_details"),
       panel_rows: rows(attrs, "panel_fields"),
       inventory_rows: rows(attrs, "inventory")
     )}
  end

  @impl true
  def handle_event("review", %{"campaign" => attrs}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)

    row_assigns = [
      character_rows: rows(attrs, "gm_characters"),
      player_detail_rows: rows(attrs, "player_character_details"),
      panel_rows: rows(attrs, "panel_fields"),
      inventory_rows: rows(attrs, "inventory")
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
           player_detail_rows: row_assigns[:player_detail_rows],
           panel_rows: row_assigns[:panel_rows],
           inventory_rows: row_assigns[:inventory_rows]
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
           step: first_error_step(changeset),
           reviewed: false,
           draft: nil,
           setup_error: nil,
           character_rows: row_assigns[:character_rows],
           player_detail_rows: row_assigns[:player_detail_rows],
           panel_rows: row_assigns[:panel_rows],
           inventory_rows: row_assigns[:inventory_rows]
         )}

      {:error, {:setup, message}} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
           step: setup_error_step(message),
           reviewed: false,
           draft: nil,
           setup_error: setup_error_message(message),
           character_rows: row_assigns[:character_rows],
           player_detail_rows: row_assigns[:player_detail_rows],
           panel_rows: row_assigns[:panel_rows],
           inventory_rows: row_assigns[:inventory_rows]
         )}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, reviewed: false, step: 4, setup_error: nil)}
  end

  @impl true
  def handle_event("navigate", %{"campaign" => attrs, "direction" => "continue"}, socket) do
    if socket.assigns.step < 4 do
      changeset = Campaigns.change_campaign(%Campaign{}, attrs)

      {:noreply,
       socket
       |> assign_form(attrs, changeset)
       |> assign(step: socket.assigns.step + 1, reviewed: false, draft: nil, setup_error: nil)}
    else
      handle_event("review", %{"campaign" => attrs}, socket)
    end
  end

  def handle_event("navigate", %{"campaign" => attrs, "direction" => "previous"}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)

    {:noreply,
     socket
     |> assign_form(attrs, changeset)
     |> assign(
       step: max(socket.assigns.step - 1, 1),
       reviewed: false,
       draft: nil,
       setup_error: nil
     )}
  end

  def handle_event("navigate", %{"campaign" => attrs}, socket) do
    handle_event("review", %{"campaign" => attrs}, socket)
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
  def handle_event("add-player-detail", _params, socket) do
    index = next_index(socket.assigns.player_detail_rows)

    {:noreply,
     assign(socket,
       player_detail_rows: socket.assigns.player_detail_rows ++ [{index, %{}}]
     )}
  end

  @impl true
  def handle_event("remove-player-detail", %{"index" => index}, socket) do
    {:noreply,
     assign(socket,
       player_detail_rows: remove_row(socket.assigns.player_detail_rows, index)
     )}
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
  def handle_event("add-starting-item", _params, socket) do
    index = next_index(socket.assigns.inventory_rows)
    {:noreply, assign(socket, inventory_rows: socket.assigns.inventory_rows ++ [{index, %{}}])}
  end

  @impl true
  def handle_event("remove-starting-item", %{"index" => index}, socket) do
    {:noreply, assign(socket, inventory_rows: remove_row(socket.assigns.inventory_rows, index))}
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
           step: first_error_step(changeset),
           setup_error:
             gettext("The campaign could not be created. Please review the setup and try again."),
           form: to_form(%{changeset | action: :validate}, as: :campaign)
         )}

      {:error, {:setup, message}} ->
        {:noreply,
         assign(socket,
           reviewed: false,
           step: setup_error_step(message),
           setup_error: setup_error_message(message)
         )}

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

  defp assign_form(socket, attrs, changeset) do
    assign(socket,
      form: to_form(changeset, as: :campaign),
      character_rows: rows(attrs, "gm_characters"),
      player_detail_rows: rows(attrs, "player_character_details"),
      panel_rows: rows(attrs, "panel_fields"),
      inventory_rows: rows(attrs, "inventory")
    )
  end

  defp first_error_step(changeset) do
    changeset.errors
    |> Enum.find_value(4, fn {field, _error} -> field_step(field) end)
  end

  defp field_step(field)
       when field in [:title, :premise, :setting, :tone, :narration_language],
       do: 1

  defp field_step(field) when field in [:player_character_name, :player_character], do: 2
  defp field_step(_field), do: 4

  defp setup_error_step(message) do
    cond do
      String.starts_with?(message, "Player character detail") or
        String.starts_with?(message, "Every player character detail") or
          String.starts_with?(message, "The label 'description'") ->
        2

      String.starts_with?(message, "Starting world") or
        String.starts_with?(message, "Starting inventory") or
        String.starts_with?(message, "Starting item") or
          String.starts_with?(message, "Add no more than 200 starting items") ->
        3

      true ->
        4
    end
  end

  defp setup_error_message("Starting world details must be JSON-safe and under 100 KB.") do
    gettext("Starting world details must be valid data and under 100 KB.")
  end

  defp setup_error_message("Add no more than 200 starting items.") do
    gettext("Add no more than 200 starting items.")
  end

  defp setup_error_message("Starting inventory contains an invalid item.") do
    gettext("Starting inventory contains an invalid item. Check the item names and quantities.")
  end

  defp setup_error_message("Starting inventory must be a list.") do
    gettext("Starting inventory must be a list.")
  end

  defp setup_error_message("GM character " <> details) do
    case String.split(details, " ", parts: 2) do
      [number, "starting place must be 300 characters or fewer."] ->
        gettext("GM character %{number} starting place must be 300 characters or fewer.",
          number: number
        )

      [number, "active duty must be 160 characters or fewer."] ->
        gettext("GM character %{number} active duty must be 160 characters or fewer.",
          number: number
        )

      [number, "active duty duration must be a positive whole number up to 525600 minutes."] ->
        gettext(
          "GM character %{number} duty duration must be between 1 and 525600 in-world minutes.",
          number: number
        )

      [number, "needs an active duty before setting its duration."] ->
        gettext("GM character %{number} needs a duty before you can set its duration.",
          number: number
        )

      [number, "needs a starting place for an active duty."] ->
        gettext("GM character %{number} needs a starting place for an active duty.",
          number: number
        )

      _details ->
        gettext("Campaign setup could not be validated. Review the fields and try again.")
    end
  end

  defp setup_error_message(
         "Voice notes need up to 280 characters per field and 1,200 characters total."
       ) do
    gettext(
      "Voice notes must be %{field_limit} characters or fewer per field and %{total_limit} characters total.",
      field_limit: VoiceGuidance.max_field_length(),
      total_limit: VoiceGuidance.max_total_length()
    )
  end

  defp setup_error_message("Player character details must be a list.") do
    gettext("Player character details must be a list.")
  end

  defp setup_error_message("Player character detail rows must be objects.") do
    gettext("Player character detail rows must be objects.")
  end

  defp setup_error_message("Add no more than 50 player character details.") do
    gettext("Add no more than 50 player character details.")
  end

  defp setup_error_message("Every player character detail needs a label up to 80 characters.") do
    gettext("Every player character detail needs a label up to 80 characters.")
  end

  defp setup_error_message("Every player character detail needs a value up to 500 characters.") do
    gettext("Every player character detail needs a value up to 500 characters.")
  end

  defp setup_error_message("Player character detail labels must be unique.") do
    gettext("Player character detail labels must be unique.")
  end

  defp setup_error_message("The label 'description' is reserved for the character summary.") do
    gettext("The label 'description' is reserved for the character summary.")
  end

  defp setup_error_message("Starting item " <> details) do
    case String.split(details, " ", parts: 2) do
      [number, "needs a name up to 160 characters."] ->
        gettext("Starting item %{number} needs a name up to 160 characters.", number: number)

      [number, "needs a positive whole-number quantity."] ->
        gettext("Starting item %{number} needs a positive whole-number quantity.", number: number)

      [number, "has an invalid unit (up to 80 characters)."] ->
        gettext("Starting item %{number} has an invalid unit (up to 80 characters).",
          number: number
        )

      [number, "has an invalid category (up to 100 characters)."] ->
        gettext("Starting item %{number} has an invalid category (up to 100 characters).",
          number: number
        )

      [number, "has an invalid description (up to 2,000 characters)."] ->
        gettext("Starting item %{number} has an invalid description (up to 2,000 characters).",
          number: number
        )

      [number, "must be an object."] ->
        gettext("Starting item %{number} must be an object.", number: number)

      _ ->
        gettext("Campaign setup could not be validated. Review the fields and try again.")
    end
  end

  defp setup_error_message(_message) do
    gettext("Campaign setup could not be validated. Review the fields and try again.")
  end

  defp row_value(row, key) when is_map(row) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.get(row, existing_atom(key), "")
    end
  end

  defp row_value(_row, _key), do: ""

  defp existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp existing_atom(_key), do: nil

  defp voice_value(row, key) when is_map(row) do
    row
    |> row_value("voice_guidance")
    |> row_value(key)
  end

  defp voice_value(_row, _key), do: ""

  defp voice_guidance_present?(row) do
    Enum.any?(~w(quirks accent_dialect cadence vocabulary mannerisms), fn key ->
      case voice_value(row, key) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  defp voice_guidance_count(row),
    do: row |> row_value("voice_guidance") |> VoiceGuidance.character_count()

  defp voice_guidance_over_limit?(row),
    do: voice_guidance_count(row) > VoiceGuidance.max_total_length()

  defp panel_type_label(:quantity), do: gettext("Quantity")
  defp panel_type_label(:money), do: gettext("Money")
  defp panel_type_label(:text), do: gettext("Text")
  defp panel_type_label(:status), do: gettext("Status")
  defp panel_type_label(:date), do: gettext("Date")

  defp review_fact_rows(facts, excluded_keys) when is_map(facts) do
    facts
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Enum.reject(fn {key, _value} -> key in excluded_keys end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp review_fact_rows(_facts, _excluded_keys), do: []

  defp review_fact(facts, key) when is_map(facts) do
    case Enum.find(facts, fn {fact_key, _value} -> to_string(fact_key) == key end) do
      {_fact_key, value} -> value
      nil -> nil
    end
  end

  defp review_fact(_facts, _key), do: nil

  defp review_value(nil), do: gettext("Not set")

  defp review_value(value) when is_binary(value) do
    if String.trim(value) == "", do: gettext("Not set"), else: value
  end

  defp review_value(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> inspect(value)
    end
  end

  defp review_voice_guidance(guidance) do
    [
      {gettext("Quirks"), Map.get(guidance, "quirks")},
      {gettext("Accent or dialect"), Map.get(guidance, "accent_dialect")},
      {gettext("Cadence"), Map.get(guidance, "cadence")},
      {gettext("Vocabulary"), Map.get(guidance, "vocabulary")},
      {gettext("Mannerisms"), Map.get(guidance, "mannerisms")}
    ]
  end

  defp setup_steps do
    [
      {1, gettext("Story")},
      {2, gettext("Your character")},
      {3, gettext("Opening scene")},
      {4, gettext("People and details")}
    ]
  end

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
