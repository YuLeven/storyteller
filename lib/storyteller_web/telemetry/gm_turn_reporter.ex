defmodule StorytellerWeb.Telemetry.GMTurnReporter do
  @moduledoc "Writes privacy-safe GM stage timings to the local application log."

  use GenServer
  require Logger

  @event [:storyteller, :gm, :turn_stage, :stop]
  @stages ~w(
    context_load context_build oauth_access_token model_resolution
    request_to_first_output provider_stream proposal_decode
    proposal_validation commit
  )a
  @cache_labels [:hit, :miss, :not_used, :not_applicable]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    handler_id = {__MODULE__, self()}

    case :telemetry.attach(handler_id, @event, &__MODULE__.handle_event/4, nil) do
      :ok -> {:ok, %{handler_id: handler_id}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(
        @event,
        %{duration: duration, success: success, failure: failure} = measurements,
        %{stage: stage, cache: cache} = metadata,
        _config
      )
      when is_integer(duration) and duration >= 0 and success in [0, 1] and failure in [0, 1] do
    turn_ref = Map.get(metadata, :turn_ref)

    if map_size(measurements) == 3 and valid_stage_metadata?(metadata, turn_ref, stage, cache) and
         stage in @stages and cache in @cache_labels and success + failure == 1 do
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)
      outcome = if success == 1, do: "success", else: "failure"
      ref_label = if is_binary(turn_ref), do: " turn_ref=#{turn_ref}", else: ""

      Logger.info(
        "gm_turn_stage stage=#{stage} duration_ms=#{duration_ms} outcome=#{outcome} cache=#{cache}#{ref_label}"
      )
    end

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp valid_stage_metadata?(metadata, nil, stage, cache),
    do: map_size(metadata) == 2 and metadata == %{stage: stage, cache: cache}

  defp valid_stage_metadata?(metadata, turn_ref, stage, cache) when is_binary(turn_ref) do
    map_size(metadata) == 3 and metadata == %{stage: stage, cache: cache, turn_ref: turn_ref} and
      Regex.match?(~r/\A[a-f0-9]{12}\z/, turn_ref)
  end

  defp valid_stage_metadata?(_metadata, _turn_ref, _stage, _cache), do: false
end
