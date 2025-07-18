defmodule BlocksAnalytics.Extract do
  alias BlocksAnalytics.Load

  def broadcast_new_block(new_block) do
    new_block = Map.merge(new_block, %{is_real_time: true})
    {:new_block, new_block}
  end

  @type new_block :: map()

  @doc """
  Builds the block map and invokes callback with the new block.
  """
  @spec update_blocks(block_from_xogmios :: map(), callback :: fun()) :: :ok
  def update_blocks(block, callback) do
    ada_output =
      block["transactions"]
      |> Stream.flat_map(fn tx -> tx["outputs"] end)
      |> Stream.map(fn output -> output["value"]["ada"]["lovelace"] end)
      |> Enum.sum()
      |> Decimal.div(1_000_000)
      |> Number.Delimit.number_to_delimited(precision: 0)

    fees =
      Stream.map(block["transactions"], fn tx ->
        tx["fee"]["ada"]["lovelace"]
      end)
      |> Enum.sum()
      |> Decimal.div(1_000_000)
      |> Decimal.round(2)
      |> to_string()

    new_block = %{
      block_id: block["id"],
      block_size: Decimal.div(block["size"]["bytes"], 1000) |> Decimal.round(1) |> to_string,
      block_height: block["height"],
      block_slot: block["slot"],
      issuer: normalize_issuer(block["issuer"]),
      tx_count: Enum.count(block["transactions"]),
      ada_output: ada_output,
      fees: fees,
      date_time: date_time_utc()
    }

    _ = Load.add_block(new_block)
    callback.(new_block)

    :ok
  end

  defp date_time_utc do
    DateTime.now!("Etc/UTC")
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  # Helper function to normalize issuer data to always be a string
  defp normalize_issuer(nil), do: "unknown"
  defp normalize_issuer(issuer) when is_binary(issuer), do: issuer

  defp normalize_issuer(issuer) when is_map(issuer) do
    # Extract pool_id, vrf_vkey, or convert to JSON string
    cond do
      Map.has_key?(issuer, "pool_id") -> Map.get(issuer, "pool_id")
      Map.has_key?(issuer, "vrf_vkey") -> Map.get(issuer, "vrf_vkey")
      true -> Jason.encode!(issuer)
    end
  end

  defp normalize_issuer(issuer), do: to_string(issuer)
end
