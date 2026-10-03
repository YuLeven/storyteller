defmodule Storyteller.GM.ModelCatalogCache do
  @moduledoc """
  Short-lived in-memory cache for the connected account's displayable model list.

  Only the stable OAuth subject and successful model catalog are retained. The
  cache never stores access tokens, email addresses, campaign data, or prompts.
  """

  use GenServer

  @default_ttl_ms 300_000
  @max_entries 16

  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)

    if is_integer(ttl_ms) and ttl_ms > 0 do
      ttl_ms = min(ttl_ms, @default_ttl_ms)

      schedule_expiry(ttl_ms)
      {:ok, %{ttl_ms: ttl_ms, entries: %{}}}
    else
      {:stop, :invalid_ttl}
    end
  end

  def get(subject, server \\ __MODULE__)

  def get(subject, server)
      when is_binary(subject) and subject != "" do
    GenServer.call(server, {:get, subject})
  end

  def get(_subject, _server), do: :miss

  def put(subject, models, server \\ __MODULE__)

  def put(subject, models, server)
      when is_binary(subject) and subject != "" and is_list(models) and models != [] do
    GenServer.call(server, {:put, subject, models})
  end

  def put(_subject, _models, _server), do: :ok

  @impl true
  def handle_call({:get, subject}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entries = discard_expired(state.entries, now)

    reply =
      case Map.get(entries, subject) do
        %{expires_at: expires_at, models: models} when expires_at > now -> {:ok, models}
        _ -> :miss
      end

    {:reply, reply, %{state | entries: entries}}
  end

  def handle_call({:put, subject, models}, _from, state) do
    now = System.monotonic_time(:millisecond)
    entries = discard_expired(state.entries, now)

    entries =
      if Map.has_key?(entries, subject) or map_size(entries) < @max_entries do
        entries
      else
        evict_earliest_expiry(entries)
      end

    entry = %{expires_at: now + state.ttl_ms, models: models}
    {:reply, :ok, %{state | entries: Map.put(entries, subject, entry)}}
  end

  @impl true
  def handle_info(:expire_entries, state) do
    now = System.monotonic_time(:millisecond)
    state = %{state | entries: discard_expired(state.entries, now)}
    schedule_expiry(state.ttl_ms)

    {:noreply, state}
  end

  defp discard_expired(entries, now) do
    Map.reject(entries, fn {_subject, entry} -> entry.expires_at <= now end)
  end

  defp evict_earliest_expiry(entries) do
    {subject, _entry} = Enum.min_by(entries, fn {_subject, entry} -> entry.expires_at end)
    Map.delete(entries, subject)
  end

  defp schedule_expiry(ttl_ms), do: Process.send_after(self(), :expire_entries, ttl_ms)
end
