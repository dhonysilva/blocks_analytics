defmodule BlocksAnalytics.ClickhouseRepo do
  use Ecto.Repo,
    otp_app: :blocks_analytics,
    adapter: Ecto.Adapters.ClickHouse
end
