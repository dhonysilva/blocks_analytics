defmodule BlocksAnalytics.ClickhouseRepo.Migrations.CreateBlocksTable do
  use Ecto.Migration

  def up do
    create_blocks_table()
  end

  def down do
    drop_if_exists(table(:blocks))
  end

  defp create_blocks_table() do
    create_if_not_exists table(:blocks,
                           primary_key: false,
                           engine: "MergeTree",
                           options: """
                           PARTITION BY toYYYYMM(date_time)
                           ORDER BY (block_height, toDate(date_time))
                           #{BlocksAnalytics.MigrationUtils.table_settings_expr()}
                           """
                         ) do
      add(:block_id, :string)
      add(:block_size, :string)
      add(:block_height, :UInt64)
      add(:block_slot, :UInt64)
      add(:issuer, :string)
      add(:tx_count, :UInt32)
      add(:ada_output, :string)
      add(:fees, :string)
      add(:date_time, :naive_datetime)
      add(:inserted_at, :naive_datetime)
    end
  end
end
