defmodule StorytellerWeb.CampaignLive.Index do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.CampaignBackup

  @max_backup_bytes 52_428_800

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Campaigns"), campaigns: Campaigns.list_campaigns())
     |> allow_upload(:campaign_backup,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: @max_backup_bytes
     )}
  end

  @impl true
  def handle_event("import-backup", _params, socket) do
    case uploaded_entries(socket, :campaign_backup) do
      {[_entry], []} ->
        [result] =
          consume_uploaded_entries(socket, :campaign_backup, fn %{path: path}, _entry ->
            result =
              case File.read(path) do
                {:ok, binary} -> CampaignBackup.import(binary)
                {:error, _reason} -> {:error, :invalid_backup}
              end

            {:ok, result}
          end)

        case result do
          {:ok, campaign} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Campaign restored as a separate copy."))
             |> push_navigate(to: ~p"/campaigns/#{campaign.id}")}

          {:error, :invalid_backup} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("This is not a valid, supported Storyteller campaign backup.")
             )}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("The backup could not be restored. No campaign was changed.")
             )}
        end

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Choose one completed JSON backup file to import."))}
    end
  end

  @impl true
  def handle_event("validate-backup-upload", _params, socket), do: {:noreply, socket}

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

  defp upload_error(:too_large), do: gettext("The file must be 50 MB or smaller.")
  defp upload_error(:not_accepted), do: gettext("Choose a JSON backup file.")
  defp upload_error(_), do: gettext("This file could not be uploaded.")
end
