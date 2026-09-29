defmodule Storyteller.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StorytellerWeb.Telemetry,
      Storyteller.Repo,
      {DNSCluster, query: Application.get_env(:storyteller, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Storyteller.PubSub},
      # Start a worker by calling: Storyteller.Worker.start_link(arg)
      # {Storyteller.Worker, arg},
      # Start to serve requests, typically the last entry
      StorytellerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Storyteller.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StorytellerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
