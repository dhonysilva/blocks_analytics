# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :blocks_analytics,
  ecto_repos: [BlocksAnalytics.Repo, BlocksAnalytics.ClickhouseRepo],
  generators: [timestamp_type: :utc_datetime]

config :blocks_analytics, BlocksAnalytics.ClickhouseRepo,
  url: "http://127.0.0.1:8123/blocks_analytics_events_db",
  table_settings: []

# Configures the endpoint
config :blocks_analytics, BlocksAnalyticsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BlocksAnalyticsWeb.ErrorHTML, json: BlocksAnalyticsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BlocksAnalytics.PubSub,
  live_view: [signing_salt: "O+z4n0L4"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :blocks_analytics, BlocksAnalytics.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  blocks_analytics: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  blocks_analytics: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :blocks_analytics, ogmios_url: System.get_env("OGMIOS_URL", nil)

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
