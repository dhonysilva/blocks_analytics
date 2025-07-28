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
      add(:block_size, :UInt32)
      add(:block_height, :UInt64)
      add(:block_slot, :UInt64)

      add(:issuer_output, :string)
      add(:issuer_proof, :string)
      add(:issuer_count, :UInt32)
      add(:issuer_kes_period, :UInt32)
      add(:issuer_kes_verification_key, :string)
      add(:issuer_sigma, :string)
      add(:issuer_verification_key, :string)
      add(:issuer_vrf_verification_key, :string)

      add(:tx_count, :UInt32)
      add(:ada_output, :UInt32)
      add(:fees, :UInt32)
      add(:date_time, :naive_datetime)
      add(:inserted_at, :naive_datetime)
    end
  end
end
