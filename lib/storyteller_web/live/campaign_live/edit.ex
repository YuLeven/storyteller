defmodule StorytellerWeb.CampaignLive.Edit do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns

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
        {:ok,
         assign(socket,
           page_title: gettext("Edit campaign"),
           campaign: campaign,
           form: to_form(Campaigns.change_campaign(campaign), as: :campaign),
           gm_characters: Campaigns.list_gm_characters(campaign.id),
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
       save_error: nil
     )}
  end

  @impl true
  def handle_event("save", %{"campaign" => attrs}, socket) do
    case Campaigns.update_campaign_authoring(socket.assigns.campaign, attrs) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Campaign setup and character voice guidance saved."))
         |> push_navigate(to: ~p"/campaigns/#{campaign.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :validate}, as: :campaign),
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
           save_error:
             gettext(
               "Character details must use the listed fields and stay within the length limits."
             )
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           save_error:
             gettext("Campaign changes could not be saved. Review the fields and try again.")
         )}
    end
  end

  defp voice_value(character, field), do: Map.get(character.voice_guidance || %{}, field, "")
  defp fact_value(facts, key), do: Map.get(facts || %{}, key, "")
end
