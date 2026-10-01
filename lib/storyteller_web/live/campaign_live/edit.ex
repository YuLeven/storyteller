defmodule StorytellerWeb.CampaignLive.Edit do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Play

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
        revision = campaign_revision(campaign.id)

        {:ok,
         assign(socket,
           page_title: gettext("Edit campaign"),
           campaign: campaign,
           state_revision: revision,
           form: to_form(Campaigns.change_campaign(campaign), as: :campaign),
           gm_characters: Campaigns.list_gm_characters(campaign.id),
           correction_reason: "",
           authoring_corrections: Campaigns.list_public_authoring_corrections(campaign.id),
           save_error: nil
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"campaign" => attrs}, socket) do
    changeset =
      Campaigns.change_campaign(socket.assigns.campaign, Map.take(attrs, @editable_fields))

    {:noreply,
     assign(socket,
       form: to_form(%{changeset | action: :validate}, as: :campaign),
       correction_reason: Map.get(attrs, "correction_reason", ""),
       save_error: nil
     )}
  end

  @impl true
  def handle_event("save", %{"campaign" => attrs}, socket) do
    case Campaigns.update_campaign_authoring(socket.assigns.campaign, attrs) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Campaign changes saved."))
         |> assign(
           campaign: Campaigns.get_campaign!(campaign.id),
           state_revision: campaign_revision(campaign.id),
           form: to_form(Campaigns.change_campaign(campaign), as: :campaign),
           gm_characters: Campaigns.list_gm_characters(campaign.id),
           correction_reason: "",
           authoring_corrections: Campaigns.list_public_authoring_corrections(campaign.id),
           save_error: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
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
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "Character voice notes must use the listed fields and stay within the length limits."
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
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "Character details must use the listed fields and stay within the length limits."
             )
         )}

      {:error, :invalid_active_duty} ->
        {:noreply,
         assign(socket,
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "An active duty needs a name up to 160 characters and a character with a known current place."
             )
         )}

      {:error, :stale_authoring_revision} ->
        {:noreply,
         assign(socket,
           state_revision: campaign_revision(socket.assigns.campaign.id),
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext(
               "The campaign changed while this setup was open. Review the current state and try again."
             )
         )}

      {:error, :authoring_turn_in_progress} ->
        {:noreply,
         assign(socket,
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
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error: gettext("Add a reason for changing the campaign setup.")
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           correction_reason: Map.get(attrs, "correction_reason", ""),
           save_error:
             gettext("Campaign changes could not be saved. Review the fields and try again.")
         )}
    end
  end

  defp voice_value(character, field), do: Map.get(character.voice_guidance || %{}, field, "")
  defp fact_value(facts, key), do: Map.get(facts || %{}, key, "")

  defp campaign_revision(campaign_id) do
    case Play.public_projection(campaign_id) do
      {:ok, projection} -> projection.revision
      _ -> 0
    end
  end

  def correction_category_label("campaign_setup"), do: gettext("Campaign setup")
  def correction_category_label("player_character"), do: gettext("Player character")
  def correction_category_label("character_details"), do: gettext("Character details")

  def correction_category_label(_category), do: gettext("Campaign setup")
end
