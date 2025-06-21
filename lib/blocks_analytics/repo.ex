defmodule BlocksAnalytics.Repo do
  use Ecto.Repo,
    otp_app: :blocks_analytics,
    adapter: Ecto.Adapters.SQLite3
end
