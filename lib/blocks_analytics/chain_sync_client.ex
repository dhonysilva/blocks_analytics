defmodule BlocksAnalytics.ChainSyncClient do
  @moduledoc """
  This module syncs with the chain and reads new blocks
  as they become available.
  """

  use Xogmios, :chain_sync

  alias BlocksAnalytics.Extract

  require Logger

  def start_link(opts) do
    Xogmios.start_chain_sync_link(__MODULE__, opts)
  end

  @impl true
  def handle_block(block, state) do
    Extract.update_blocks(block, &Extract.broadcast_new_block/1)

    {:ok, :next_block, state}
  end
end
