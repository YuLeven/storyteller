defmodule Storyteller.Campaigns do
  @moduledoc "Campaign and session persistence for the local Storyteller application."

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Storyteller.Campaigns.{Campaign, Session}
  alias Storyteller.Repo

  def list_campaigns do
    session_query = from session in Session, order_by: [desc: session.inserted_at]

    Repo.all(
      from campaign in Campaign,
        order_by: [desc: campaign.updated_at, desc: campaign.inserted_at],
        preload: [sessions: ^session_query]
    )
  end

  def get_campaign(id) do
    case Repo.get(Campaign, id) do
      nil ->
        nil

      campaign ->
        Repo.preload(campaign,
          sessions: from(session in Session, order_by: [desc: session.inserted_at])
        )
    end
  end

  def get_campaign!(id) do
    Repo.get!(Campaign, id)
    |> Repo.preload(sessions: from(session in Session, order_by: [desc: session.inserted_at]))
  end

  def change_campaign(%Campaign{} = campaign, attrs \\ %{}) do
    Campaign.changeset(campaign, attrs)
  end

  def create_campaign(attrs) do
    campaign_changeset = Campaign.changeset(%Campaign{}, attrs)

    if campaign_changeset.valid? do
      Multi.new()
      |> Multi.insert(:campaign, campaign_changeset)
      |> Multi.insert(:session, fn %{campaign: campaign} ->
        Session.changeset(%Session{}, %{campaign_id: campaign.id, title: "Session 1"})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{campaign: campaign, session: session}} ->
          {:ok, %{campaign | sessions: [session]}}

        {:error, :campaign, changeset, _changes} ->
          {:error, changeset}

        {:error, :session, changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, campaign_changeset}
    end
  end

  def start_session(%Campaign{id: campaign_id}, attrs \\ %{}) do
    Multi.new()
    |> Multi.run(:locked_campaign, fn repo, _changes ->
      case repo.one(
             from campaign in Campaign, where: campaign.id == ^campaign_id, lock: "FOR UPDATE"
           ) do
        %Campaign{status: :active} = campaign -> {:ok, campaign}
        %Campaign{status: :archived} -> {:error, :campaign_archived}
        nil -> {:error, :not_found}
      end
    end)
    |> Multi.update_all(
      :complete_previous_session,
      from(session in Session,
        where: session.campaign_id == ^campaign_id and session.status == :active
      ),
      set: [status: :completed, ended_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)]
    )
    |> Multi.insert(:session, fn %{locked_campaign: campaign} ->
      sequence =
        Repo.aggregate(
          from(session in Session, where: session.campaign_id == ^campaign.id),
          :count
        )

      title = supplied_title(attrs) || "Session #{sequence + 1}"

      Session.changeset(%Session{}, %{campaign_id: campaign.id, title: title})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} -> {:ok, session}
      {:error, :session, changeset, _changes} -> {:error, changeset}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def get_session(campaign_id, session_id) do
    Repo.get_by(Session, id: session_id, campaign_id: campaign_id)
    |> case do
      nil -> nil
      session -> Repo.preload(session, :campaign)
    end
  end

  def archive_campaign(%Campaign{id: campaign_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Multi.new()
    |> Multi.run(:locked_campaign, fn repo, _changes ->
      case repo.one(
             from campaign in Campaign, where: campaign.id == ^campaign_id, lock: "FOR UPDATE"
           ) do
        nil -> {:error, :not_found}
        campaign -> {:ok, campaign}
      end
    end)
    |> Multi.update_all(
      :complete_active_sessions,
      from(session in Session,
        where: session.campaign_id == ^campaign_id and session.status == :active
      ),
      set: [status: :completed, ended_at: now]
    )
    |> Multi.update(:campaign, fn %{locked_campaign: campaign} ->
      Campaign.changeset(campaign, %{status: :archived})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{campaign: campaign}} -> {:ok, campaign}
      {:error, :campaign, changeset, _changes} -> {:error, changeset}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  def restore_campaign(%Campaign{} = campaign) do
    campaign
    |> Campaign.changeset(%{status: :active})
    |> Repo.update()
  end

  defp supplied_title(attrs) do
    attrs
    |> Map.get(:title, Map.get(attrs, "title"))
    |> case do
      title when is_binary(title) -> String.trim(title)
      _ -> ""
    end
    |> case do
      "" -> nil
      title -> title
    end
  end
end
