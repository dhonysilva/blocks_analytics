defmodule BlocksAnalytics.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if File.exists?(".env") do
      Dotenv.load()
    end

    children = [
      BlocksAnalyticsWeb.Telemetry,
      BlocksAnalytics.Repo,
      BlocksAnalytics.ClickhouseRepo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:blocks_analytics, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:blocks_analytics, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BlocksAnalytics.PubSub},
      # Start a worker by calling: BlocksAnalytics.Worker.start_link(arg)
      # {BlocksAnalytics.Worker, arg},
      # Start to serve requests, typically the last entry
      BlocksAnalytics.Load,
      {BlocksAnalytics.ChainSyncClient, url: ogmios_connection_url()},
      BlocksAnalyticsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BlocksAnalytics.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BlocksAnalyticsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp ogmios_connection_url() do
    System.fetch_env!("OGMIOS_URL")
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
