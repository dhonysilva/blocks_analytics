defmodule BlocksAnalytics.ClickhouseService do
  @moduledoc """
  Service module for ClickHouse operations on blocks data.
  Provides functions to store, retrieve, and query Cardano blocks.
  """

  alias BlocksAnalytics.ClickhouseRepo
  alias BlocksAnalytics.Schemas.Block
  alias BlocksAnalytics.Load
  import Ecto.Query

  @doc """
  Inserts a single block into ClickHouse.
  """
  @spec insert_block(map()) :: {:ok, Block.t()} | {:error, Ecto.Changeset.t()}
  def insert_block(block_attrs) do
    # Ensure datetime fields are truncated to seconds
    processed_attrs = truncate_datetime_fields(block_attrs)

    %Block{}
    |> Block.changeset(processed_attrs)
    |> ClickhouseRepo.insert()
  end

  @doc """
  Inserts multiple blocks into ClickHouse in a single batch operation.
  This is more efficient for bulk operations.
  """
  @spec insert_blocks([map()]) :: {:ok, [Block.t()]} | {:error, term()}
  def insert_blocks(blocks_attrs) when is_list(blocks_attrs) do
    blocks =
      blocks_attrs
      |> Enum.map(fn attrs ->
        %Block{}
        |> Block.changeset(attrs)
        |> Ecto.Changeset.apply_changes()
      end)

    case ClickhouseRepo.insert_all(Block, blocks, returning: false) do
      {count, _} when count > 0 -> {:ok, blocks}
      error -> {:error, error}
    end
  end

  @doc """
  Retrieves all blocks from ClickHouse.
  Returns blocks ordered by block_height in descending order.
  """
  @spec get_all_blocks() :: [Block.t()]
  def get_all_blocks do
    Block
    |> order_by(desc: :block_height)
    |> ClickhouseRepo.all()
  end

  @doc """
  Retrieves blocks with pagination support.
  """
  @spec get_blocks_paginated(integer(), integer()) :: [Block.t()]
  def get_blocks_paginated(limit \\ 50, offset \\ 0) do
    Block
    |> order_by(desc: :block_height)
    |> limit(^limit)
    |> offset(^offset)
    |> ClickhouseRepo.all()
  end

  @doc """
  Retrieves blocks within a specific height range.
  """
  @spec get_blocks_by_height_range(integer(), integer()) :: [Block.t()]
  def get_blocks_by_height_range(min_height, max_height) do
    Block
    |> where([b], b.block_height >= ^min_height and b.block_height <= ^max_height)
    |> order_by(desc: :block_height)
    |> ClickhouseRepo.all()
  end

  @doc """
  Retrieves blocks by issuer.
  """
  @spec get_blocks_by_issuer(String.t()) :: [Block.t()]
  def get_blocks_by_issuer(issuer) do
    Block
    |> where([b], b.issuer == ^issuer)
    |> order_by(desc: :block_height)
    |> ClickhouseRepo.all()
  end

  @doc """
  Retrieves blocks within a specific time range.
  """
  @spec get_blocks_by_date_range(NaiveDateTime.t(), NaiveDateTime.t()) :: [Block.t()]
  def get_blocks_by_date_range(start_date, end_date) do
    Block
    |> where([b], b.date_time >= ^start_date and b.date_time <= ^end_date)
    |> order_by(desc: :block_height)
    |> ClickhouseRepo.all()
  end

  @doc """
  Gets the latest block by height.
  """
  @spec get_latest_block() :: Block.t() | nil
  def get_latest_block do
    Block
    |> order_by(desc: :block_height)
    |> limit(1)
    |> ClickhouseRepo.one()
  end

  @doc """
  Gets a specific block by block_id.
  """
  @spec get_block_by_id(String.t()) :: Block.t() | nil
  def get_block_by_id(block_id) do
    Block
    |> where([b], b.block_id == ^block_id)
    |> ClickhouseRepo.one()
  end

  @doc """
  Gets blocks statistics including total count, average block size, etc.
  """
  @spec get_blocks_stats() :: map()
  def get_blocks_stats do
    query = """
    SELECT
      count(*) as total_blocks,
      avg(block_height) as avg_height,
      max(block_height) as max_height,
      min(block_height) as min_height,
      sum(tx_count) as total_transactions,
      avg(tx_count) as avg_transactions_per_block
    FROM blocks
    """

    case ClickhouseRepo.query(query) do
      {:ok, %{rows: [[total, avg_height, max_height, min_height, total_tx, avg_tx]]}} ->
        %{
          total_blocks: total,
          avg_height: avg_height,
          max_height: max_height,
          min_height: min_height,
          total_transactions: total_tx,
          avg_transactions_per_block: avg_tx
        }

      _ ->
        %{
          total_blocks: 0,
          avg_height: 0,
          max_height: 0,
          min_height: 0,
          total_transactions: 0,
          avg_transactions_per_block: 0
        }
    end
  end

  @doc """
  Migrates blocks from the in-memory storage to ClickHouse.
  This function fetches all blocks from the Load module and stores them in ClickHouse.
  """
  @spec migrate_blocks_to_clickhouse() :: {:ok, integer()} | {:error, term()}
  def migrate_blocks_to_clickhouse do
    blocks = Load.get_all_blocks()

    case insert_blocks(blocks) do
      {:ok, inserted_blocks} -> {:ok, length(inserted_blocks)}
      error -> error
    end
  end

  @doc """
  Checks if a block with the given block_id already exists in ClickHouse.
  """
  @spec block_exists?(String.t()) :: boolean()
  def block_exists?(block_id) do
    Block
    |> where([b], b.block_id == ^block_id)
    |> select([b], 1)
    |> limit(1)
    |> ClickhouseRepo.exists?()
  end

  @doc """
  Deletes all blocks from ClickHouse.
  Use with caution!
  """
  @spec delete_all_blocks() :: {:ok, integer()} | {:error, term()}
  def delete_all_blocks do
    case ClickhouseRepo.delete_all(Block) do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end

  @doc """
  Gets recent blocks (last N blocks).
  """
  @spec get_recent_blocks(integer()) :: [Block.t()]
  def get_recent_blocks(limit \\ 10) do
    Block
    |> order_by(desc: :block_height)
    |> limit(^limit)
    |> ClickhouseRepo.all()
  end

  @doc """
  Stores a block from the get_all_blocks function data to ClickHouse.
  This function is designed to work with the current Load module data structure.
  """
  @spec store_block_from_memory(map()) :: {:ok, Block.t()} | {:error, term()}
  def store_block_from_memory(block_data) do
    # Convert datetime string back to NaiveDateTime if needed
    processed_attrs =
      case block_data[:date_time] do
        dt when is_binary(dt) ->
          case NaiveDateTime.from_iso8601(dt) do
            {:ok, naive_dt} ->
              truncated_dt = NaiveDateTime.truncate(naive_dt, :second)
              Map.put(block_data, :date_time, truncated_dt)

            {:error, _} ->
              # Try alternative parsing approaches
              case try_alternative_datetime_parsing(dt) do
                {:ok, naive_dt} ->
                  truncated_dt = NaiveDateTime.truncate(naive_dt, :second)
                  Map.put(block_data, :date_time, truncated_dt)

                _ ->
                  block_data
              end
          end

        %NaiveDateTime{} = dt ->
          truncated_dt = NaiveDateTime.truncate(dt, :second)
          Map.put(block_data, :date_time, truncated_dt)

        _ ->
          block_data
      end

    insert_block(processed_attrs)
  end

  # Private helper functions for datetime handling
  defp truncate_datetime_fields(attrs) do
    attrs
    |> truncate_datetime_field(:date_time)
    |> truncate_datetime_field(:inserted_at)
  end

  defp truncate_datetime_field(attrs, field) do
    case attrs[field] do
      %NaiveDateTime{} = datetime ->
        Map.put(attrs, field, NaiveDateTime.truncate(datetime, :second))

      _ ->
        attrs
    end
  end

  # Helper function to try alternative datetime parsing approaches
  defp try_alternative_datetime_parsing(dt_string) do
    # Try with Z suffix for UTC
    case DateTime.from_iso8601(dt_string <> "Z") do
      {:ok, dt, _} ->
        {:ok, DateTime.to_naive(dt)}

      {:error, _} ->
        # Try with T separator instead of space
        iso_format = String.replace(dt_string, " ", "T")

        case NaiveDateTime.from_iso8601(iso_format) do
          {:ok, naive_dt} ->
            {:ok, naive_dt}

          {:error, _} ->
            {:error, :invalid_format}
        end
    end
  end
end
