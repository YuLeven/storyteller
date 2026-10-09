defmodule Storyteller.GM.TurnTelemetry do
  @moduledoc """
  Emits bounded, content-free measurements for the stages of GM turn resolution.

  Events carry only elapsed monotonic time, a success bit, and a fixed stage/cache
  label. During a resolution they also carry one random, local correlation
  reference shared by all attempts for that saved turn. Callers cannot attach
  arbitrary metadata, campaign details, or provider diagnostics to measurements.
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
  @turn_ref_key {__MODULE__, :turn_ref}
  @turn_ref_pattern ~r/\A[a-f0-9]{12}\z/

  def event, do: @event

  @doc false
  def with_turn_ref(fun) when is_function(fun, 0) do
    previous_ref = Process.get(@turn_ref_key)
    turn_ref = if valid_turn_ref?(previous_ref), do: previous_ref, else: new_turn_ref()

    Process.put(@turn_ref_key, turn_ref)

    try do
      fun.()
    after
      if is_nil(previous_ref) do
        Process.delete(@turn_ref_key)
      else
        Process.put(@turn_ref_key, previous_ref)
      end
    end
  end

  @doc false
  def current_turn_ref do
    case Process.get(@turn_ref_key) do
      ref when is_binary(ref) -> if valid_turn_ref?(ref), do: ref
      _ -> nil
    end
  end

  def stop(stage, started_at, outcome, cache \\ :not_applicable)

  def stop(stage, started_at, outcome, cache)
      when stage in @stages and is_integer(started_at) and outcome in [:ok, :error] and
             cache in @cache_labels do
    duration = max(System.monotonic_time() - started_at, 0)
    success = if outcome == :ok, do: 1, else: 0

    metadata = %{stage: stage, cache: cache}

    metadata =
      if turn_ref = current_turn_ref(), do: Map.put(metadata, :turn_ref, turn_ref), else: metadata

    :telemetry.execute(
      @event,
      %{duration: duration, success: success, failure: 1 - success},
      metadata
    )

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def stop(_stage, _started_at, _outcome, _cache), do: :ok

  defp new_turn_ref, do: :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)

  defp valid_turn_ref?(ref) when is_binary(ref), do: Regex.match?(@turn_ref_pattern, ref)
  defp valid_turn_ref?(_ref), do: false
end
