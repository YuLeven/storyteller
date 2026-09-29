defmodule StorytellerWeb.CampaignLive.Show do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Panels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Campaigns.get_campaign(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("That campaign could not be found."))
         |> push_navigate(to: ~p"/")}

      campaign ->
        panels =
          case Panels.public_projection(campaign.id) do
            {:ok, %{panels: panels}} -> panels
            _ -> []
          end

        {:ok,
         assign(socket,
           page_title: campaign.title,
           campaign: campaign,
           panels: panels,
           session_title: "",
           session_error?: false
         )}
    end
  end

  @impl true
  def handle_event("start-session", %{"session" => attrs}, socket) do
    case Campaigns.start_session(socket.assigns.campaign, attrs) do
      {:ok, session} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Session started. Your campaign history is still here."))
         |> push_navigate(to: ~p"/campaigns/#{socket.assigns.campaign.id}/sessions/#{session.id}")}

      {:error, :campaign_archived} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Restore this campaign before starting another session.")
         )}

      {:error, _changeset} ->
        {:noreply, assign(socket, session_title: attrs["title"] || "", session_error?: true)}
    end
  end

  @impl true
  def handle_event("archive", _params, socket) do
    case Campaigns.archive_campaign(socket.assigns.campaign) do
      {:ok, _campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Campaign archived. Its sessions remain saved."))
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("The campaign could not be archived."))}
    end
  end

  @impl true
  def handle_event("restore", _params, socket) do
    case Campaigns.restore_campaign(socket.assigns.campaign) do
      {:ok, _campaign} ->
        {:noreply,
         socket
         |> assign(campaign: Campaigns.get_campaign(socket.assigns.campaign.id))
         |> put_flash(:info, gettext("Campaign restored."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("The campaign could not be restored."))}
    end
  end

  defp panel_value(value, unit) do
    rendered = if is_nil(value), do: gettext("Not set"), else: to_string(value)
    if is_binary(unit) and unit != "", do: rendered <> " " <> unit, else: rendered
  end
end
