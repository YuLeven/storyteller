defmodule StorytellerWeb.SessionLive.Show do
  use StorytellerWeb, :live_view

  alias Storyteller.Auth.OAuth
  alias Storyteller.Campaigns
  alias Storyteller.Play
  alias Storyteller.Play.CanonCorrections

  @poll_interval 1_500
  @turn_in_progress [:pending, :resolving]
  @turn_blocking [:pending, :resolving, :awaiting_roll]
  @timeline_page_size 500
  @timeline_live_window 20
  @night_time_words ~w(night nighttime midnight tonight dusk evening nightfall noche nocturno nocturna medianoche anochecer atardecer nuit minuit soir nocturne crepuscule)
  @day_time_words ~w(day daytime daylight morning midmorning dawn sunrise noon midday afternoon dia manana amanecer mediodia tarde jour journee matin matinee aube midi apres-midi)
  @mist_weather_words ~w(mist misty fog foggy haze hazy neblina niebla bruma brumoso brumosa brouillard brume)
  @rain_weather_words ~w(rain rains raining rainy drizzle shower showers lluvia lluvioso lloviendo llovizna tormenta pluie pleut pluvieux bruine averse orage orageux)
  @snow_weather_words ~w(snow snowy snowfall flurry flakes nieve nevado nevada neige neigeux flocon flocons)
  @cloud_weather_words ~w(cloud clouds cloudy overcast nublado nuboso nuage nuageux nuageuse couvert)
  @clear_weather_words ~w(clear sunny sunshine despejado despejada soleado soleada claro clara ensoleille degage beau)

  @impl true
  def mount(%{"campaign_id" => campaign_id, "session_id" => session_id}, _session, socket) do
    case Campaigns.get_session(campaign_id, session_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That session could not be found in this campaign."))
         |> push_navigate(to: ~p"/")}

      session ->
        usage_status = current_plan_usage_status()

        socket =
          assign(socket,
            page_title: session.title,
            session: session,
            plan_usage_enabled?: OAuth.status().plan_usage_enabled?,
            plan_usage_status: usage_status,
            plan_usage_paused?: usage_status == :paused,
            plan_usage_blocked?: usage_status != :available,
            draft: "",
            interaction_mode: :action,
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
            worker_pid: nil,
            worker_monitor_ref: nil,
            worker_tag: nil,
            worker_attempt: nil,
            turn_first_output_id: nil,
            poll_scheduled?: false,
            correction_options: nil,
            correction_receipts: [],
            correction_form: %{"kind" => "inventory", "action" => "add", "owner_id" => "player"},
            correction_open?: false,
            campaign_reference_open?: false,
            campaign_tools_open?: false,
            correction_error: nil,
            memory_editor: nil,
            memory_form: default_story_memory_form(),
            memory_submit: "save",
            memory_error: nil,
            memory_status: nil
          )

        case Play.initialize_campaign(session.campaign) do
          {:ok, _state} ->
            case Play.ensure_opening_scene(session.campaign_id, session.id) do
              {:ok, _opening_turn} ->
                socket = refresh_game(socket)
                socket = maybe_start_resolution(socket, socket.assigns.current_turn)
                {:ok, maybe_schedule_poll(socket)}

              {:error, _reason} ->
                {:ok,
                 assign(
                   socket,
                   game_error: gettext("The campaign's opening scene could not be started.")
                 )}
            end

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

  def handle_event("change-input", _params, socket), do: {:noreply, socket}

  def handle_event("open-campaign-reference", _params, socket) do
    {:noreply, assign(socket, campaign_reference_open?: true)}
  end

  def handle_event("toggle-campaign-reference", _params, socket) do
    {:noreply,
     assign(socket, campaign_reference_open?: not socket.assigns.campaign_reference_open?)}
  end

  def handle_event("toggle-campaign-tools", _params, socket) do
    {:noreply, assign(socket, campaign_tools_open?: not socket.assigns.campaign_tools_open?)}
  end

  def handle_event("change-correction-form", %{"correction" => params}, socket)
      when is_map(params) do
    options = socket.assigns.correction_options || %{}
    previous = socket.assigns.correction_form

    form =
      params
      |> Map.put_new("kind", "inventory")
      |> Map.put_new("action", "add")
      |> maybe_fill_correction_default(previous, options)

    {:noreply, assign(socket, correction_form: form, correction_error: nil)}
  end

  def handle_event("change-correction-form", _params, socket), do: {:noreply, socket}

  def handle_event("toggle-canon-corrections", _params, socket) do
    {:noreply, assign(socket, correction_open?: not socket.assigns.correction_open?)}
  end

  def handle_event("start-canon-correction", %{"kind" => kind, "target-id" => target_id}, socket)
      when is_binary(kind) and is_binary(target_id) do
    options = socket.assigns.correction_options || %{}

    with true <- correction_changes_allowed?(socket),
         {:ok, form} <- contextual_correction_form(kind, target_id, options) do
      {:noreply,
       assign(socket,
         correction_open?: true,
         campaign_tools_open?: true,
         correction_form: form,
         correction_error: nil
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("start-canon-correction", _params, socket), do: {:noreply, socket}

  def handle_event("save-canon-correction", %{"correction" => params}, socket)
      when is_map(params) do
    values =
      Map.take(
        params,
        ~w(action name quantity unit category description owner_id properties value place_id)
      )

    attrs = %{
      "kind" => Map.get(params, "kind"),
      "target_id" => Map.get(params, "target_id"),
      "expected_revision" => Map.get(params, "expected_revision"),
      "reason" => Map.get(params, "reason"),
      "values" => values
    }

    case CanonCorrections.correct(
           socket.assigns.session.campaign_id,
           socket.assigns.session.id,
           attrs
         ) do
      {:ok, _receipt} ->
        socket =
          socket
          |> assign(
            correction_form: default_correction_form(),
            correction_open?: true,
            correction_error: nil
          )
          |> refresh_game()
          |> put_flash(:info, gettext("Correction saved outside the story."))

        {:noreply, socket}

      {:error, reason} ->
        socket =
          assign(socket,
            correction_form: params,
            correction_error: correction_error_message(reason)
          )

        socket = if reason == :stale_correction, do: refresh_game(socket), else: socket
        {:noreply, socket}
    end
  end

  def handle_event("save-canon-correction", _params, socket) do
    {:noreply, assign(socket, correction_error: gettext("The correction could not be saved."))}
  end

  def handle_event("open-story-memory", %{"entry_id" => "new"}, socket) do
    if memory_changes_allowed?(socket) do
      {:noreply,
       assign(socket,
         memory_editor: :new,
         memory_form: default_story_memory_form(),
         memory_submit: "save",
         memory_error: nil,
         memory_status: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-story-memory", %{"entry_id" => entry_id}, socket)
      when is_binary(entry_id) do
    entry =
      socket.assigns.projection.continuity_entries
      |> Enum.find(&(&1.entry_id == entry_id))

    if entry && memory_changes_allowed?(socket) do
      {:noreply,
       assign(socket,
         memory_editor: entry,
         memory_form: %{
           "kind" => Atom.to_string(entry.kind),
           "title" => entry.title,
           "details" => entry.details,
           "reason" => ""
         },
         memory_submit: "save",
         memory_error: nil,
         memory_status: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open-story-memory", _params, socket), do: {:noreply, socket}

  def handle_event("change-story-memory-form", %{"memory" => params}, socket)
      when is_map(params) do
    {:noreply,
     assign(socket,
       memory_form:
         Map.merge(default_story_memory_form(), Map.take(params, ~w(kind title details reason))),
       memory_error: nil
     )}
  end

  def handle_event("change-story-memory-form", _params, socket), do: {:noreply, socket}

  def handle_event("set-story-memory-action", %{"action" => "retract"}, socket) do
    if is_map(socket.assigns.memory_editor) do
      {:noreply, assign(socket, memory_submit: "retract", memory_error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set-story-memory-action", %{"action" => "save"}, socket) do
    {:noreply, assign(socket, memory_submit: "save", memory_error: nil)}
  end

  def handle_event("set-story-memory-action", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-story-memory", _params, socket) do
    {:noreply,
     assign(socket,
       memory_editor: nil,
       memory_form: default_story_memory_form(),
       memory_submit: "save",
       memory_error: nil
     )}
  end

  def handle_event("save-story-memory", %{"memory" => params}, socket) when is_map(params) do
    submit_kind = socket.assigns.memory_submit

    {action, target_id, values} =
      case {socket.assigns.memory_editor, submit_kind} do
        {:new, "save"} ->
          {"add", nil, Map.take(params, ~w(kind title details))}

        {%{entry_id: entry_id}, "save"} ->
          {"update", entry_id, Map.take(params, ~w(kind title details))}

        {%{entry_id: entry_id}, "retract"} ->
          {"retract", entry_id, %{}}

        _ ->
          {nil, nil, %{}}
      end

    if action && memory_changes_allowed?(socket) do
      values = Map.put(values, "action", action)

      attrs = %{
        "kind" => "memory",
        "target_id" => target_id,
        "expected_revision" => Map.get(params, "expected_revision"),
        "reason" => Map.get(params, "reason"),
        "values" => values
      }

      case CanonCorrections.correct(
             socket.assigns.session.campaign_id,
             socket.assigns.session.id,
             attrs
           ) do
        {:ok, _receipt} ->
          message =
            if action == "retract",
              do: gettext("Memory removed from the active campaign board."),
              else: gettext("Campaign memory saved for future scenes.")

          socket =
            socket
            |> assign(
              memory_editor: nil,
              memory_form: default_story_memory_form(),
              memory_submit: "save",
              memory_error: nil,
              memory_status: message
            )
            |> refresh_game()

          {:noreply, socket}

        {:error, reason} ->
          socket =
            assign(socket,
              memory_form:
                Map.merge(
                  default_story_memory_form(),
                  Map.take(params, ~w(kind title details reason))
                ),
              memory_error: story_memory_error_message(reason)
            )

          socket = if reason == :stale_correction, do: refresh_game(socket), else: socket
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-story-memory", _params, socket) do
    {:noreply, assign(socket, memory_error: gettext("The campaign memory could not be saved."))}
  end

  def handle_event("select-mode", %{"mode" => mode}, socket) do
    case interaction_mode(mode) do
      nil ->
        {:noreply, socket}

      mode ->
        {:noreply, assign(socket, interaction_mode: mode, input_error?: false)}
    end
  end

  def handle_event("select-mode", _params, socket), do: {:noreply, socket}

  def handle_event("use-in-action", %{"item_id" => item_id}, socket) when is_binary(item_id) do
    item = player_action_item(socket.assigns.projection, item_id)
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)

    if item && playable?(socket.assigns.session) && not blocking_turn?(latest) do
      sentence =
        item_action_sentence(item["name"], socket.assigns.session.campaign.narration_language)

      next_draft = append_action_sentence(socket.assigns.draft, sentence)

      socket = assign(socket, draft: next_draft, interaction_mode: :action, input_error?: false)
      {:noreply, push_event(socket, "action-composer:update", %{draft: next_draft})}
    else
      # Unknown, hidden, or non-player-owned item IDs deliberately have the same result.
      {:noreply, socket}
    end
  end

  def handle_event("use-in-action", _params, socket), do: {:noreply, socket}

  def handle_event("use-nudge", %{"nudge_id" => nudge_id}, socket) when is_binary(nudge_id) do
    nudge =
      socket.assigns.interaction_mode
      |> contextual_nudges(socket.assigns.projection)
      |> Enum.find(&(&1.id == nudge_id))

    if nudge && playable?(socket.assigns.session) &&
         not blocking_turn?(Play.public_current_turn(socket.assigns.session.campaign_id)) do
      next_draft = append_action_sentence(socket.assigns.draft, nudge.text)
      socket = assign(socket, draft: next_draft, input_error?: false)
      {:noreply, push_event(socket, "action-composer:update", %{draft: next_draft})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("use-nudge", _params, socket), do: {:noreply, socket}

  def handle_event("resume-plan-usage", _params, socket) do
    case Play.resume_plan_usage(token_store: plan_usage_store()) do
      :ok ->
        socket = refresh_game(socket)

        socket =
          if opening_scene_pending?(socket.assigns.current_turn),
            do: maybe_start_resolution(socket, socket.assigns.current_turn),
            else: socket

        {:noreply,
         socket
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

  def handle_event("check-plan-usage-status", _params, socket) do
    {:noreply, refresh_game(socket)}
  end

  @impl true
  def handle_event("load-earlier-story", _params, socket) do
    case List.first(socket.assigns.timeline) do
      %{sequence: before_sequence} ->
        case Play.public_story_timeline_page(socket.assigns.session.campaign_id,
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

    intent =
      interaction_mode(Map.get(params, "intent", Atom.to_string(socket.assigns.interaction_mode)))

    latest = Play.public_current_turn(socket.assigns.session.campaign_id)
    usage_status = current_plan_usage_status()

    cond do
      usage_status == :paused ->
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

      usage_status == :unavailable ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "Account usage status cannot be checked right now. Requests are paused until it can be checked."
           )
         )}

      not playable?(socket.assigns.session) ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> put_flash(:error, gettext("This session is available for review only."))}

      blocking_turn?(latest) ->
        {:noreply,
         socket
         |> assign(draft: input)
         |> refresh_game()
         |> put_flash(:error, gettext("Finish the current turn before sending another action."))}

      is_nil(intent) ->
        {:noreply,
         socket
         |> assign(draft: input, input_error?: true)
         |> put_flash(:error, gettext("Choose a valid way to interact before sending."))}

      true ->
        submit_turn(socket, input, Map.get(params, "idempotency_key", ""), intent)
    end
  end

  @impl true
  def handle_event("retry-turn", %{"turn_id" => turn_id}, socket) do
    latest = Play.public_current_turn(socket.assigns.session.campaign_id)
    usage_status = current_plan_usage_status()

    cond do
      usage_status == :paused ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "ChatGPT plan requests are paused. Check Usage and resume before retrying this turn."
           )
         )}

      usage_status == :unavailable ->
        {:noreply,
         socket
         |> refresh_game()
         |> put_flash(
           :error,
           gettext(
             "Account usage status cannot be checked right now. Requests are paused until it can be checked."
           )
         )}

      same_turn?(latest, turn_id) and latest.status == :failed and
        latest.session_id == socket.assigns.session.id and retryable?(latest) ->
        if socket.assigns.worker_turn_id == latest.id do
          {:noreply, maybe_schedule_poll(socket)}
        else
          socket =
            socket
            |> start_resolution(latest.id)
            |> maybe_schedule_poll()

          {:noreply, socket}
        end

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
  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    if socket.assigns.worker_monitor_ref == ref do
      if is_integer(socket.assigns.worker_attempt) do
        _ =
          Play.abandon_resolution_attempt(
            socket.assigns.worker_turn_id,
            socket.assigns.worker_attempt
          )
      end

      socket = socket |> clear_resolution_worker() |> refresh_game()
      socket = maybe_start_resolution(socket, socket.assigns.current_turn)

      {:noreply, maybe_schedule_poll(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:turn_resolution_claimed, turn_id, worker_tag, attempt}, socket) do
    if socket.assigns.worker_turn_id == turn_id and socket.assigns.worker_tag == worker_tag do
      {:noreply, assign(socket, worker_attempt: attempt)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:turn_first_output, turn_id, worker_tag}, socket) do
    current_turn = socket.assigns.current_turn

    if socket.assigns.worker_turn_id == turn_id and socket.assigns.worker_tag == worker_tag and
         same_turn?(current_turn, to_string(turn_id)) and current_turn.status in @turn_in_progress do
      {:noreply,
       assign(socket,
         turn_first_output_id: turn_id,
         turn_announcement:
           first_output_announcement(current_turn, socket.assigns.current_turn_roll)
       )}
    else
      {:noreply, socket}
    end
  end

  attr :world, :map, required: true

  defp scene_weather_icon(assigns) do
    assigns = assign(assigns, :cue, scene_weather_cue(assigns.world))

    ~H"""
    <span
      id="scene-weather-cue"
      class="scene-weather-cue"
      data-scene-cue={@cue.name}
      data-time-mode={@cue.time}
      data-weather-mode={@cue.weather}
      aria-hidden="true"
    >
      <svg viewBox="0 0 40 36" fill="none" xmlns="http://www.w3.org/2000/svg">
        <g
          :if={@cue.time == :day}
          data-sky-icon="sun"
          stroke="currentColor"
          stroke-linecap="round"
        >
          <circle cx="14" cy="13" r="5.3" fill="currentColor" fill-opacity=".2" stroke-width="1.6" />
          <path
            d="M14 3.2v2.3m0 15v2.3m10-9.8h-2.3m-15.4 0H4m17.1-7.1-1.7 1.7M8.6 18.1l-1.7 1.7m14.2 0-1.7-1.7M8.6 8.5 6.9 6.8"
            stroke-width="1.5"
          />
        </g>
        <g
          :if={@cue.time == :night}
          data-sky-icon="moon"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path
            d="M26.6 3.6c-5.4 1.1-8.8 6.7-7.4 12.1 1.5 5.8 7.4 8.5 12.2 6.1-1.5 3.3-4.9 5.5-8.9 5.1-5.2-.4-9.2-4.9-8.7-10.2.5-6.8 6.4-11.4 12.8-13.1Z"
            fill="currentColor"
            fill-opacity=".19"
            stroke-width="1.6"
          />
          <path
            :if={!@cue.cloud?}
            d="m8 8 .5 1.4L10 10l-1.5.5L8 12l-.5-1.5L6 10l1.5-.6L8 8Zm24 2 .4 1.1 1.1.4-1.1.4L32 13l-.4-1.1-1.1-.4 1.1-.4L32 10Z"
            stroke-width="1.2"
          />
        </g>
        <path
          :if={@cue.cloud?}
          data-weather-icon="cloud"
          d="M9.2 26.9c-2.3 0-3.8-1.5-3.8-3.5 0-1.8 1.3-3.2 3.1-3.5.3-3 2.7-5.2 5.8-5.2 2.2 0 4.2 1.2 5.1 3.2 2.8-.8 5.8 1.2 5.8 4.1 2.6-.2 4.3 1.2 4.3 3.1 0 1.2-.9 1.9-2.5 1.9H9.2Z"
          fill="#f5edda"
          fill-opacity=".94"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        <g :if={@cue.mist?} data-weather-icon="mist" stroke="#8da0a8" stroke-linecap="round">
          <path
            d="M6.5 30.1c3.2-1.2 5.6.8 8.8-.1 2.7-.8 4.4-.9 7.1-.1m2.3-.1c2.3-.8 4.9-.8 7.5.1"
            stroke-width="1.45"
          />
          <path d="M9 33c2.8-.7 4.5.6 7.4.1m3-.1c3.4-.8 6.1.6 9.5-.1" stroke-width="1.15" />
        </g>
        <g :if={@cue.rain?} data-weather-icon="rain" stroke="#66849a" stroke-linecap="round">
          <path d="m12 29.4-1.2 2.2m8-2.2-1.2 2.2m8-2.2-1.2 2.2" stroke-width="1.5" />
        </g>
        <g :if={@cue.snow?} data-weather-icon="snow" stroke="#7798a6" stroke-linecap="round">
          <path
            d="M11 30v4m-1.7-3 3.4 2m0-2-3.4 2m11.2-3v4m-1.7-3 3.4 2m0-2-3.4 2m10.2-3v4m-1.7-3 3.4 2m0-2-3.4 2"
            stroke-width="1.1"
          />
        </g>
        <g
          :if={@cue.time == :unknown}
          data-sky-icon="neutral"
          stroke="currentColor"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="20" cy="18" r="11" stroke-width="1.45" />
          <path
            d="M12 21c2.2-2 4.6 2 7.1 0 2.5-2 4.8 1.8 8.9-.3M20 7v2m0 18v2m-11-11H7m26 0h-2"
            stroke-width="1.35"
          />
        </g>
      </svg>
    </span>
    """
  end

  attr :event, :map, required: true
  attr :earlier_session?, :boolean, required: true
  attr :show_game_time?, :boolean, required: true
  attr :characters_by_id, :map, required: true
  attr :projection, :map, required: true

  defp timeline_entry(assigns) do
    ~H"""
    <li
      id={"event-#{@event.sequence}"}
      data-event-sequence={@event.sequence}
      data-event-type={@event.event_type}
      data-turn-id={@event.turn_id}
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
        @event.event_type in [:player_action, :player_question, :time_passage] &&
          "story-entry-player",
        @event.event_type == :npc_dialogue && "story-entry-dialogue",
        @event.event_type == :remote_message && "story-entry-message",
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
              :player_action ->
                gettext("You")

              :player_question ->
                gettext("Question for the GM")

              :time_passage ->
                gettext("You")

              :gm_narration ->
                gettext("Game master")

              :npc_dialogue ->
                speaker_name(@characters_by_id, @event.speaker_id)

              :remote_message ->
                gettext("Message from %{name}",
                  name: speaker_name(@characters_by_id, @event.speaker_id)
                )

              :character_activity ->
                speaker_name(@characters_by_id, @event.speaker_id)

              :roll_request ->
                gettext("Roll requested")

              :player_roll ->
                gettext("D20 roll")

              :state_change ->
                state_change_label(@event, @characters_by_id)
            end}
          </h3>
          <p
            :if={@show_game_time? and game_time_label(@event.game_time)}
            class="game-time-label text-[11px] text-stone-400"
          >
            <span class="sr-only">{gettext("Game time")}: </span>
            {game_time_label(@event.game_time)}
          </p>
        </div>

        <p
          :if={
            @event.event_type in [
              :player_action,
              :player_question,
              :time_passage,
              :gm_narration,
              :npc_dialogue,
              :remote_message,
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
          :if={@event.event_type == :state_change && continuity_change_values(@event) != []}
          class="mt-2 space-y-2 text-sm text-stone-700"
        >
          <li
            :for={change <- continuity_change_values(@event)}
            class="rounded-lg border border-violet-200/70 bg-violet-50/60 px-3 py-2"
          >
            <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
              <h4 class="font-semibold text-stone-900">{change["entry"]["title"]}</h4>
              <span class="text-xs font-medium text-violet-900">
                {continuity_status_label(change)}
              </span>
            </div>
            <p class="mt-1 whitespace-pre-wrap leading-6 text-stone-700">
              {change["entry"]["details"]}
            </p>
          </li>
        </ul>
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

  attr :change, :map, required: true

  defp panel_change_receipt(assigns) do
    ~H"""
    <details class="mt-1 text-left text-xs font-normal">
      <summary class="cursor-pointer text-amber-800 underline decoration-amber-700/40 underline-offset-2">
        {gettext("Last changed")}
      </summary>
      <div class="mt-2 space-y-1 rounded-lg border border-amber-100 bg-amber-50/60 p-2">
        <p class="font-medium text-stone-800">{panel_change_summary(@change)}</p>
        <p class="leading-5 text-stone-600">
          {gettext("Reason: %{reason}", reason: @change["reason"])}
        </p>
        <p :if={game_time_label(@change["game_time"])} class="text-stone-500">
          {game_time_label(@change["game_time"])}
        </p>
      </div>
    </details>
    """
  end

  attr :id, :string, required: true
  attr :change, :map, required: true

  defp canonical_change_receipt(assigns) do
    ~H"""
    <details id={@id} class="mt-1 text-left text-xs font-normal">
      <summary class="cursor-pointer text-amber-800 underline decoration-amber-700/40 underline-offset-2">
        {gettext("Last changed")}
      </summary>
      <div class="mt-2 space-y-1 rounded-lg border border-amber-100 bg-amber-50/60 p-2">
        <dl class="space-y-1">
          <div :for={{key, before, after_value} <- canonical_change_rows(@change)}>
            <dt :if={key != ""} class="font-medium text-stone-600">{world_label(key)}</dt>
            <dd class="whitespace-pre-wrap break-words text-stone-800">
              <span :if={!is_nil(before)}>{display_value(before)} → </span>{display_value(after_value)}
            </dd>
          </div>
        </dl>
        <p
          :if={is_binary(@change["reason"]) && String.trim(@change["reason"]) != ""}
          class="leading-5 text-stone-600"
        >
          {gettext("Reason: %{reason}", reason: @change["reason"])}
        </p>
        <p :if={game_time_label(@change["game_time"])} class="text-stone-500">
          {game_time_label(@change["game_time"])}
        </p>
      </div>
    </details>
    """
  end

  defp canonical_change_rows(%{"after" => after_value} = change) when is_map(after_value) do
    before_values = if is_map(change["before"]), do: change["before"], else: %{}

    after_value
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> {key, Map.get(before_values, key), value} end)
  end

  defp canonical_change_rows(%{"after" => after_value} = change),
    do: [{"", change["before"], after_value}]

  defp canonical_change_rows(_change), do: []

  attr :item, :map, required: true
  attr :change, :map, default: nil
  attr :characters_by_id, :map, required: true
  attr :playable, :boolean, required: true
  attr :turn_blocked, :boolean, required: true
  attr :can_correct, :boolean, default: false

  defp inventory_item(assigns) do
    ~H"""
    <li
      id={"inventory-item-#{@item["id"]}"}
      data-panel-watch={"inventory-#{@item["id"]}"}
      class="rounded-xl border border-stone-100 bg-stone-50 px-3 py-2"
    >
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <h3 class="truncate text-sm font-semibold text-stone-900">{@item["name"]}</h3>
          <p :if={@item["category"]} class="truncate text-xs text-stone-500">
            {@item["category"]}
          </p>
        </div>
        <span class="shrink-0 rounded-full bg-white px-2 py-1 text-xs font-semibold text-stone-700">
          {@item["quantity"]}{if @item["unit"], do: " " <> @item["unit"], else: ""}
        </span>
      </div>
      <details :if={inventory_item_has_details?(@item)} class="mt-1 text-xs text-stone-500">
        <summary class="cursor-pointer rounded font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 focus-visible:ring-offset-2">
          {gettext("Item details")}
        </summary>
        <div class="mt-2 space-y-1.5">
          <p :if={@item["owner_id"] not in ["player", "party"]}>
            {gettext("Carried by %{name}",
              name: speaker_name(@characters_by_id, @item["owner_id"])
            )}
          </p>
          <p :if={@item["owner_id"] == "party"}>{gettext("Stored with the party")}</p>
          <p :if={@item["description"]} class="whitespace-pre-wrap text-sm leading-6 text-stone-700">
            {@item["description"]}
          </p>
          <dl :if={@item["properties"] not in [nil, %{}]} class="space-y-1.5">
            <div
              :for={{label, value} <- inventory_property_rows(@item["properties"])}
              class="grid grid-cols-[minmax(0,auto)_1fr] gap-x-3"
            >
              <dt class="font-medium text-stone-600">{label}</dt>
              <dd class="min-w-0 whitespace-pre-wrap break-words text-stone-700">{value}</dd>
            </div>
          </dl>
        </div>
      </details>
      <details :if={@change} class="mt-1 text-xs font-normal">
        <summary class="cursor-pointer text-amber-800 underline decoration-amber-700/40 underline-offset-2">
          {gettext("Last changed")}
        </summary>
        <div class="mt-2 space-y-1 rounded-lg border border-amber-100 bg-amber-50/60 p-2">
          <p class="font-medium text-stone-800">
            {inventory_event_text(@change, @characters_by_id)}
          </p>
          <p :if={inventory_change_owner(@change, @characters_by_id)} class="text-stone-600">
            {inventory_change_owner(@change, @characters_by_id)}
          </p>
          <dl
            :if={
              @change["type"] == "update" and is_map(@change["properties"]) and
                map_size(@change["properties"]) > 0
            }
            class="space-y-1"
          >
            <div
              :for={{label, value} <- inventory_property_rows(@change["properties"])}
              class="grid grid-cols-[minmax(0,auto)_1fr] gap-x-2"
            >
              <dt class="font-medium text-stone-600">{label}</dt>
              <dd class="min-w-0 break-words text-stone-700">{value}</dd>
            </div>
          </dl>
          <p class="leading-5 text-stone-600">
            {gettext("Reason: %{reason}", reason: @change["reason"])}
          </p>
          <p :if={game_time_label(@change["game_time"])} class="text-stone-500">
            {game_time_label(@change["game_time"])}
          </p>
        </div>
      </details>
      <button
        :if={@item["owner_id"] in ["player", "party"] and @playable}
        type="button"
        phx-click={JS.push("use-in-action", value: %{item_id: @item["id"]})}
        aria-label={gettext("Use %{item} in your action", item: @item["name"])}
        disabled={@turn_blocked}
        class="mt-1 inline-flex min-h-8 items-center rounded-lg border border-amber-300 bg-white px-2.5 py-1 text-xs font-semibold text-amber-900 hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
      >{gettext("Use in action")}</button>
      <a
        :if={@can_correct}
        id={"correct-inventory-#{@item["id"]}"}
        href="#canon-corrections"
        phx-click="start-canon-correction"
        phx-value-kind="inventory"
        phx-value-target-id={@item["id"]}
        class="ml-2 inline-flex min-h-8 items-center rounded-lg px-2 py-1 text-xs font-semibold text-amber-800 underline decoration-amber-700/40 underline-offset-2 hover:bg-amber-50"
      >
        {gettext("Correct")}<span class="sr-only">: {@item["name"]}</span>
      </a>
    </li>
    """
  end

  defp submit_turn(socket, input, key, intent) do
    case Play.submit_turn(
           socket.assigns.session.campaign_id,
           socket.assigns.session.id,
           key,
           input,
           token_store: plan_usage_store(),
           intent: intent
         ) do
      {:ok, _turn} ->
        socket =
          socket
          |> assign(
            draft: "",
            interaction_mode: :action,
            input_error?: false,
            submission_key: Ecto.UUID.generate()
          )
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
         |> assign(draft: input)
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

    correction_options =
      if playable?(socket.assigns.session) do
        case CanonCorrections.options(campaign_id, socket.assigns.session.id) do
          {:ok, options} -> options
          _ -> nil
        end
      end

    correction_receipts = CanonCorrections.list_receipts(campaign_id)

    with {:ok, projection} <- Play.public_projection(campaign_id),
         {:ok, %{events: recent_events, has_earlier?: has_earlier?}} <-
           Play.public_story_timeline_page(campaign_id, limit: @timeline_page_size) do
      timeline = merge_timeline(socket.assigns.timeline, recent_events)

      timeline_has_earlier? =
        if socket.assigns.timeline_loaded_earlier?,
          do: socket.assigns.timeline_has_earlier?,
          else: has_earlier?

      session_id = socket.assigns.session.id

      current_turn =
        case Play.public_current_turn(campaign_id) do
          %{session_id: ^session_id} = turn -> turn
          _ -> nil
        end

      previous_turn = socket.assigns.current_turn
      current_turn_roll = player_roll_result(timeline, current_turn)
      usage_status = current_plan_usage_status()

      socket =
        assign(socket,
          projection: projection,
          correction_options: correction_options,
          correction_receipts: correction_receipts,
          player_character: Enum.find(projection.characters, &(&1.speaker_id == "player")),
          characters_by_id: Map.new(projection.characters, &{&1.speaker_id, &1}),
          timeline: timeline,
          current_situation: latest_public_narration(timeline),
          plan_usage_status: usage_status,
          plan_usage_paused?: usage_status == :paused,
          plan_usage_blocked?: usage_status != :available,
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
    question_turn_ids =
      events
      |> Enum.filter(&(&1.event_type == :player_question))
      |> Enum.map(& &1.turn_id)
      |> MapSet.new()

    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{event_type: :gm_narration, turn_id: turn_id, payload: %{"text" => text}}
      when is_binary(text) ->
        if String.trim(text) == "" or MapSet.member?(question_turn_ids, turn_id),
          do: nil,
          else: text

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

    {indexed_events, _previous_story_time} =
      socket.assigns.timeline
      |> Enum.with_index()
      |> Enum.map_reduce(%{session_id: nil, turn_id: nil, game_time: nil}, fn
        {event, index}, previous_story_time ->
          earlier_session? =
            event.session_id != socket.assigns.session.id and
              (index == 0 or previous_story_time.session_id != event.session_id)

          show_game_time? =
            not is_nil(game_time_label(event.game_time)) and
              (event.turn_id != previous_story_time.turn_id or
                 event.game_time != previous_story_time.game_time)

          current_story_time = %{
            session_id: event.session_id,
            turn_id: event.turn_id,
            game_time: event.game_time
          }

          {{event, earlier_session?, show_game_time?}, current_story_time}
      end)

    {history, live} =
      Enum.split_with(indexed_events, fn {event, _earlier_session?, _show_game_time?} ->
        is_nil(live_from_sequence) or event.sequence < live_from_sequence
      end)

    assign(socket,
      timeline_history: history,
      timeline_live: live
    )
  end

  defp maybe_start_resolution(socket, turn) do
    if connected?(socket) and not socket.assigns.plan_usage_blocked? and not is_nil(turn) and
         turn.session_id == socket.assigns.session.id and
         playable?(socket.assigns.session) do
      case turn.status do
        :pending ->
          start_resolution(socket, turn.id)

        :resolving ->
          if Play.resolution_lease_expired?(turn) do
            socket
            |> retire_resolution_worker(turn.id)
            |> start_resolution(turn.id)
          else
            socket
          end

        :failed ->
          retire_resolution_worker(socket, turn.id)

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp start_resolution(socket, turn_id) do
    if socket.assigns.worker_turn_id == turn_id do
      socket
    else
      owner = self()
      worker_tag = make_ref()
      provider = Application.get_env(:storyteller, :gm_provider, Storyteller.GM.OpenAI)

      case Task.start(fn ->
             Play.retry_turn(turn_id,
               provider: provider,
               token_store: plan_usage_store(),
               on_claim: fn claimed_turn_id, attempt ->
                 send(owner, {:turn_resolution_claimed, claimed_turn_id, worker_tag, attempt})
               end,
               on_first_output: fn ->
                 send(owner, {:turn_first_output, turn_id, worker_tag})
               end
             )
           end) do
        {:ok, pid} ->
          ref = Process.monitor(pid)

          socket =
            assign(socket,
              worker_turn_id: turn_id,
              worker_pid: pid,
              worker_monitor_ref: ref,
              worker_tag: worker_tag,
              worker_attempt: nil,
              turn_first_output_id: nil
            )

          if connected?(socket) and
               same_turn?(socket.assigns.current_turn, to_string(turn_id)) do
            assign(
              socket,
              turn_announcement:
                turn_announcement(
                  socket.assigns.current_turn,
                  socket.assigns.current_turn_roll,
                  turn_id,
                  socket.assigns.plan_usage_status
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

  defp retire_resolution_worker(socket, turn_id) do
    if socket.assigns.worker_turn_id == turn_id do
      if is_pid(socket.assigns.worker_pid) and Process.alive?(socket.assigns.worker_pid) do
        Process.exit(socket.assigns.worker_pid, :kill)
      end

      if is_reference(socket.assigns.worker_monitor_ref) do
        Process.demonitor(socket.assigns.worker_monitor_ref, [:flush])
      end

      clear_resolution_worker(socket)
    else
      socket
    end
  end

  defp clear_resolution_worker(socket) do
    assign(socket,
      worker_turn_id: nil,
      worker_pid: nil,
      worker_monitor_ref: nil,
      worker_tag: nil,
      worker_attempt: nil,
      turn_first_output_id: nil
    )
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

  defp default_correction_form do
    %{"kind" => "inventory", "action" => "add", "owner_id" => "player"}
  end

  defp correction_changes_allowed?(socket) do
    playable?(socket.assigns.session) and not is_nil(socket.assigns.correction_options) and
      not blocking_turn?(socket.assigns.current_turn)
  end

  defp correctable_resource?(key, options) when is_map(options) do
    Enum.any?(options[:resources] || [], &(&1.key == key))
  end

  defp correctable_resource?(_key, _options), do: false

  defp contextual_correction_form("inventory", target_id, options) do
    case Enum.find(options[:inventory] || [], &(&1.id == target_id)) do
      nil ->
        {:error, :not_found}

      _item ->
        form = %{"kind" => "inventory", "action" => "set", "target_id" => target_id}
        {:ok, maybe_fill_correction_default(form, %{}, options)}
    end
  end

  defp contextual_correction_form("resource", target_id, options) do
    case Enum.find(options[:resources] || [], &(&1.key == target_id)) do
      nil ->
        {:error, :not_found}

      _field ->
        form = %{"kind" => "resource", "target_id" => target_id}
        {:ok, maybe_fill_correction_default(form, %{}, options)}
    end
  end

  defp contextual_correction_form(_kind, _target_id, _options), do: {:error, :invalid_target}

  defp default_story_memory_form do
    %{"kind" => "fact", "title" => "", "details" => "", "reason" => ""}
  end

  defp memory_changes_allowed?(socket) do
    playable?(socket.assigns.session) and not is_nil(socket.assigns.correction_options) and
      not blocking_turn?(socket.assigns.current_turn)
  end

  defp maybe_fill_correction_default(params, previous, options) do
    inventory_item_changed? =
      params["kind"] == "inventory" and params["action"] in ["set", "edit"] and
        not is_nil(params["target_id"]) and
        (params["kind"] != previous["kind"] or params["target_id"] != previous["target_id"] or
           params["action"] != previous["action"])

    resource_changed? =
      params["kind"] == "resource" and not is_nil(params["target_id"]) and
        (params["kind"] != previous["kind"] or params["target_id"] != previous["target_id"])

    world_label_changed? =
      params["kind"] == "world" and not is_nil(params["target_id"]) and
        (params["kind"] != previous["kind"] or params["target_id"] != previous["target_id"])

    cond do
      inventory_item_changed? ->
        case Enum.find(options[:inventory] || [], &(&1.id == params["target_id"])) do
          nil ->
            params

          item ->
            params
            |> Map.put("quantity", to_string(item.quantity))
            |> Map.put("name", item.name)
            |> Map.put("unit", item.unit || "")
            |> Map.put("category", item.category || "")
            |> Map.put("description", item.description || "")
            |> Map.put("owner_id", item.owner_id || "")
            |> Map.put("properties", Jason.encode!(item.properties, pretty: true))
        end

      resource_changed? ->
        case Enum.find(options[:resources] || [], &(&1.key == params["target_id"])) do
          nil -> params
          field -> Map.put(params, "value", correction_value(field.value))
        end

      world_label_changed? ->
        case Enum.find(options[:world_labels] || [], &(&1.key == params["target_id"])) do
          nil -> params
          field -> Map.put(params, "value", correction_value(field.value))
        end

      true ->
        params
    end
  end

  defp correction_value(nil), do: ""
  defp correction_value(value) when is_binary(value), do: value
  defp correction_value(value) when is_number(value), do: to_string(value)
  defp correction_value(value), do: inspect(value)

  defp correction_error_message(:stale_correction),
    do:
      gettext(
        "The campaign changed while this correction was open. Review the current state and try again."
      )

  defp correction_error_message(:turn_in_progress),
    do:
      gettext("Wait for the current game master turn to finish before correcting campaign state.")

  defp correction_error_message(:invalid_reason),
    do: gettext("Add a short reason for this correction.")

  defp correction_error_message(:no_change),
    do: gettext("That detail already has this value. Choose a different correction.")

  defp correction_error_message(:not_found),
    do: gettext("That tracked detail is no longer available to correct.")

  defp correction_error_message(:invalid_value),
    do: gettext("Check the correction values and try again.")

  defp correction_error_message(_reason),
    do: gettext("The correction could not be saved. Refresh and try again.")

  defp story_memory_error_message(:stale_correction),
    do:
      gettext(
        "The campaign changed while this note was open. Review the current details and try again."
      )

  defp story_memory_error_message(:turn_in_progress),
    do: gettext("Wait for the game master to finish this turn before changing campaign memory.")

  defp story_memory_error_message(:invalid_reason),
    do: gettext("Add a short reason for keeping or changing this detail.")

  defp story_memory_error_message(:invalid_memory),
    do: gettext("Add a title and details within the shown length limits.")

  defp story_memory_error_message(:memory_limit_reached),
    do: gettext("Your lasting-note space is full. Edit or remove a note before adding another.")

  defp story_memory_error_message(:no_change),
    do: gettext("This note already has those details. Change something before saving.")

  defp story_memory_error_message(:not_found),
    do: gettext("This public note is no longer available to change.")

  defp story_memory_error_message(_reason),
    do: gettext("The campaign memory could not be saved. Refresh and try again.")

  defp correction_kind_label("inventory"), do: gettext("Inventory")
  defp correction_kind_label("resource"), do: gettext("Tracked resource")
  defp correction_kind_label("location"), do: gettext("Character location")
  defp correction_kind_label("world"), do: gettext("World state")
  defp correction_kind_label("memory"), do: gettext("Campaign memory")
  defp correction_kind_label(kind), do: kind

  defp world_correction_label("date"), do: gettext("Date")
  defp world_correction_label("time"), do: gettext("Time")
  defp world_correction_label("weather"), do: gettext("Weather")
  defp world_correction_label(key), do: key

  defp story_memory_kind_label(:fact), do: gettext("Fact")
  defp story_memory_kind_label(:relationship), do: gettext("Relationship")
  defp story_memory_kind_label(:commitment), do: gettext("Promise or commitment")

  defp correction_receipt_value("inventory", %{name: name, quantity: quantity, unit: unit}) do
    inventory_correction_label(%{name: name, quantity: quantity, unit: unit})
  end

  defp correction_receipt_value("inventory", _item), do: gettext("Not recorded")

  defp correction_receipt_value("resource", %{value: value, unit: unit}) do
    value = correction_value(value)
    if unit, do: "#{value} #{unit}", else: value
  end

  defp correction_receipt_value("location", %{place_name: name}) when is_binary(name), do: name
  defp correction_receipt_value("location", _place), do: gettext("Unrecorded location")

  defp correction_receipt_value("world", %{value: value}), do: correction_value(value)
  defp correction_receipt_value("world", _field), do: gettext("Not recorded")

  defp correction_receipt_value("memory", %{title: title, details: details, status: status}) do
    gettext("%{title}: %{details} (%{status})",
      title: title,
      details: details,
      status: story_memory_status_label(status)
    )
  end

  defp correction_receipt_value("memory", _entry), do: gettext("Not recorded")
  defp correction_receipt_value(_kind, _snapshot), do: gettext("Not recorded")

  defp story_memory_status_label("active"), do: gettext("Active")
  defp story_memory_status_label("retracted"), do: gettext("Removed")
  defp story_memory_status_label(status), do: status

  defp correction_owner_label(%{id: "party"}), do: gettext("Party")
  defp correction_owner_label(%{name: name}), do: name

  defp inventory_correction_label(item) do
    quantity = to_string(item.quantity)
    unit = if item.unit, do: " #{item.unit}", else: ""
    "#{item.name} · #{quantity}#{unit}"
  end

  defp resource_correction_label(field) do
    unit = if field.unit, do: " (#{field.unit})", else: ""
    "#{field.panel} · #{field.label}#{unit}"
  end

  defp correction_inputmode(target_id, resources) do
    case Enum.find(resources, &(&1.key == target_id)) do
      %{type: type} when type in [:quantity, :money] -> "decimal"
      _ -> "text"
    end
  end

  defp blocking_turn?(%{intent: :opening_scene}), do: true
  defp blocking_turn?(%{status: status}), do: status in @turn_blocking
  defp blocking_turn?(_turn), do: false

  defp opening_scene?(%{intent: :opening_scene}), do: true
  defp opening_scene?(_turn), do: false

  defp opening_scene_pending?(%{intent: :opening_scene, status: status})
       when status in [:pending, :resolving],
       do: true

  defp opening_scene_pending?(_turn), do: false

  defp turn_blocks_composer?(turn), do: blocking_turn?(turn)

  defp interaction_mode(mode) when mode in [:action, :question, :time_passage], do: mode
  defp interaction_mode("action"), do: :action
  defp interaction_mode("question"), do: :question
  defp interaction_mode("time_passage"), do: :time_passage
  defp interaction_mode(_mode), do: nil

  defp composer_label(:question), do: gettext("What would you like to ask the GM?")
  defp composer_label(:time_passage), do: gettext("How much time should pass?")
  defp composer_label(_mode), do: gettext("What do you do or say?")

  defp composer_placeholder(:question),
    do: gettext("Ask a direct question about the world or your options…")

  defp composer_placeholder(:time_passage),
    do: gettext("Say how long time should pass, or what you are waiting for…")

  defp composer_placeholder(_mode),
    do: gettext("Describe your character's action or words…")

  defp composer_submit_label(:question), do: gettext("Ask the GM")
  defp composer_submit_label(:time_passage), do: gettext("Let time pass")
  defp composer_submit_label(_mode), do: gettext("Send turn")

  defp composer_guidance(:question),
    do:
      gettext("Questions go directly to the GM; they are not things your character says or does.")

  defp composer_guidance(:time_passage),
    do: gettext("The GM advances the requested interval and pauses when your decision is needed.")

  defp composer_guidance(_mode),
    do: gettext("Actions and dialogue become part of your saved campaign history.")

  defp contextual_nudges(:question, _projection) do
    [
      %{
        id: "visible",
        label: gettext("What can I see?"),
        text: gettext("What can I see from here that I haven't noticed yet?")
      },
      %{
        id: "choices",
        label: gettext("What choices do I notice?"),
        text: gettext("What meaningful choices are available to me right now?")
      }
    ]
  end

  defp contextual_nudges(:time_passage, projection) do
    [
      %{
        id: "wait-here",
        label: gettext("Wait here"),
        text: time_passage_wait_text(projection)
      },
      %{
        id: "quiet-hour",
        label: gettext("Pass a quiet hour"),
        text: gettext("Let a quiet hour pass, stopping if a meaningful choice comes up.")
      },
      %{
        id: "few-days",
        label: gettext("Pass a few days"),
        text:
          gettext("Let a few days pass, stopping at the next meaningful decision I need to make.")
      },
      %{
        id: "until-morning",
        label: gettext("Advance to morning"),
        text: gettext("Advance to the next morning, stopping if I need to make a decision.")
      }
    ]
  end

  defp contextual_nudges(_mode, _projection) do
    [
      %{
        id: "look-around",
        label: gettext("Look around"),
        text: gettext("I scan the scene for anything new or out of place.")
      },
      %{
        id: "talk-nearby",
        label: gettext("Talk to someone nearby"),
        text: gettext("I ask someone nearby what they know.")
      }
    ]
  end

  defp time_passage_wait_text(%{world: world}) when is_map(world) do
    case Map.get(world, "location") do
      location when is_binary(location) and location != "" ->
        gettext(
          "Wait at %{location} for the next development. Advance time only until a decision is needed.",
          location: location
        )

      _ ->
        gettext(
          "Wait here for the next development. Advance time only until a decision is needed."
        )
    end
  end

  defp time_passage_wait_text(_projection),
    do:
      gettext("Wait here for the next development. Advance time only until a decision is needed.")

  defp same_turn?(%{id: id}, turn_id), do: to_string(id) == turn_id
  defp same_turn?(_turn, _turn_id), do: false

  defp retryable?(turn), do: turn.failure_code not in ["session_closed", "campaign_archived"]

  defp plan_usage_store do
    Application.get_env(:storyteller, :plan_usage_token_store, Storyteller.Auth.TokenStore)
  end

  defp current_plan_usage_status do
    Play.plan_usage_status(token_store: plan_usage_store())
  end

  defp announce_turn_status(socket, previous_turn, current_turn, current_turn_roll) do
    cond do
      not connected?(socket) ->
        socket

      is_nil(current_turn) and match?(%{intent: :opening_scene}, previous_turn) ->
        assign(socket, turn_announcement: "")

      is_nil(current_turn) and not is_nil(previous_turn) ->
        assign(socket, turn_announcement: gettext("Your turn is complete."))

      is_nil(current_turn) ->
        socket

      true ->
        announcement =
          if current_turn.status in @turn_in_progress and
               socket.assigns.turn_first_output_id == current_turn.id do
            first_output_announcement(current_turn, current_turn_roll)
          else
            turn_announcement(
              current_turn,
              current_turn_roll,
              socket.assigns.worker_turn_id,
              socket.assigns.plan_usage_status
            )
          end

        assign(socket, turn_announcement: announcement)
    end
  end

  defp turn_announcement(%{status: status} = turn, result, worker_turn_id, _plan_usage_status)
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
         _worker_turn_id,
         _plan_usage_status
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

  defp turn_announcement(%{status: :failed} = turn, result, worker_turn_id, plan_usage_status) do
    prefix =
      cond do
        worker_turn_id == turn.id ->
          gettext("Retrying…")

        turn.failure_code == "usage_limit" and plan_usage_status == :paused ->
          gettext("Your turn is saved")

        plan_usage_status == :unavailable ->
          gettext("The account usage status could not be checked. Your turn remains saved.")

        true ->
          gettext("This turn needs attention") <>
            ". " <>
            failure_message(turn, plan_usage_status)
      end

    append_roll_result(prefix, result)
  end

  defp turn_announcement(_turn, _result, _worker_turn_id, _plan_usage_status), do: ""

  defp responding_announcement(%{resolution_phase: :after_roll}, result) when not is_nil(result),
    do: append_roll_result(gettext("The game master is responding"), result)

  defp responding_announcement(_turn, _result), do: gettext("The game master is responding")

  defp first_output_announcement(%{intent: :opening_scene}, _result),
    do: gettext("The opening scene is taking shape")

  defp first_output_announcement(%{resolution_phase: :after_roll}, result)
       when not is_nil(result),
       do: append_roll_result(gettext("The game master is shaping the scene"), result)

  defp first_output_announcement(_turn, _result),
    do: gettext("The game master is shaping the scene")

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

  defp pending_action_preview?(%{intent: :opening_scene}, _timeline), do: false

  defp pending_action_preview?(%{status: status, id: turn_id, intent: intent}, timeline)
       when status in [:pending, :resolving, :awaiting_roll, :failed] do
    event_type = pending_input_event_type(intent)

    not Enum.any?(timeline, fn event ->
      event.turn_id == turn_id and event.event_type == event_type
    end)
  end

  defp pending_action_preview?(_current_turn, _timeline), do: false

  defp pending_input_event_type(:action), do: :player_action
  defp pending_input_event_type(:question), do: :player_question
  defp pending_input_event_type(:time_passage), do: :time_passage
  defp pending_input_event_type(_intent), do: nil

  defp pending_input_label(:question), do: gettext("Question for the GM")
  defp pending_input_label(:time_passage), do: gettext("Time passage request")
  defp pending_input_label(_intent), do: gettext("Saved player action")

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

  defp panel_field_value(%{value: value}) when is_nil(value) or value == "",
    do: gettext("Not recorded")

  defp panel_field_value(%{value: value}), do: display_value(value)

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value) when is_number(value), do: to_string(value)

  defp display_value(value) when is_boolean(value),
    do: if(value, do: gettext("Yes"), else: gettext("No"))

  defp display_value(value), do: Jason.encode!(value)

  defp inventory_item_has_details?(item) do
    item["description"] not in [nil, ""] or item["properties"] not in [nil, %{}] or
      item["owner_id"] not in ["player", "party"]
  end

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
      is_list(Map.get(event.payload, "continuity_changes")) ->
        gettext("Campaign memory")

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

  defp continuity_change_values(%{payload: %{"continuity_changes" => changes}})
       when is_list(changes),
       do: changes

  defp continuity_change_values(_event), do: []

  defp continuity_status_label(%{"entry" => %{"status" => "active"}}),
    do: gettext("Remembered")

  defp continuity_status_label(%{"entry" => %{"status" => "resolved"}}),
    do: gettext("Resolved")

  defp continuity_status_label(%{"entry" => %{"status" => "retracted"}}),
    do: gettext("Retracted")

  defp continuity_status_label(_change), do: gettext("Updated")

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

  defp inventory_change_owner(
         %{"type" => "add", "item" => %{"owner_id" => "party"}},
         _characters
       ),
       do: gettext("Stored with the party")

  defp inventory_change_owner(
         %{"type" => "add", "item" => %{"owner_id" => owner_id}},
         characters
       )
       when is_binary(owner_id) and owner_id != "player",
       do: gettext("Carried by %{name}", name: speaker_name(characters, owner_id))

  defp inventory_change_owner(_change, _characters), do: nil

  defp quantity_label(quantity, nil), do: to_string(quantity)
  defp quantity_label(quantity, unit), do: "#{quantity} #{unit}"

  defp inventory_owner_name("party", _characters), do: gettext("the party stash")
  defp inventory_owner_name(owner_id, characters), do: speaker_name(characters, owner_id)

  defp world_display(world, keys) do
    case world_value(world, keys) do
      nil -> gettext("Not recorded")
      value -> display_value(value)
    end
  end

  defp elapsed_clock_text(1), do: gettext("1 minute elapsed")
  defp elapsed_clock_text(minutes), do: gettext("%{minutes} minutes elapsed", minutes: minutes)

  defp world_value(world, keys) when is_map(world) do
    case Enum.find(keys, fn key ->
           Map.has_key?(world, key) and not is_nil(Map.get(world, key)) and
             Map.get(world, key) != ""
         end) do
      nil -> nil
      key -> Map.get(world, key)
    end
  end

  defp world_value(_world, _keys), do: nil

  defp player_world_location(%{current_place: %{name: name}}, _world)
       when is_binary(name) and name != "",
       do: name

  defp player_world_location(_player_character, world),
    do: world_display(world, ["location", "current_location"])

  defp scene_weather_cue(world) when is_map(world) do
    time_text = world_value(world, ["time", "current_time", "time_of_day", "world_time"])
    weather_text = world_value(world, ["weather", "conditions"])
    time_text = scene_cue_text(time_text)
    weather_text = scene_cue_text(weather_text)
    time_mode = scene_time_mode(time_text)

    mist? = contains_scene_keyword?(weather_text, @mist_weather_words)
    rain? = contains_scene_keyword?(weather_text, @rain_weather_words)
    snow? = contains_scene_keyword?(weather_text, @snow_weather_words)

    cloud? =
      contains_scene_keyword?(weather_text, @cloud_weather_words) or mist? or rain? or snow?

    clear? = contains_scene_keyword?(weather_text, @clear_weather_words)
    weather_known? = cloud? or clear?

    weather_mode =
      cond do
        mist? -> :mist
        rain? -> :rain
        snow? -> :snow
        cloud? -> :cloud
        clear? -> :clear
        true -> :unknown
      end

    weather_mode = if weather_known?, do: weather_mode, else: :unknown

    name =
      if time_mode == :unknown and weather_mode == :unknown,
        do: "neutral",
        else: "#{time_mode}-#{weather_mode}"

    %{
      name: name,
      time: time_mode,
      weather: weather_mode,
      cloud?: cloud?,
      mist?: mist?,
      rain?: rain?,
      snow?: snow?
    }
  end

  defp scene_weather_cue(_world),
    do: %{
      name: "neutral",
      time: :unknown,
      weather: :unknown,
      cloud?: false,
      mist?: false,
      rain?: false,
      snow?: false
    }

  defp scene_time_mode(text) do
    cond do
      contains_scene_keyword?(text, @night_time_words) ->
        :night

      hour = scene_clock_hour(text) ->
        if hour <= 5 or hour >= 19, do: :night, else: :day

      contains_scene_keyword?(text, @day_time_words) ->
        :day

      true ->
        :unknown
    end
  end

  defp scene_clock_hour(text) do
    case Regex.run(~r/(?:^|\s)(1[0-2]|0?[1-9])(?::[0-5]\d)?\s*(am|pm)\b/u, text) do
      [_, hour, meridiem] ->
        hour = String.to_integer(hour)

        case {hour, meridiem} do
          {12, "am"} -> 0
          {hour, "pm"} when hour < 12 -> hour + 12
          {hour, _meridiem} -> hour
        end

      _ ->
        case Regex.run(~r/(?:^|\s)([01]?\d|2[0-3])(?:\s*h|:[0-5]\d)/u, text) do
          [_, hour] -> String.to_integer(hour)
          _ -> nil
        end
    end
  end

  defp scene_cue_text(value) when is_binary(value) do
    value
    |> String.slice(0, 300)
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end

  defp scene_cue_text(_value), do: ""

  defp contains_scene_keyword?(text, keywords) do
    words = String.split(text, ~r/[^\p{L}\p{N}]+/u, trim: true)
    Enum.any?(keywords, &(&1 in words))
  end

  defp player_character_description(%{visible_facts: facts}) when is_map(facts),
    do: Map.get(facts, "description")

  defp player_character_description(_character), do: nil

  defp player_character_profile_summary(character),
    do: character |> player_character_profile_details() |> Enum.take(3)

  defp player_character_additional_details(character),
    do: character |> player_character_profile_details() |> Enum.drop(3)

  defp player_character_profile_details(%{visible_facts: facts}) when is_map(facts) do
    facts
    |> Enum.reject(fn {key, _value} -> to_string(key) == "description" end)
    |> Enum.sort_by(fn {key, _value} -> String.downcase(to_string(key)) end)
  end

  defp player_character_profile_details(_character), do: []

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
    do:
      gettext(
        "ChatGPT could not verify this account's permission for Storyteller. Reconnect the account, confirm plan usage is enabled, then retry this turn."
      )

  defp failure_message("authorization_configuration"),
    do:
      gettext(
        "ChatGPT could not authorize Storyteller to use this account's plan. Check the selected account and workspace, then verify Storyteller's client and plan-usage grant configuration before retrying."
      )

  defp failure_message("account_ineligible"),
    do: gettext("The connected account is not eligible to continue this turn.")

  defp failure_message("usage_limit"),
    do: gettext("ChatGPT reported an account usage limit before the GM could respond.")

  defp failure_message("usage_unavailable"),
    do: gettext("The connected account's usage could not be confirmed.")

  defp failure_message("model_unavailable"),
    do: gettext("No available model could resolve this turn.")

  defp failure_message("context_budget_exceeded"),
    do:
      gettext(
        "Storyteller could not fit the required campaign details into its local GM request-size limit. Your action is saved, and the request was not sent. Shorten unusually long campaign instructions or notes, then retry this turn."
      )

  defp failure_message("timeout"),
    do: gettext("The game master took too long to answer. Your turn is saved.")

  defp failure_message(_),
    do: gettext("The game master could not resolve this turn. Your action is saved.")

  defp failure_message("usage_limit", status) when status in [:paused, true],
    do:
      gettext(
        "ChatGPT reported an account usage limit. The GM cannot respond until account usage is available."
      )

  defp failure_message("usage_limit", :unavailable),
    do: gettext("The account usage status could not be checked. Your turn remains saved.")

  defp failure_message("usage_limit", status) when status in [:available, false],
    do: gettext("ChatGPT reported an account usage limit before the GM could respond.")

  defp failure_message(
         %{failure_code: "invalid_response", failure_stage: stage},
         _plan_usage_paused?
       )
       when stage in [:response_decoding, :proposal_validation, :commit],
       do:
         gettext(
           "The GM's reply could not be used safely. No narration or campaign changes from it were saved; your action remains here to retry."
         )

  defp failure_message(%{failure_code: failure_code}, plan_usage_paused?),
    do: failure_message(failure_code, plan_usage_paused?)

  defp failure_message(failure_code, _plan_usage_paused?) when is_binary(failure_code),
    do: failure_message(failure_code)

  defp reconnect_needed?(code),
    do: code in ["reauth_required", "account_ineligible", "model_unavailable"]

  defp game_time_label(game_time) when is_map(game_time) do
    [Map.get(game_time, "date"), Map.get(game_time, "time")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&display_value/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, " · ")
    end
  end

  defp game_time_label(_game_time), do: nil
end
