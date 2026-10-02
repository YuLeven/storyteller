defmodule StorytellerWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("storyteller.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("storyteller.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("storyteller.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("storyteller.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("storyteller.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Safe GM context diagnostics: counts and byte sizes only, never prompt data.
      summary("storyteller.gm.context.estimated_request_bytes"),
      summary("storyteller.gm.context.provider_input_tokens"),
      summary("storyteller.gm.context.provider_output_tokens"),
      summary("storyteller.gm.context.instructions_bytes"),
      summary("storyteller.gm.context.context_json_bytes"),
      summary("storyteller.gm.context.section_campaign_bytes"),
      summary("storyteller.gm.context.section_world_bytes"),
      summary("storyteller.gm.context.section_inventory_bytes"),
      summary("storyteller.gm.context.section_places_bytes"),
      summary("storyteller.gm.context.section_travel_connections_bytes"),
      summary("storyteller.gm.context.section_objectives_bytes"),
      summary("storyteller.gm.context.section_memory_bytes"),
      summary("storyteller.gm.context.section_continuity_bytes"),
      summary("storyteller.gm.context.section_characters_bytes"),
      summary("storyteller.gm.context.section_panels_bytes"),
      summary("storyteller.gm.context.section_history_bytes"),

      # Provider wall-clock latency and outcome counts; measurements only.
      summary("storyteller.gm.provider.stop.duration",
        unit: {:native, :millisecond},
        description: "Provider invocation wall-clock duration"
      ),
      sum("storyteller.gm.provider.stop.success"),
      sum("storyteller.gm.provider.stop.failure"),
      summary("storyteller.gm.provider.first_text_delta.stop.duration",
        unit: {:native, :millisecond},
        description: "Time from the start of a provider call to its first streamed text delta"
      ),
      summary("storyteller.gm.resolution.stop.duration",
        unit: {:native, :millisecond},
        description:
          "Turn resolution duration including local context, validation, and commit work"
      ),
      sum("storyteller.gm.resolution.stop.success"),
      sum("storyteller.gm.resolution.stop.failure"),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {StorytellerWeb, :count_users, []}
    ]
  end
end
