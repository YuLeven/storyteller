defmodule StorytellerWeb.CampaignLive.New do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.Campaign

  @impl true
  def mount(_params, _session, socket) do
    changeset = Campaigns.change_campaign(%Campaign{})

    {:ok,
     assign(socket,
       page_title: "New campaign",
       form: to_form(changeset, as: :campaign),
       reviewed: false,
       draft: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"campaign" => attrs}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)
    {:noreply, assign(socket, form: to_form(changeset, as: :campaign), draft: nil)}
  end

  @impl true
  def handle_event("review", %{"campaign" => attrs}, socket) do
    changeset = Campaigns.change_campaign(%Campaign{}, attrs)

    if changeset.valid? do
      {:noreply,
       assign(socket,
         form: to_form(changeset, as: :campaign),
         draft: Ecto.Changeset.apply_changes(changeset),
         reviewed: true
       )}
    else
      {:noreply, assign(socket, form: to_form(%{changeset | action: :validate}, as: :campaign))}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, reviewed: false)}
  end

  @impl true
  def handle_event("create", _params, %{assigns: %{draft: %Campaign{} = draft}} = socket) do
    case Campaigns.create_campaign(Map.from_struct(draft)) do
      {:ok, campaign} ->
        {:noreply,
         socket
         |> put_flash(:info, "Campaign created and its first session is ready to resume.")
         |> push_navigate(to: ~p"/campaigns/#{campaign.id}")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           reviewed: false,
           form: to_form(%{changeset | action: :validate}, as: :campaign)
         )}
    end
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:noreply, assign(socket, reviewed: false)}
  end
end
