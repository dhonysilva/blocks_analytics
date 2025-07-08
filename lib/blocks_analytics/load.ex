defmodule BlocksAnalytics.Load do
  @moduledoc """
  Load module that stores blocks both in memory (for real-time display)
  and persists them to ClickHouse for long-term storage and analytics.
  """

  use Agent
  alias BlocksAnalytics.ClickhouseService
  require Logger

  @doc """
  Starts the Agent with an empty list of blocks.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> [] end, name: name)
  end

  @doc """
  Adds new block to both in-memory storage and to ClickHouse,
  persisting them for long-term storage and analytics.
  """
  def add_block(pid \\ __MODULE__, block) do
    # First, try to persist to ClickHouse
    case persist_to_clickhouse(block) do
      {:ok, _} ->
        Logger.debug("Block #{block.block_id} successfully persisted to ClickHouse")

      {:error, reason} ->
        Logger.error(
          "Failed to persist block #{block.block_id} to ClickHouse: #{inspect(reason)}. " <>
            "Block data: #{inspect(Map.take(block, [:block_id, :block_height, :block_slot]))}"
        )

        # Continue with in-memory storage even if ClickHouse fails
    end

    # Then update in-memory storage
    Agent.get_and_update(pid, fn state ->
      new_state = [block | state]

      if length(new_state) > 10 do
        [last_block] = Enum.take(new_state, -1)
        {last_block, Enum.drop(new_state, -1)}
      else
        {nil, new_state}
      end
    end)
  end

  @doc """
  Returns a list with all currently stored blocks from in-memory storage.
  """
  def get_all_blocks(pid \\ __MODULE__) do
    Agent.get(pid, & &1)
  end

  @doc """
  Returns all blocks from ClickHouse storage.
  This provides access to the full historical data.
  """
  def get_all_blocks_from_clickhouse do
    ClickhouseService.get_all_blocks()
  end

  @doc """
  Returns recent blocks from ClickHouse with pagination support.
  """
  def get_recent_blocks_from_clickhouse(limit \\ 50, offset \\ 0) do
    ClickhouseService.get_blocks_paginated(limit, offset)
  end

  @doc """
  Returns blocks statistics from ClickHouse.
  """
  def get_blocks_statistics do
    ClickhouseService.get_blocks_stats()
  end

  @doc """
  Migrates all current in-memory blocks to ClickHouse.
  This is useful for initial data migration or backup.
  """
  def migrate_memory_to_clickhouse(pid \\ __MODULE__) do
    blocks = get_all_blocks(pid)

    case ClickhouseService.insert_blocks(blocks) do
      {:ok, inserted_blocks} ->
        Logger.info("Successfully migrated #{length(inserted_blocks)} blocks to ClickHouse")
        {:ok, length(inserted_blocks)}

      {:error, reason} ->
        Logger.error("Failed to migrate blocks to ClickHouse: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Searches for a specific block by block_id in ClickHouse.
  """
  def find_block_by_id(block_id) do
    ClickhouseService.get_block_by_id(block_id)
  end

  @doc """
  Gets blocks within a specific height range from ClickHouse.
  """
  def get_blocks_by_height_range(min_height, max_height) do
    ClickhouseService.get_blocks_by_height_range(min_height, max_height)
  end

  @doc """
  Gets blocks by issuer from ClickHouse.
  """
  def get_blocks_by_issuer(issuer) do
    ClickhouseService.get_blocks_by_issuer(issuer)
  end

  @doc """
  Gets blocks within a specific date range from ClickHouse.
  """
  def get_blocks_by_date_range(start_date, end_date) do
    ClickhouseService.get_blocks_by_date_range(start_date, end_date)
  end

  @doc """
  Gets the latest block from ClickHouse.
  """
  def get_latest_block_from_clickhouse do
    ClickhouseService.get_latest_block()
  end

  @doc """
  Clears all in-memory blocks. ClickHouse data remains intact.
  """
  def clear_memory_blocks(pid \\ __MODULE__) do
    Agent.update(pid, fn _ -> [] end)
  end

  @doc """
  Returns the current count of blocks in memory.
  """
  def count_memory_blocks(pid \\ __MODULE__) do
    Agent.get(pid, &length/1)
  end

  @doc """
  Checks if a block exists in ClickHouse.
  """
  def block_exists_in_clickhouse?(block_id) do
    ClickhouseService.block_exists?(block_id)
  end

  @doc """
  Bulk insert blocks to ClickHouse.
  Useful for batch operations or data imports.
  """
  def bulk_insert_blocks(blocks) when is_list(blocks) do
    case ClickhouseService.insert_blocks(blocks) do
      {:ok, inserted_blocks} ->
        Logger.info("Successfully bulk inserted #{length(inserted_blocks)} blocks to ClickHouse")
        {:ok, length(inserted_blocks)}

      {:error, reason} ->
        Logger.error("Failed to bulk insert blocks to ClickHouse: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp persist_to_clickhouse(block) do
    try do
      Logger.debug("Checking if block #{block.block_id} exists in ClickHouse...")

      # Check if block already exists to avoid duplicates
      if ClickhouseService.block_exists?(block.block_id) do
        Logger.debug("Block #{block.block_id} already exists in ClickHouse, skipping")
        {:ok, :already_exists}
      else
        Logger.debug("Block #{block.block_id} does not exist, attempting to store...")

        case ClickhouseService.store_block_from_memory(block) do
          {:ok, result} ->
            Logger.debug("Successfully stored block #{block.block_id} to ClickHouse")
            {:ok, result}

          {:error, reason} ->
            Logger.error("Failed to store block #{block.block_id}: #{inspect(reason)}")
            {:error, {:store_failed, reason}}
        end
      end
    rescue
      error ->
        Logger.error(
          "Exception in persist_to_clickhouse for block #{block.block_id}: #{inspect(error)}"
        )

        {:error, {:exception, error}}
    end
  end
end
