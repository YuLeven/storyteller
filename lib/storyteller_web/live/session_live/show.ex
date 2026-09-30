defmodule StorytellerWeb.SessionLive.Show do
  use StorytellerWeb, :live_view

  alias Storyteller.Auth.OAuth
  alias Storyteller.Campaigns
  alias Storyteller.Play

  @poll_interval 1_500
  @turn_in_progress [:pending, :resolving]
  @turn_blocking [:pending, :resolving, :awaiting_roll]
  @timeline_page_size 500
  @timeline_live_window 20

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
            plan_usage_paused?: Play.plan_usage_paused?(token_store: plan_usage_store()),
            draft: "",
            input_error?: false,
            submission_key: Ecto.UUID.generate(),
            current_turn: nil,
            current_turn_roll: nil,
            projection: nil,
            player_character: nil,
            characters_by_id: %{},
            timeline: [],
            current_situation: nil,
            timeline_history: [],
            timeline_live: [],
            timeline_has_earlier?: false,
            timeline_loaded_earlier?: false,
            game_error: nil,
            turn_announcement: "",
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

  def handle_event("resume-plan-usage", _params, socket) do
    case Play.resume_plan_usage(token_store: plan_usage_store()) do
      :ok ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :info,
           gettext("Plan requests are resumed. Retry a saved turn when you are ready.")
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :error,
           gettext("The account-wide pause could not be cleared. Please try again.")
         )}
    end
  end

  @impl true
  def handle_event("load-earlier-story", _params, socket) do
    case List.first(socket.assigns.timeline) do
      %{sequence: before_sequence} ->
        case Play.public_timeline_page(socket.assigns.session.campaign_id,
               before_sequence: before_sequence,
               limit: @timeline_page_size
             ) do
          {:ok, %{events: events, has_earlier?: has_earlier?}} ->
            timeline = merge_timeline(socket.assigns.timeline, events)

            {:noreply,
             socket
             |> assign(
               timeline: timeline,
               timeline_has_earlier?: has_earlier?,
               timeline_loaded_earlier?: true
             )
             |> assign_timeline_regions()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Earlier story could not be loaded."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("submit-turn", %{"turn" => params}, socket) do
    input = Map.get(params, "input", "")
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    cond do
      Play.plan_usage_paused?(token_store: plan_usage_store()) ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "ChatGPT plan requests are paused. Check Usage and resume before starting a turn."
           )
         )}

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

    cond do
      Play.plan_usage_paused?(token_store: plan_usage_store()) ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "ChatGPT plan requests are paused. Check Usage and resume before retrying this turn."
           )
         )}

      same_turn?(latest, turn_id) and latest.status == :failed and
        latest.session_id == socket.assigns.session.id and retryable?(latest) ->
        socket =
          socket
          |> start_resolution(latest.id)
          |> maybe_schedule_poll()

        {:noreply, socket}

      true ->
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

      case Play.click_player_d20(
             latest.id,
             roll_source: roll_source,
             token_store: plan_usage_store()
           ) do
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

  attr :event, :map, required: true
  attr :earlier_session?, :boolean, required: true
  attr :characters_by_id, :map, required: true
  attr :projection, :map, required: true

  defp timeline_entry(assigns) do
    ~H"""
    <li
      id={"event-#{@event.sequence}"}
      class="min-w-0"
    >
      <p
        :if={@earlier_session?}
        class="mb-2 text-center text-[11px] font-semibold uppercase tracking-[0.14em] text-stone-400"
      >
        {gettext("Earlier session")}
      </p>
      <article class={[
        "story-entry",
        @event.event_type == :player_action && "story-entry-player",
        @event.event_type == :npc_dialogue && "story-entry-dialogue",
        @event.event_type == :gm_narration && "story-entry-narration",
        @event.event_type in [
          :character_activity,
          :roll_request,
          :player_roll,
          :state_change
        ] &&
          "story-entry-note"
      ]}>
        <div class="mb-1 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-stone-600">
            {case @event.event_type do
              :player_action -> gettext("You")
              :gm_narration -> gettext("Game master")
              :npc_dialogue -> speaker_name(@characters_by_id, @event.speaker_id)
              :character_activity -> speaker_name(@characters_by_id, @event.speaker_id)
              :roll_request -> gettext("Roll requested")
              :player_roll -> gettext("D20 roll")
              :state_change -> state_change_label(@event, @characters_by_id)
            end}
          </h3>
          <time class="text-[11px] text-stone-400">
            {gettext("%{date} at %{time} UTC",
              date: Calendar.strftime(@event.inserted_at, "%Y-%m-%d"),
              time: Calendar.strftime(@event.inserted_at, "%H:%M")
            )}
          </time>
        </div>

        <p
          :if={
            @event.event_type in [
              :player_action,
              :gm_narration,
              :npc_dialogue,
              :character_activity
            ]
          }
          class="whitespace-pre-wrap leading-7 text-stone-800"
        >
          {event_text(@event)}
        </p>

        <p :if={@event.event_type == :roll_request} class="leading-7 text-stone-800">
          <span class="block">
            {@projection.characters
            |> Enum.find(&(&1.role == :player))
            |> then(fn character -> character && character.name end) ||
              gettext("Your character")} {gettext("needs to roll")} <strong>{@event.payload["test"]}</strong>.
          </span>
          <span
            :if={@event.payload["difficulty"]}
            class="mt-1 block text-sm text-stone-600"
          >
            {gettext("Difficulty:")} {@event.payload["difficulty"]}
          </span>
          <span :if={@event.payload["target"]} class="mt-1 block text-sm text-stone-600">
            {gettext("Target:")} {@event.payload["target"]}
          </span>
        </p>

        <p :if={@event.event_type == :player_roll} class="font-semibold text-violet-900">
          {gettext("D20 result:")} {@event.payload["result"]}
        </p>

        <p
          :if={@event.event_type == :state_change && state_change_reason(@event)}
          class="mt-2 text-sm leading-6 text-stone-600"
        >
          {gettext("Reason: %{reason}", reason: state_change_reason(@event))}
        </p>

        <dl
          :if={@event.event_type == :state_change && map_size(state_change_values(@event)) > 0}
          class="mt-2 grid gap-2 text-sm sm:grid-cols-[8rem_minmax(0,1fr)]"
        >
          <div :for={{key, value} <- state_change_values(@event)} class="contents">
            <dt class="font-medium text-stone-600">{world_label(key)}</dt>
            <dd class="whitespace-pre-wrap text-stone-800">{display_value(value)}</dd>
          </div>
        </dl>
        <ul
          :if={@event.event_type == :state_change && panel_change_values(@event) != []}
          class="mt-2 space-y-2 text-sm text-stone-700"
        >
          <li :for={change <- panel_change_values(@event)}>
            <p class="font-medium text-stone-800">{panel_change_summary(change)}</p>
            <p>{panel_change_operation(change)}</p>
            <p class="text-stone-600">
              {gettext("Reason: %{reason}", reason: change["reason"])}
            </p>
          </li>
        </ul>
        <ul
          :if={@event.event_type == :state_change && inventory_change_values(@event) != []}
          class="mt-2 space-y-1 text-sm text-stone-700"
        >
          <li :for={change <- inventory_change_values(@event)}>
            {inventory_event_text(change, @characters_by_id)}
          </li>
        </ul>
        <ul
          :if={@event.event_type == :state_change && location_change_values(@event) != []}
          class="mt-2 space-y-1 text-sm text-stone-700"
        >
          <li :for={change <- location_change_values(@event)}>
            {location_event_text(change, @characters_by_id)}
          </li>
        </ul>
        <ul
          :if={@event.event_type == :state_change && objective_change_values(@event) != []}
          class="mt-2 space-y-1 text-sm text-stone-700"
        >
          <li :for={change <- objective_change_values(@event)}>
            {objective_event_text(change)}
          </li>
        </ul>
      </article>
    </li>
    """
  end

  defp submit_turn(socket, input, key) do
    case Play.submit_turn(
           socket.assigns.session.campaign_id,
           socket.assigns.session.id,
           key,
           input,
           token_store: plan_usage_store()
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

      {:error, :plan_usage_paused} ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "ChatGPT plan requests are paused. Check Usage and resume before starting a turn."
           )
         )}

      {:error, :plan_usage_state_unavailable} ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> refresh_game()
         |> put_flash(
           :error,
           gettext("The ChatGPT plan pause could not be checked. Please try again.")
         )}

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
         {:ok, %{events: recent_events, has_earlier?: has_earlier?}} <-
           Play.public_timeline_page(campaign_id, limit: @timeline_page_size) do
      timeline = merge_timeline(socket.assigns.timeline, recent_events)

      timeline_has_earlier? =
        if socket.assigns.timeline_loaded_earlier?,
          do: socket.assigns.timeline_has_earlier?,
          else: has_earlier?

      current_turn = Play.public_current_turn(campaign_id)
      previous_turn = socket.assigns.current_turn
      current_turn_roll = player_roll_result(timeline, current_turn)

      socket =
        assign(socket,
          projection: projection,
          player_character: Enum.find(projection.characters, &(&1.speaker_id == "player")),
          characters_by_id: Map.new(projection.characters, &{&1.speaker_id, &1}),
          timeline: timeline,
          current_situation: latest_public_narration(timeline),
          plan_usage_paused?: Play.plan_usage_paused?(token_store: plan_usage_store()),
          timeline_has_earlier?: timeline_has_earlier?,
          current_turn: current_turn,
          current_turn_roll: current_turn_roll,
          game_error: nil
        )

      socket
      |> announce_turn_status(previous_turn, current_turn, current_turn_roll)
      |> assign_timeline_regions(recent_events)
    else
      _ ->
        assign(socket, game_error: gettext("The campaign's play state could not be refreshed."))
    end
  end

  defp latest_public_narration(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{event_type: :gm_narration, payload: %{"text" => text}}
      when is_binary(text) ->
        if String.trim(text) == "", do: nil, else: text

      _event ->
        nil
    end)
  end

  defp player_roll_result(_events, nil), do: nil

  defp player_roll_result(events, %{id: turn_id}) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{
        event_type: :player_roll,
        turn_id: ^turn_id,
        payload: %{"result" => result}
      } ->
        result

      _event ->
        nil
    end)
  end

  defp merge_timeline(existing, incoming), do: merge_timeline(existing, incoming, [])

  defp merge_timeline([], incoming, acc), do: Enum.reverse(acc, incoming)
  defp merge_timeline(existing, [], acc), do: Enum.reverse(acc, existing)

  defp merge_timeline(
         [%{sequence: left_sequence} = event | left],
         [%{sequence: right_sequence} | _] = incoming,
         acc
       )
       when left_sequence < right_sequence do
    merge_timeline(left, incoming, [event | acc])
  end

  defp merge_timeline(
         [%{sequence: left_sequence} | _] = existing,
         [%{sequence: right_sequence} = event | right],
         acc
       )
       when left_sequence > right_sequence do
    merge_timeline(existing, right, [event | acc])
  end

  defp merge_timeline([event | left], [_duplicate | right], acc),
    do: merge_timeline(left, right, [event | acc])

  defp assign_timeline_regions(socket, recent_events \\ nil) do
    latest_events = recent_events || socket.assigns.timeline

    live_from_sequence =
      latest_events
      |> Enum.take(-@timeline_live_window)
      |> List.first()
      |> case do
        %{sequence: sequence} -> sequence
        _ -> nil
      end

    {indexed_events, _previous_session_id} =
      socket.assigns.timeline
      |> Enum.with_index()
      |> Enum.map_reduce(nil, fn {event, index}, previous_session_id ->
        earlier_session? =
          event.session_id != socket.assigns.session.id and
            (index == 0 or previous_session_id != event.session_id)

        {{event, earlier_session?}, event.session_id}
      end)

    {history, live} =
      Enum.split_with(indexed_events, fn {event, _earlier_session?} ->
        is_nil(live_from_sequence) or event.sequence < live_from_sequence
      end)

    assign(socket,
      timeline_history: history,
      timeline_live: live
    )
  end

  defp maybe_start_resolution(socket, turn) do
    if not socket.assigns.plan_usage_paused? and not is_nil(turn) and
         turn.session_id == socket.assigns.session.id and
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
             _ =
               Play.retry_turn(turn_id,
                 provider: provider,
                 token_store: plan_usage_store()
               )

             send(owner, {:turn_resolution_finished, turn_id})
           end) do
        {:ok, _pid} ->
          socket = assign(socket, worker_turn_id: turn_id)

          if connected?(socket) and
               same_turn?(socket.assigns.current_turn, to_string(turn_id)) do
            assign(
              socket,
              turn_announcement:
                turn_announcement(
                  socket.assigns.current_turn,
                  socket.assigns.current_turn_roll,
                  turn_id
                )
            )
          else
            socket
          end

        {:error, _reason} ->
          socket
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

  defp plan_usage_store do
    Application.get_env(:storyteller, :plan_usage_token_store, Storyteller.Auth.TokenStore)
  end

  defp announce_turn_status(socket, previous_turn, current_turn, current_turn_roll) do
    cond do
      not connected?(socket) ->
        socket

      is_nil(current_turn) and not is_nil(previous_turn) ->
        assign(socket, turn_announcement: gettext("Your turn is complete."))

      is_nil(current_turn) ->
        socket

      true ->
        assign(
          socket,
          turn_announcement:
            turn_announcement(current_turn, current_turn_roll, socket.assigns.worker_turn_id)
        )
    end
  end

  defp turn_announcement(%{status: status} = turn, result, worker_turn_id)
       when status in [:pending, :resolving] do
    if worker_turn_id == turn.id do
      responding_announcement(turn, result)
    else
      append_roll_result(gettext("Reconnecting to the saved turn…"), result)
    end
  end

  defp turn_announcement(
         %{status: :awaiting_roll, roll_request: request},
         _result,
         _worker_turn_id
       ) do
    if valid_roll_request?(request) do
      test = request["test"] || request[:test]

      gettext("Roll requested") <>
        ": " <>
        test <>
        ". " <>
        gettext("The game master is waiting. Click only when you are ready to roll the D20.")
    else
      ""
    end
  end

  defp turn_announcement(%{status: :failed} = turn, result, worker_turn_id) do
    prefix =
      if worker_turn_id == turn.id do
        gettext("Retrying…")
      else
        gettext("This turn needs attention") <> ". " <> failure_message(turn.failure_code)
      end

    append_roll_result(prefix, result)
  end

  defp turn_announcement(_turn, _result, _worker_turn_id), do: ""

  defp responding_announcement(%{resolution_phase: :after_roll}, result) when not is_nil(result),
    do: append_roll_result(gettext("The game master is responding"), result)

  defp responding_announcement(_turn, _result), do: gettext("The game master is responding")

  defp append_roll_result(message, nil), do: message

  defp append_roll_result(message, result),
    do: message <> " " <> gettext("D20 result:") <> " " <> to_string(result)

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

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value) when is_number(value), do: to_string(value)

  defp display_value(value) when is_boolean(value),
    do: if(value, do: gettext("Yes"), else: gettext("No"))

  defp display_value(value), do: Jason.encode!(value)

  defp inventory_property_rows(properties) when is_map(properties) do
    properties
    |> Enum.sort_by(fn {key, _value} -> inventory_property_key(key) end)
    |> Enum.flat_map(fn {key, value} ->
      flatten_inventory_property([inventory_property_key(key)], value)
    end)
  end

  defp inventory_property_rows(_properties), do: []

  defp flatten_inventory_property(path, properties)
       when is_map(properties) and map_size(properties) > 0 do
    properties
    |> Enum.sort_by(fn {key, _value} -> inventory_property_key(key) end)
    |> Enum.flat_map(fn {key, value} ->
      flatten_inventory_property(path ++ [inventory_property_key(key)], value)
    end)
  end

  defp flatten_inventory_property(path, value),
    do: [{Enum.join(path, " / "), compact_inventory_property_value(value)}]

  defp inventory_property_key(key) when is_binary(key) do
    key
    |> String.replace(~r/[_-]+/u, " ")
    |> String.trim()
    |> String.capitalize()
  end

  defp inventory_property_key(key) when is_atom(key),
    do: key |> Atom.to_string() |> inventory_property_key()

  defp inventory_property_key(key), do: inspect(key)

  defp compact_inventory_property_value(value) when is_binary(value), do: value

  defp compact_inventory_property_value(value) when is_integer(value),
    do: Integer.to_string(value)

  defp compact_inventory_property_value(value) when is_float(value), do: Float.to_string(value)
  defp compact_inventory_property_value(true), do: "true"
  defp compact_inventory_property_value(false), do: "false"
  defp compact_inventory_property_value(nil), do: "null"

  defp compact_inventory_property_value(value) when is_list(value) do
    "[" <> Enum.map_join(value, ", ", &compact_inventory_collection_value/1) <> "]"
  end

  defp compact_inventory_property_value(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.sort_by(fn {key, _value} -> inventory_property_key(key) end)
       |> Enum.map_join(", ", fn {key, nested_value} ->
         "#{inventory_property_key(key)}: #{compact_inventory_collection_value(nested_value)}"
       end)) <> "}"
  end

  defp compact_inventory_collection_value(value) when is_binary(value), do: Jason.encode!(value)
  defp compact_inventory_collection_value(value), do: compact_inventory_property_value(value)

  defp state_change_label(event, characters) do
    cond do
      is_list(Map.get(event.payload, "inventory_changes")) ->
        gettext("Inventory")

      is_list(Map.get(event.payload, "location_changes")) ->
        gettext("Places and travel")

      is_list(Map.get(event.payload, "objective_changes")) ->
        gettext("Campaign objectives")

      is_map(Map.get(event.payload, "character_created")) ->
        gettext("Character introduced")

      is_list(Map.get(event.payload, "panel_changes")) or
          is_map(Map.get(event.payload, "panel_changes")) ->
        gettext("Campaign values")

      event.speaker_id == "player" and is_map(Map.get(event.payload, "visible_facts")) ->
        gettext("Character details updated")

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

  defp state_change_values(%{payload: %{"character_created" => created}}) when is_map(created) do
    created
    |> Map.get("visible_facts", %{})
    |> Map.put("name", Map.get(created, "name"))
  end

  defp state_change_values(%{payload: %{"visible_facts" => facts}}) when is_map(facts),
    do: facts

  defp state_change_values(_event), do: %{}

  defp panel_change_values(%{payload: %{"panel_changes" => changes}}) when is_list(changes),
    do: changes

  defp panel_change_values(_event), do: []

  defp panel_change_summary(change) do
    gettext("%{label}: %{before} → %{after}",
      label: Map.get(change, "label", Map.get(change, "key", "")),
      before: panel_value(Map.get(change, "before"), Map.get(change, "unit")),
      after: panel_value(Map.get(change, "after"), Map.get(change, "unit"))
    )
  end

  defp panel_change_operation(%{"type" => "delta", "delta" => delta} = change) do
    value = display_value(delta)
    value = if String.starts_with?(value, "-"), do: value, else: "+" <> value
    gettext("Change: %{change}", change: panel_value(value, Map.get(change, "unit")))
  end

  defp panel_change_operation(%{"type" => "set", "value" => value} = change) do
    gettext("Change: set to %{value}", value: panel_value(value, Map.get(change, "unit")))
  end

  defp panel_change_operation(_change), do: gettext("Campaign value changed")

  defp panel_value(value, unit) do
    value =
      if is_nil(value) or value == "", do: gettext("Not recorded"), else: display_value(value)

    if is_binary(unit) and unit != "", do: "#{value} #{unit}", else: value
  end

  defp state_change_reason(%{payload: %{"visible_facts" => facts, "reason" => reason}})
       when is_map(facts) and is_binary(reason),
       do: reason

  defp state_change_reason(_event), do: nil

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

  defp player_world_location(%{current_place: %{name: name}}, _world)
       when is_binary(name) and name != "",
       do: name

  defp player_world_location(_player_character, world),
    do: world_display(world, ["location", "current_location"])

  defp world_label(key) do
    case to_string(key) do
      "date" -> gettext("Date")
      "time" -> gettext("Time")
      "world_time" -> gettext("Time")
      "weather" -> gettext("Weather")
      "location" -> gettext("Location")
      "name" -> gettext("Name")
      custom -> custom |> String.replace("_", " ") |> String.capitalize()
    end
  end

  defp event_text(event), do: Map.get(event.payload, "text", "")

  defp failure_message("reauth_required"),
    do: gettext("The connected account needs you to reconnect before this turn can continue.")

  defp failure_message("account_ineligible"),
    do: gettext("The connected account is not eligible to continue this turn.")

  defp failure_message("usage_limit"),
    do:
      gettext(
        "ChatGPT reported a plan usage limit, so requests are paused in every session. Check Usage settings, resume when you believe requests are available, then retry this saved turn."
      )

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
