defmodule StorytellerWeb.SessionLive.Show do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns

  @impl true
  def mount(%{"campaign_id" => campaign_id, "session_id" => session_id}, _session, socket) do
    case Campaigns.get_session(campaign_id, session_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That session could not be found in this campaign.")
         |> push_navigate(to: ~p"/")}

      session ->
        {:ok, assign(socket, page_title: session.title, session: session)}
    end
  end
end
