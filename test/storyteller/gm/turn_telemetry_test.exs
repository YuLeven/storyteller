defmodule Storyteller.GM.TurnTelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Storyteller.GM.TurnTelemetry

  test "emits numeric stage data with bounded labels and writes safe local diagnostics" do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler_id,
               TurnTelemetry.event(),
               fn event, measurements, metadata, _config ->
                 send(test_pid, {:stage_event, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    original_logger_level = Logger.level()

    log =
      try do
        Logger.configure(level: :info)

        capture_log([level: :info], fn ->
          assert :ok =
                   TurnTelemetry.stop(:model_resolution, System.monotonic_time(), :error, :miss)

          assert_receive {:stage_event, [:storyteller, :gm, :turn_stage, :stop], measurements,
                          metadata}

          assert Map.keys(measurements) |> Enum.sort() == [:duration, :failure, :success]
          assert is_integer(measurements.duration) and measurements.duration >= 0
          assert measurements.success == 0
          assert measurements.failure == 1
          assert metadata == %{stage: :model_resolution, cache: :miss}
        end)
      after
        Logger.configure(level: original_logger_level)
      end

    assert log =~ "gm_turn_stage stage=model_resolution duration_ms="
    assert log =~ "outcome=failure cache=miss"
    refute log =~ "fixture-account"
    refute log =~ "access-token"
    refute log =~ "campaign text"
  end

  test "rejects arbitrary stage and cache labels without emitting or logging them" do
    log =
      capture_log(fn ->
        assert :ok =
                 TurnTelemetry.stop("player supplied campaign text", System.monotonic_time(), :ok)

        assert :ok =
                 TurnTelemetry.stop(
                   :model_resolution,
                   System.monotonic_time(),
                   :ok,
                   "secret token"
                 )
      end)

    assert log == ""
  end

  test "shares an opaque local reference across a resolution and clears it afterward" do
    test_pid = self()
    handler_id = {__MODULE__, make_ref()}

    assert :ok =
             :telemetry.attach(
               handler_id,
               TurnTelemetry.event(),
               fn event, measurements, metadata, _config ->
                 send(test_pid, {:stage_event, event, measurements, metadata})
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    original_logger_level = Logger.level()

    log =
      try do
        Logger.configure(level: :info)

        capture_log([level: :info], fn ->
          ref =
            TurnTelemetry.with_turn_ref(fn ->
              current_ref = TurnTelemetry.current_turn_ref()
              assert Regex.match?(~r/\A[a-f0-9]{12}\z/, current_ref)

              assert :ok = TurnTelemetry.stop(:provider_stream, System.monotonic_time(), :ok)

              assert current_ref ==
                       TurnTelemetry.with_turn_ref(fn -> TurnTelemetry.current_turn_ref() end)

              assert TurnTelemetry.current_turn_ref() == current_ref
              current_ref
            end)

          assert TurnTelemetry.current_turn_ref() == nil
          send(test_pid, {:turn_ref, ref})
        end)
      after
        Logger.configure(level: original_logger_level)
      end

    assert_receive {:turn_ref, turn_ref}

    assert_receive {:stage_event, [:storyteller, :gm, :turn_stage, :stop], measurements, metadata}

    assert measurements.success == 1
    assert metadata == %{stage: :provider_stream, cache: :not_applicable, turn_ref: turn_ref}
    assert log =~ "turn_ref=#{turn_ref}"
    refute log =~ "campaign text"
    assert TurnTelemetry.current_turn_ref() == nil
  end

  test "local reporter ignores malformed measurements and metadata" do
    log =
      capture_log(fn ->
        :telemetry.execute(
          TurnTelemetry.event(),
          %{duration: 1, success: 1, failure: 0, prompt: "private campaign scene"},
          %{stage: :context_load, cache: :not_applicable, account_id: "private-account"}
        )
      end)

    refute log =~ "private campaign scene"
    refute log =~ "private-account"
    assert log == ""
  end
end
