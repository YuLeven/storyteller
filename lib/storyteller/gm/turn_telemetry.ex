defmodule Storyteller.GM.TurnTelemetry do
  @moduledoc """
  Emits bounded, content-free measurements for the stages of GM turn resolution.

  Events carry only elapsed monotonic time, a success bit, and a fixed stage/cache
  label. Callers cannot attach arbitrary metadata, campaign details, or provider
  diagnostics to these measurements.
  """

  @event [:storyteller, :gm, :turn_stage, :stop]
  @stages [
    :context_load,
    :context_build,
    :oauth_access_token,
    :model_resolution,
    :request_to_first_output,
    :provider_stream,
    :proposal_decode,
    :proposal_validation,
    :commit
  ]
  @cache_labels [:hit, :miss, :not_used, :not_applicable]

  def event, do: @event

  def stop(stage, started_at, outcome, cache \\ :not_applicable)

  def stop(stage, started_at, outcome, cache)
      when stage in @stages and is_integer(started_at) and outcome in [:ok, :error] and
             cache in @cache_labels do
    duration = max(System.monotonic_time() - started_at, 0)
    success = if outcome == :ok, do: 1, else: 0

    :telemetry.execute(
      @event,
      %{duration: duration, success: success, failure: 1 - success},
      %{stage: stage, cache: cache}
    )

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def stop(_stage, _started_at, _outcome, _cache), do: :ok
end
