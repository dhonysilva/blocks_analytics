defmodule BlocksAnalytics.ChainSyncClient do
  @moduledoc """
  This module syncs with the chain and reads new blocks
  as they become available.

  Be sure to add this module to your app's supervision tree like so:

  def start(_type, _args) do
    children = [
      ...,
      {BlocksAnalytics.ChainSyncClient, url: System.fetch_env!("OGMIOS_URL")}
    ]
    ...
  end
  """

  use Xogmios, :chain_sync

  def start_link(opts) do
    # Syncs from current tip by default
    initial_state = []
    ### See examples below on how to sync
    ### from different points of the chain:
    # initial_state = [sync_from: :babbage]
    # initial_state = [
    #   sync_from: %{
    #     point: %{
    #       slot: 114_127_654,
    #       id: "b0ff1e2bfc326a7f7378694b1f2693233058032bfb2798be2992a0db8b143099"
    #     }
    #   }
    # ]
    opts = Keyword.merge(opts, initial_state)
    Xogmios.start_chain_sync_link(__MODULE__, opts)
  end

  @impl true
  def handle_block(block, state) do
    IO.puts("handle_block #{block["height"]}")
    {:ok, :next_block, state}
  end
end
