defmodule StorytellerWeb.CampaignLive.Integrations do
  use StorytellerWeb, :live_view

  alias Storyteller.Campaigns

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
           page_title: gettext("Companion projects"),
           campaign: campaign,
           draft: integration_map(campaign.integrations),
           save_error: nil,
           save_succeeded: false
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"campaign" => attrs}, socket) do
    integrations = Map.get(attrs, "integrations", %{})

    {:noreply,
     assign(socket,
       draft: preserve_enabled_values(integrations, socket.assigns.draft),
       save_error: nil,
       save_succeeded: false
     )}
  end

  @impl true
  def handle_event("add-integration", _params, socket) do
    id = Ecto.UUID.generate()

    integration = %{
      "name" => "",
      "mcp_endpoint_url" => "",
      "instructions" => "",
      "site_label" => "",
      "site_url" => "",
      "enabled" => "true"
    }

    {:noreply,
     assign(socket,
       draft: Map.put(socket.assigns.draft, id, integration),
       save_error: nil,
       save_succeeded: false
     )}
  end

  @impl true
  def handle_event("remove-integration", %{"id" => id}, socket) do
    {:noreply,
     assign(socket,
       draft: Map.delete(socket.assigns.draft, id),
       save_error: nil,
       save_succeeded: false
     )}
  end

  @impl true
  def handle_event("save", %{"campaign" => attrs}, socket) do
    integrations =
      attrs
      |> Map.get("integrations", %{})
      |> preserve_enabled_values(socket.assigns.draft)
      |> reject_blank_rows()

    case Campaigns.update_integrations(socket.assigns.campaign, integrations) do
      {:ok, campaign} ->
        {:noreply,
         assign(socket,
           campaign: campaign,
           draft: integration_map(campaign.integrations),
           save_error: nil,
           save_succeeded: true
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        message =
          case Keyword.get(changeset.errors, :integrations) do
            {message, _opts} -> message
            _ -> gettext("Review each project and check its URLs and instructions.")
          end

        {:noreply,
         assign(socket,
           draft: integrations,
           save_error: message,
           save_succeeded: false
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           draft: integrations,
           save_error: gettext("Companion projects could not be saved."),
           save_succeeded: false
         )}
    end
  end

  defp integration_map(integrations) when is_map(integrations) do
    Map.new(integrations, fn {id, row} ->
      row =
        Map.new(row || %{}, fn {key, value} -> {to_string(key), value} end)
        |> Map.put_new("enabled", true)
        |> Map.put_new("instructions", "")
        |> Map.put_new("mcp_endpoint_url", "")
        |> Map.put_new("site_label", "")
        |> Map.put_new("site_url", "")

      {id, row}
    end)
  end

  defp integration_map(_), do: %{}

  defp preserve_enabled_values(integrations, previous) when is_map(integrations) do
    Map.new(integrations, fn {id, row} ->
      row = if is_map(row), do: row, else: %{}
      previous_row = Map.get(previous, id, %{})

      enabled =
        case Map.get(row, "enabled") do
          nil -> Map.get(previous_row, "enabled", true)
          value -> value
        end

      {id, Map.put(row, "enabled", enabled)}
    end)
  end

  defp preserve_enabled_values(_integrations, previous), do: previous

  defp reject_blank_rows(integrations) do
    Map.reject(integrations, fn {_id, row} ->
      Enum.all?(["name", "mcp_endpoint_url", "instructions", "site_label", "site_url"], fn key ->
        value = Map.get(row, key, "")
        not is_binary(value) or String.trim(value) == ""
      end)
    end)
  end
end
