defmodule StorytellerWeb.SessionLive.Show do
  use StorytellerWeb, :live_view

  alias Storyteller.Auth.OAuth
  alias Storyteller.Campaigns
  alias Storyteller.Play

  @poll_interval 1_500
  @turn_in_progress [:pending, :resolving]
  @turn_blocking [:pending, :resolving, :awaiting_roll]

  @impl true
  def mount(%{"campaign_id" => campaign_id, "session_id" => session_id}, _session, socket) do
    case Campaigns.get_session(campaign_id, session_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That session could not be found in this campaign."))
         |> push_navigate(to: ~p"/")}

      session ->
        socket =
          assign(socket,
            page_title: session.title,
            session: session,
            plan_usage_enabled?: OAuth.status().plan_usage_enabled?,
            draft: "",
            input_error?: false,
            submission_key: Ecto.UUID.generate(),
            current_turn: nil,
            projection: nil,
            player_character: nil,
            characters_by_id: %{},
            timeline: [],
            game_error: nil,
            worker_turn_id: nil,
            poll_scheduled?: false
          )

        case Play.initialize_campaign(session.campaign) do
          {:ok, _state} ->
            socket = refresh_game(socket)
            socket = maybe_start_resolution(socket, socket.assigns.current_turn)
            {:ok, maybe_schedule_poll(socket)}

          {:error, _reason} ->
            {:ok,
             assign(socket, game_error: gettext("The campaign's play state could not be loaded."))}
        end
    end
  end

  @impl true
  def handle_event("change-input", %{"turn" => %{"input" => input}}, socket) do
    {:noreply, assign(socket, draft: input, input_error?: false)}
  end

  def handle_event("use-in-action", %{"item_id" => item_id}, socket) when is_binary(item_id) do
    item = player_action_item(socket.assigns.projection, item_id)
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    if item && playable?(socket.assigns.session) && not blocking_turn?(latest) do
      sentence =
        item_action_sentence(item["name"], socket.assigns.session.campaign.narration_language)

      {:noreply,
       assign(socket,
         draft: append_action_sentence(socket.assigns.draft, sentence),
         input_error?: false
       )}
    else
      # Unknown, hidden, or non-player-owned item IDs deliberately have the same result.
      {:noreply, socket}
    end
  end

  def handle_event("use-in-action", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("submit-turn", %{"turn" => params}, socket) do
    input = Map.get(params, "input", "")
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    cond do
      not playable?(socket.assigns.session) ->
        {:noreply,
         put_flash(socket, :error, gettext("This session is available for review only."))}

      blocking_turn?(latest) ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(:error, gettext("Finish the current turn before sending another action."))}

      true ->
        submit_turn(socket, input, Map.get(params, "idempotency_key", ""))
    end
  end

  @impl true
  def handle_event("retry-turn", %{"turn_id" => turn_id}, socket) do
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    if same_turn?(latest, turn_id) and latest.status == :failed and
         latest.session_id == socket.assigns.session.id and retryable?(latest) do
      socket =
        socket
        |> start_resolution(latest.id)
        |> maybe_schedule_poll()

      {:noreply, socket}
    else
      {:noreply,
       socket
       |> refresh_game()
       |> put_flash(:error, gettext("That turn cannot be retried from this session."))}
    end
  end

  @impl true
  def handle_event("roll-d20", %{"turn_id" => turn_id}, socket) do
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    if same_turn?(latest, turn_id) and latest.session_id == socket.assigns.session.id and
         latest.status == :awaiting_roll and valid_roll_request?(latest.roll_request) and
         playable?(socket.assigns.session) do
      roll_source =
        Application.get_env(:storyteller, :d20_roll_source, fn -> :rand.uniform(20) end)

      case Play.click_player_d20(latest.id, roll_source: roll_source) do
        {:ok, _result} ->
          socket = refresh_game(socket)
          socket = maybe_start_resolution(socket, socket.assigns.current_turn)
          {:noreply, maybe_schedule_poll(socket)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> refresh_game()
           |> put_flash(:error, gettext("The requested roll could not be recorded."))}
      end
    else
      {:noreply,
       socket
       |> refresh_game()
       |> put_flash(:error, gettext("There is no validated D20 request to roll right now."))}
    end
  end

  @impl true
  def handle_info(:refresh_turn, socket) do
    socket =
      socket
      |> assign(poll_scheduled?: false)
      |> refresh_game()

    socket = maybe_start_resolution(socket, socket.assigns.current_turn)
    {:noreply, maybe_schedule_poll(socket)}
  end

  @impl true
  def handle_info({:turn_resolution_finished, turn_id}, socket) do
    worker_turn_id =
      if socket.assigns.worker_turn_id == turn_id, do: nil, else: socket.assigns.worker_turn_id

    socket =
      socket
      |> assign(worker_turn_id: worker_turn_id)
      |> refresh_game()
      |> maybe_schedule_poll()

    {:noreply, socket}
  end

  defp submit_turn(socket, input, key) do
    case Play.submit_turn(
           socket.assigns.session.campaign_id,
           socket.assigns.session.id,
           key,
           input
         ) do
      {:ok, _turn} ->
        socket =
          socket
          |> assign(draft: "", input_error?: false, submission_key: Ecto.UUID.generate())
          |> refresh_game()

        socket = maybe_start_resolution(socket, socket.assigns.current_turn)
        {:noreply, maybe_schedule_poll(socket)}

      {:error, :invalid_player_input} ->
        {:noreply, assign(socket, draft: input, input_error?: true)}

      {:error, :turn_already_open} ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(:error, gettext("A turn is already waiting for resolution."))}

      {:error, :idempotency_conflict} ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> put_flash(
           :error,
           gettext("This submission changed while it was being sent. Please send it again.")
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> put_flash(:error, gettext("Your action could not be saved. Please try again."))}
    end
  end

  defp refresh_game(socket) do
    campaign_id = socket.assigns.session.campaign_id

    with {:ok, projection} <- Play.public_projection(campaign_id),
         {:ok, timeline} <- Play.public_timeline(campaign_id) do
      assign(socket,
        projection: projection,
        player_character: Enum.find(projection.characters, &(&1.speaker_id == "player")),
        characters_by_id: Map.new(projection.characters, &{&1.speaker_id, &1}),
        timeline: timeline,
        current_turn: Play.public_current_turn(campaign_id),
        game_error: nil
      )
    else
      _ ->
        assign(socket, game_error: gettext("The campaign's play state could not be refreshed."))
    end
  end

  defp maybe_start_resolution(socket, turn) do
    if not is_nil(turn) and turn.session_id == socket.assigns.session.id and
         turn.status in @turn_in_progress and playable?(socket.assigns.session) do
      start_resolution(socket, turn.id)
    else
      socket
    end
  end

  defp start_resolution(socket, turn_id) do
    if socket.assigns.worker_turn_id == turn_id do
      socket
    else
      owner = self()
      provider = Application.get_env(:storyteller, :gm_provider, Storyteller.GM.OpenAI)

      case Task.start(fn ->
             _ = Play.retry_turn(turn_id, provider: provider)
             send(owner, {:turn_resolution_finished, turn_id})
           end) do
        {:ok, _pid} -> assign(socket, worker_turn_id: turn_id)
        {:error, _reason} -> socket
      end
    end
  end

  defp maybe_schedule_poll(socket) do
    turn = socket.assigns.current_turn

    retry_in_flight? = not is_nil(turn) and socket.assigns.worker_turn_id == turn.id

    if connected?(socket) and not socket.assigns.poll_scheduled? and not is_nil(turn) and
         turn.session_id == socket.assigns.session.id and
         (turn.status in @turn_in_progress or retry_in_flight?) do
      Process.send_after(self(), :refresh_turn, @poll_interval)
      assign(socket, poll_scheduled?: true)
    else
      socket
    end
  end

  defp playable?(session) do
    session.status == :active and session.campaign.status == :active
  end

  defp blocking_turn?(%{status: status}), do: status in @turn_blocking
  defp blocking_turn?(_turn), do: false

  defp same_turn?(%{id: id}, turn_id), do: to_string(id) == turn_id
  defp same_turn?(_turn, _turn_id), do: false

  defp retryable?(turn), do: turn.failure_code not in ["session_closed", "campaign_archived"]

  defp valid_roll_request?(request) when is_map(request) do
    test = request["test"] || request[:test]
    difficulty = request["difficulty"] || request[:difficulty]
    target = request["target"] || request[:target]

    is_binary(test) and String.trim(test) != "" and
      ((is_binary(difficulty) and String.trim(difficulty) != "") or is_integer(target) or
         (is_binary(target) and String.trim(target) != ""))
  end

  defp valid_roll_request?(_), do: false

  defp speaker_name(characters, speaker_id) do
    case Map.get(characters, speaker_id) do
      %{name: name} -> name
      _ -> gettext("Someone nearby")
    end
  end

  defp player_action_item(%{inventory: inventory}, item_id) when is_list(inventory) do
    Enum.find(inventory, fn item ->
      item["id"] == item_id and item["visibility"] == "public" and
        item["owner_id"] in ["player", "party"]
    end)
  end

  defp player_action_item(_projection, _item_id), do: nil

  defp item_action_sentence(item_name, narration_language) do
    locale =
      case narration_language do
        "Spanish" -> "es"
        "French" -> "fr"
        _ -> "en"
      end

    Gettext.with_locale(StorytellerWeb.Gettext, locale, fn ->
      gettext("I use %{item}.", item: item_name)
    end)
  end

  defp append_action_sentence(draft, sentence) do
    draft = String.trim_trailing(draft || "")

    if draft == "", do: sentence, else: draft <> "\n" <> sentence
  end

  defp public_values(map) do
    Enum.reject(map, fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value) when is_number(value), do: to_string(value)

  defp display_value(value) when is_boolean(value),
    do: if(value, do: gettext("Yes"), else: gettext("No"))

  defp display_value(value), do: Jason.encode!(value)

  defp earlier_session_start?(timeline, index, current_session_id) do
    event = Enum.at(timeline, index)

    event.session_id != current_session_id and
      (index == 0 or Enum.at(timeline, index - 1).session_id != event.session_id)
  end

  defp state_change_label(event, characters) do
    cond do
      is_list(Map.get(event.payload, "inventory_changes")) ->
        gettext("Inventory")

      is_list(Map.get(event.payload, "location_changes")) ->
        gettext("Places and travel")

      is_list(Map.get(event.payload, "objective_changes")) ->
        gettext("Campaign objectives")

      is_map(Map.get(event.payload, "panel_changes")) ->
        gettext("Campaign values")

      is_nil(event.speaker_id) ->
        gettext("World update")

      true ->
        gettext("%{character}: known details",
          character: speaker_name(characters, event.speaker_id)
        )
    end
  end

  defp state_change_values(%{payload: %{"panel_changes" => changes}}) when is_map(changes),
    do: changes

  defp state_change_values(%{payload: %{"changes" => changes}}) when is_map(changes), do: changes

  defp state_change_values(%{payload: %{"visible_facts" => facts}}) when is_map(facts),
    do: facts

  defp state_change_values(_event), do: %{}

  defp inventory_change_values(%{payload: %{"inventory_changes" => changes}})
       when is_list(changes),
       do: changes

  defp inventory_change_values(_event), do: []

  defp location_change_values(%{payload: %{"location_changes" => changes}}) when is_list(changes),
    do: changes

  defp location_change_values(_event), do: []

  defp objective_change_values(%{payload: %{"objective_changes" => changes}})
       when is_list(changes),
       do: changes

  defp objective_change_values(_event), do: []

  defp objective_event_text(%{"type" => "create", "objective" => objective}) do
    gettext("Added objective: %{title} (%{status})",
      title: objective["title"],
      status: objective_status_label(objective["status"])
    )
  end

  defp objective_event_text(%{"objective" => objective}) do
    gettext("Updated objective: %{title} (%{status})",
      title: objective["title"],
      status: objective_status_label(objective["status"])
    )
  end

  defp objective_event_text(_change), do: gettext("Campaign objective updated")

  defp objectives_for_status(objectives, status),
    do: Enum.filter(objectives, &(&1.status == status))

  defp objective_status_label(:open), do: gettext("Open")
  defp objective_status_label("open"), do: gettext("Open")
  defp objective_status_label(:completed), do: gettext("Completed")
  defp objective_status_label("completed"), do: gettext("Completed")
  defp objective_status_label(:abandoned), do: gettext("Abandoned")
  defp objective_status_label("abandoned"), do: gettext("Abandoned")
  defp objective_status_label(_status), do: gettext("Unknown status")

  defp character_location_label(%{current_place: nil}, _player_character),
    do: gettext("No known location")

  defp character_location_label(character, %{current_place_id: place_id})
       when not is_nil(place_id) and character.current_place_id == place_id,
       do: gettext("Here")

  defp character_location_label(character, _player_character), do: character.current_place.name

  defp characters_here(_characters, %{current_place_id: nil}), do: []

  defp characters_here(characters, player_character) do
    Enum.filter(characters, fn character ->
      character.speaker_id != "player" and
        character.current_place_id == player_character.current_place_id
    end)
  end

  defp location_event_text(%{"type" => "create_place", "place_name" => name}, _characters) do
    gettext("Discovered %{place}", place: name)
  end

  defp location_event_text(
         %{"type" => "move_character", "character_name" => character, "place_name" => place},
         _characters
       ) do
    gettext("%{character} moved to %{place}", character: character, place: place)
  end

  defp location_event_text(_change, _characters), do: gettext("A location changed")

  defp inventory_event_text(%{"type" => "add", "item" => item}, _characters) do
    gettext("Added %{quantity} %{item}",
      quantity: quantity_label(item["quantity"], item["unit"]),
      item: item["name"]
    )
  end

  defp inventory_event_text(
         %{"type" => "transfer", "item_name" => item, "owner_id" => owner_id} = change,
         characters
       ) do
    gettext("Transferred %{quantity} %{item} to %{owner}",
      quantity: quantity_label(change["quantity"], change["unit"]),
      item: item,
      owner: inventory_owner_name(owner_id, characters)
    )
  end

  defp inventory_event_text(
         %{"type" => "consume", "item_name" => item, "quantity" => quantity} = change,
         _characters
       ) do
    gettext("Used %{quantity} %{item}",
      quantity: quantity_label(quantity, change["unit"]),
      item: item
    )
  end

  defp inventory_event_text(_change, _characters), do: gettext("Inventory updated")

  defp quantity_label(quantity, nil), do: to_string(quantity)
  defp quantity_label(quantity, unit), do: "#{quantity} #{unit}"

  defp inventory_owner_name("party", _characters), do: gettext("the party stash")
  defp inventory_owner_name(owner_id, characters), do: speaker_name(characters, owner_id)

  defp world_display(world, keys) do
    case Enum.find(keys, fn key ->
           Map.has_key?(world, key) and not is_nil(Map.get(world, key)) and
             Map.get(world, key) != ""
         end) do
      nil -> gettext("Not recorded")
      key -> display_value(Map.get(world, key))
    end
  end

  defp world_label(key) do
    case to_string(key) do
      "date" -> gettext("Date")
      "time" -> gettext("Time")
      "world_time" -> gettext("Time")
      "weather" -> gettext("Weather")
      "location" -> gettext("Location")
      custom -> custom |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp event_text(event), do: Map.get(event.payload, "text", "")

  defp failure_message("reauth_required"),
    do: gettext("The connected account needs you to reconnect before this turn can continue.")

  defp failure_message("account_ineligible"),
    do: gettext("The connected account is not eligible to continue this turn.")

  defp failure_message("usage_limit"),
    do: gettext("The connected account has reached its current usage limit.")

  defp failure_message("usage_unavailable"),
    do: gettext("The connected account's usage could not be confirmed.")

  defp failure_message("model_unavailable"),
    do: gettext("No available model could resolve this turn.")

  defp failure_message("timeout"),
    do: gettext("The game master took too long to answer. Your turn is saved.")

  defp failure_message(_),
    do: gettext("The game master could not resolve this turn. Your action is saved.")

  defp reconnect_needed?(code),
    do: code in ["reauth_required", "account_ineligible", "model_unavailable"]
end
