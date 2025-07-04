defmodule BlocksAnalytics.ClickhouseRepo.Migrations.AddTemperatureTable do
  use Ecto.Migration

  def up do
    create_temperatures()
  end

  defp create_temperatures() do
    create_if_not_exists table(:teperatures,
                           primary_key: false,
                           engine: "MergeTree",
                           options: """
                           PARTITION BY toYYYYMM(timestamp)
                           ORDER BY (device_id, toDate(timestamp))
                           #{BlocksAnalytics.MigrationUtils.table_settings_expr()}
                           """
                         ) do
      add(:device_id, :UInt64)
      add(:value, :integer)
      add(:timestamp, :naive_datetime)
    end
  end
end
