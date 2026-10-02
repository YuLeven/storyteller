defmodule StorytellerWeb.CampaignLive.Edit do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Play
  alias Storyteller.Play.VoiceGuidance

  @editable_fields ~w(
    title premise setting tone narration_language player_character_name player_character
  )

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Campaigns.get_campaign(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That campaign could not be found."))
         |> push_navigate(to: ~p"/")}

      campaign ->
        {revision, elapsed_minutes} = campaign_clock(campaign.id)

        {:ok,
         assign(socket,
           page_title: gettext("Edit campaign"),
           campaign: campaign,
           state_revision: revision,
           authoring_revision: Campaigns.authoring_revision(campaign.id),
           form: to_form(Campaigns.change_campaign(campaign), as: :campaign),
           authoring_draft: %{},
           gm_characters: gm_characters_with_duty_time(campaign.id, elapsed_minutes),
           correction_reason: "",
           authoring_corrections: Campaigns.list_public_authoring_corrections(campaign.id),
           save_error: nil,
           save_succeeded: false
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"campaign" => attrs}, socket) do
    authoring_draft =
      merge_authoring_draft(authoring_draft(attrs), socket.assigns.authoring_draft)

    changeset =
      Campaigns.change_campaign(socket.assigns.campaign, Map.take(attrs, @editable_fields))

    {:noreply,
     assign(socket,
       form: to_form(%{changeset | action: :validate}, as: :campaign),
       authoring_draft: authoring_draft,
       correction_reason: Map.get(attrs, "correction_reason", socket.assigns.correction_reason),
       save_error: nil,
       save_succeeded: false
     )}
  end

  @impl true
  def handle_event("save", %{"campaign" => attrs}, socket) do
    attrs =
      attrs
      |> merge_authoring_draft(socket.assigns.authoring_draft)
      |> omit_unchanged_duty_inputs(socket.assigns.gm_characters)
      |> put_default_correction_reason(socket.assigns.correction_reason)

    socket = assign(socket, save_succeeded: false)

    case Campaigns.update_campaign_authoring(socket.assigns.campaign, attrs) do
      {:ok, campaign} ->
        {revision, elapsed_minutes} = campaign_clock(campaign.id)

        {:noreply,
         socket
         |> assign(
           campaign: Campaigns.get_campaign!(campaign.id),
           state_revision: revision,
           authoring_revision: Campaigns.authoring_revision(campaign.id),
           form: to_form(Campaigns.change_campaign(campaign), as: :campaign),
           authoring_draft: %{},
           gm_characters: gm_characters_with_duty_time(campaign.id, elapsed_minutes),
           correction_reason: "",
           authoring_corrections: Campaigns.list_public_authoring_corrections(campaign.id),
           save_error: nil,
           save_succeeded: true
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error: nil
         )}

      {:error, :invalid_voice_guidance} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               Campaigns.change_campaign(
                 socket.assigns.campaign,
                 Map.take(attrs, @editable_fields)
               ),
               as: :campaign
             ),
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "Voice notes must be %{field_limit} characters or fewer per field and %{total_limit} characters total.",
               field_limit: VoiceGuidance.max_field_length(),
               total_limit: VoiceGuidance.max_total_length()
             )
         )}

      {:error, :invalid_authoring_details} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               Campaigns.change_campaign(
                 socket.assigns.campaign,
                 Map.take(attrs, @editable_fields)
               ),
               as: :campaign
             ),
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "Character details must use the listed fields and stay within the length limits."
             )
         )}

      {:error, :invalid_active_duty} ->
        {:noreply,
         assign(socket,
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "An active duty needs a name up to 160 characters, a known current place, and a whole-number duration from 0 to 525600 minutes."
             )
         )}

      {:error, :stale_authoring_revision} ->
        {revision, elapsed_minutes} = campaign_clock(socket.assigns.campaign.id)
        campaign = Campaigns.get_campaign!(socket.assigns.campaign.id)

        {:noreply,
         assign(socket,
           campaign: campaign,
           state_revision: revision,
           authoring_revision: Campaigns.authoring_revision(campaign.id),
           form:
             to_form(
               Campaigns.change_campaign(campaign, Map.take(attrs, @editable_fields)),
               as: :campaign
             ),
           gm_characters: gm_characters_with_duty_time(campaign.id, elapsed_minutes),
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "The campaign changed while this setup was open. Your draft is still here; review the latest campaign state before saving again."
             )
         )}

      {:error, :authoring_turn_in_progress} ->
        {:noreply,
         assign(socket,
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "Wait for the game master to finish the turn before changing an active duty."
             )
         )}

      {:error, :invalid_correction_reason} ->
        {:noreply,
         assign(socket,
           form:
             to_form(
               Campaigns.change_campaign(
                 socket.assigns.campaign,
                 Map.take(attrs, @editable_fields)
               ),
               as: :campaign
             ),
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error: gettext("Add a reason for changing the campaign setup.")
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           authoring_draft: authoring_draft(attrs),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext("Campaign changes could not be saved. Review the fields and try again.")
         )}
    end
  end

  defp voice_value(character, field, draft) do
    draft_value(
      draft,
      "character_voice_guidance",
      character.speaker_id,
      field,
      Map.get(character.voice_guidance || %{}, field, "")
    )
  end

  defp voice_guidance_open?(character, draft) do
    draft_guidance =
      draft
      |> draft_attr("character_voice_guidance", %{})
      |> draft_attr(character.speaker_id, %{})

    nonempty_map?(character.voice_guidance) or nonempty_map?(draft_guidance)
  end

  defp voice_guidance_count(character, draft) do
    guidance =
      Map.new(VoiceGuidance.fields(), fn field ->
        {field, voice_value(character, field, draft)}
      end)

    VoiceGuidance.character_count(guidance)
  end

  defp voice_guidance_over_limit?(character, draft),
    do: voice_guidance_count(character, draft) > VoiceGuidance.max_total_length()

  defp nonempty_map?(map) when is_map(map), do: map_size(map) > 0
  defp nonempty_map?(_value), do: false

  defp fact_value(facts, key), do: Map.get(facts || %{}, key, "")

  defp draft_value(draft, category, speaker_id, field, default) do
    draft
    |> draft_attr(category, %{})
    |> draft_attr(speaker_id, %{})
    |> draft_attr(field, default)
  end

  defp draft_attr(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp draft_attr(_map, _key, default), do: default

  defp authoring_draft(attrs) do
    Map.take(attrs, ["gm_character_setup", "character_active_duties", "character_voice_guidance"])
    |> drop_unused_liveview_markers()
  end

  defp put_default_correction_reason(attrs, default) do
    reason = draft_attr(attrs, "correction_reason", default)

    reason =
      if is_binary(reason) and String.trim(reason) != "",
        do: reason,
        else: gettext("Campaign setup updated")

    Map.put(attrs, "correction_reason", reason)
  end

  defp merge_authoring_draft(attrs, draft) do
    Enum.reduce(
      [
        {"gm_character_setup", :gm_character_setup},
        {"character_active_duties", :character_active_duties},
        {"character_voice_guidance", :character_voice_guidance}
      ],
      attrs,
      fn {key, atom_key}, merged ->
        submitted =
          attrs
          |> draft_attr(key, %{})
          |> stringify_nested_keys()
          |> drop_unused_liveview_markers()

        validated =
          draft
          |> draft_attr(key, %{})
          |> stringify_nested_keys()
          |> drop_unused_liveview_markers()

        combined = deep_merge(validated, submitted)

        merged
        |> Map.delete(atom_key)
        |> Map.put(key, combined)
      end
    )
  end

  defp omit_unchanged_duty_inputs(attrs, characters) do
    submitted = attrs |> draft_attr("character_active_duties", %{}) |> stringify_nested_keys()
    characters_by_speaker = Map.new(characters, &{&1.speaker_id, &1})

    changed =
      Map.reject(submitted, fn {speaker_id, row} ->
        case Map.get(characters_by_speaker, speaker_id) do
          nil ->
            false

          character ->
            duty_input_matches_snapshot?(row, character)
        end
      end)

    attrs
    |> Map.delete(:character_active_duties)
    |> Map.put("character_active_duties", changed)
  end

  defp duty_input_matches_snapshot?(row, character) when is_map(row) do
    submitted_name = draft_attr(row, "duty_name", "")
    submitted_duration = draft_attr(row, "duty_duration_minutes", "")

    submitted_name == (character.duty_name || "") and
      to_string(submitted_duration || "") == to_string(character.duty_duration_minutes || "")
  end

  defp duty_input_matches_snapshot?(_row, _character), do: false

  defp stringify_nested_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested_keys(value)} end)
  end

  defp stringify_nested_keys(value), do: value

  # phx-change adds these markers for untouched nested controls. They are UI
  # metadata, not campaign authoring fields, and cannot reach the validators.
  defp drop_unused_liveview_markers(%_{} = struct), do: struct

  defp drop_unused_liveview_markers(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, drop_unused_liveview_markers(value)} end)
    |> Map.reject(fn {key, _value} -> unused_liveview_marker?(key) end)
  end

  defp drop_unused_liveview_markers(value), do: value

  defp unused_liveview_marker?(key) when is_atom(key),
    do: unused_liveview_marker?(Atom.to_string(key))

  defp unused_liveview_marker?(key) when is_binary(key),
    do: String.starts_with?(key, "_unused_")

  defp unused_liveview_marker?(_key), do: false

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right

  defp campaign_clock(campaign_id) do
    case Play.public_projection(campaign_id) do
      {:ok, projection} ->
        {projection.revision, projection.elapsed_world_clock.total_minutes}

      _ ->
        {0, 0}
    end
  end

  defp gm_characters_with_duty_time(campaign_id, elapsed_minutes) do
    Campaigns.list_gm_characters(campaign_id)
    |> Enum.map(fn character ->
      remaining =
        if is_integer(character.duty_release_at_world_minute),
          do: max(character.duty_release_at_world_minute - elapsed_minutes, 0),
          else: nil

      Map.put(character, :duty_duration_minutes, remaining)
    end)
  end

  def correction_category_label("campaign_setup"), do: gettext("Campaign setup")
  def correction_category_label("player_character"), do: gettext("Player character")
  def correction_category_label("character_details"), do: gettext("Character details")

  def correction_category_label(_category), do: gettext("Campaign setup")
end
