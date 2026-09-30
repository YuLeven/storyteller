defmodule StorytellerWeb.CampaignBackupController do
  use StorytellerWeb, :controller

  alias Storyteller.CampaignBackup

  def show(conn, %{"id" => raw_id}) do
    case Integer.parse(raw_id) do
      {campaign_id, ""} when campaign_id > 0 ->
        case CampaignBackup.export(campaign_id) do
          {:ok, binary} ->
            conn
            |> put_resp_header("cache-control", "private, no-store")
            |> send_download({:binary, binary},
              filename: "storyteller-campaign-#{campaign_id}-sensitive-backup.json",
              content_type: "application/json",
              disposition: :attachment
            )

          {:error, _reason} ->
            conn
            |> put_status(:not_found)
            |> text("Campaign backup is unavailable.")
        end

      _ ->
        conn
        |> put_status(:not_found)
        |> text("Campaign backup is unavailable.")
    end
  end
end
