defmodule StorytellerWeb.CampaignLive.Index do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: gettext("Campaigns"), campaigns: Campaigns.list_campaigns())}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    case Campaigns.get_campaign(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("That campaign could not be found."))}

      campaign ->
        case Campaigns.archive_campaign(campaign) do
          {:ok, _campaign} ->
            {:noreply,
             socket
             |> assign(campaigns: Campaigns.list_campaigns())
             |> put_flash(:info, gettext("Campaign archived. Its sessions are saved."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("The campaign could not be archived."))}
        end
    end
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    case Campaigns.get_campaign(id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("That campaign could not be found."))}

      campaign ->
        case Campaigns.restore_campaign(campaign) do
          {:ok, _campaign} ->
            {:noreply,
             socket
             |> assign(campaigns: Campaigns.list_campaigns())
             |> put_flash(:info, gettext("Campaign restored."))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("The campaign could not be restored."))}
        end
    end
  end
end
