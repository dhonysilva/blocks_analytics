defmodule BlocksAnalyticsWeb.DashboardLive do
  use BlocksAnalyticsWeb, :live_view

  alias BlocksAnalytics.ClickhouseService

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(30_000, self(), :update_data)
    end

    {:ok, load_dashboard_data(socket)}
  end

  # Auto-refresh data every 30 seconds
  def handle_info(:update_data, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  # Manual refresh
  def handle_event("refresh", _params, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  defp load_dashboard_data(socket) do
    socket
    |> assign(:statistics, get_statistics())
    |> assign(:recent_blocks, get_recent_blocks())
    |> assign(:issuer_summary, get_issuer_summary())
    |> assign(:block_distribution, get_block_distribution())
    |> assign(:hourly_averages, get_hourly_averages())
    |> assign(:last_updated, NaiveDateTime.utc_now())
  end

  defp get_statistics do
    base_stats = ClickhouseService.get_blocks_stats()

    # Get additional stats
    latest_block = ClickhouseService.get_latest_block()
    recent_blocks = ClickhouseService.get_recent_blocks(100)

    # Calculate additional metrics
    avg_block_size =
      if length(recent_blocks) > 0 do
        recent_blocks
        |> Enum.map(fn block ->
          case block.block_size do
            {size, _} -> size
            _ -> 0
          end
        end)
        |> Enum.sum()
        |> div(length(recent_blocks))
      else
        0
      end

    avg_fees =
      if length(recent_blocks) > 0 do
        recent_blocks
        |> Enum.map(fn block ->
          case block.fees do
            {fees, _} -> fees
            _ -> 0
          end
        end)
        |> Enum.sum()
        |> div(length(recent_blocks))
      else
        0
      end

    base_stats
    |> Map.put(:latest_block_height, if(latest_block, do: latest_block.block_height, else: 0))
    |> Map.put(:latest_block_time, if(latest_block, do: latest_block.date_time, else: nil))
    |> Map.put(:avg_block_size, avg_block_size)
    |> Map.put(:avg_fees, avg_fees)
  end

  defp get_recent_blocks do
    ClickhouseService.get_recent_blocks(20)
  end

  defp get_issuer_summary do
    # Get top 10 issuers by block count
    query = """
    SELECT
      issuer,
      count(*) as block_count,
      sum(tx_count) as total_transactions,
      avg(tx_count) as avg_transactions
    FROM blocks
    GROUP BY issuer
    ORDER BY block_count DESC
    LIMIT 10
    """

    case BlocksAnalytics.ClickhouseRepo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [issuer, block_count, total_tx, avg_tx] ->
          %{
            issuer: issuer,
            block_count: block_count,
            total_transactions: total_tx,
            avg_transactions: Float.round(avg_tx, 2)
          }
        end)

      _ ->
        []
    end
  end

  defp get_block_distribution do
    # Get block distribution by transaction count ranges
    query = """
    SELECT
      CASE
        WHEN tx_count = 0 THEN 'Empty (0)'
        WHEN tx_count BETWEEN 1 AND 10 THEN 'Low (1-10)'
        WHEN tx_count BETWEEN 11 AND 50 THEN 'Medium (11-50)'
        WHEN tx_count BETWEEN 51 AND 100 THEN 'High (51-100)'
        WHEN tx_count > 100 THEN 'Very High (>100)'
      END as tx_range,
      count(*) as count,
      avg(tx_count) as avg_tx_count
    FROM blocks
    GROUP BY tx_range
    ORDER BY avg_tx_count
    """

    case BlocksAnalytics.ClickhouseRepo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [range, count, avg_tx] ->
          %{
            range: range,
            count: count,
            avg_tx_count: Float.round(avg_tx, 2)
          }
        end)

      _ ->
        []
    end
  end

  defp get_hourly_averages do
    # Get hourly block production averages for the last 24 hours
    query = """
    SELECT
      toHour(date_time) as hour,
      count(*) as block_count,
      avg(tx_count) as avg_transactions,
      sum(tx_count) as total_transactions
    FROM blocks
    WHERE date_time >= now() - INTERVAL 24 HOUR
    GROUP BY hour
    ORDER BY hour
    """

    case BlocksAnalytics.ClickhouseRepo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [hour, block_count, avg_tx, total_tx] ->
          %{
            hour: hour,
            block_count: block_count,
            avg_transactions: Float.round(avg_tx, 2),
            total_transactions: total_tx
          }
        end)

      _ ->
        []
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ".")
  end

  defp format_number(num) when is_float(num) do
    :io_lib.format("~.2f", [num])
    |> IO.iodata_to_binary()
  end

  defp format_number(num), do: to_string(num)

  defp format_timestamp(timestamp) when is_struct(timestamp, NaiveDateTime) do
    timestamp
    |> NaiveDateTime.to_string()
    |> String.replace(~r/\.\d+/, "")
  end

  defp format_timestamp(timestamp), do: to_string(timestamp)

  defp format_ada_amount(amount_str) when is_binary(amount_str) do
    case Integer.parse(amount_str) do
      {amount, _} ->
        # Convert from lovelace to ADA
        ada_amount = amount / 1_000_000
        "#{:io_lib.format("~.2f", [ada_amount])} ADA"

      _ ->
        amount_str
    end
  end

  defp format_ada_amount(amount), do: to_string(amount)

  defp format_bytes(size_str) when is_binary(size_str) do
    case Integer.parse(size_str) do
      {size, _} when size >= 1024 * 1024 ->
        mb_size = size / (1024 * 1024)
        "#{:io_lib.format("~.2f", [mb_size])} MB"

      {size, _} when size >= 1024 ->
        kb_size = size / 1024
        "#{:io_lib.format("~.2f", [kb_size])} KB"

      {size, _} ->
        "#{size} bytes"

      _ ->
        size_str
    end
  end

  defp format_bytes(size), do: to_string(size)

  def render(assigns) do
    ~H"""
    <div class="p-6 max-w-7xl mx-auto">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold text-gray-900">Cardano Blocks Dashboard</h1>
        <div class="flex items-center space-x-4">
          <span class="text-sm text-gray-500">
            Last updated: {format_timestamp(@last_updated)}
          </span>
          <button
            phx-click="refresh"
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
            Refresh
          </button>
        </div>
      </div>
      
    <!-- Statistics Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div class="bg-white overflow-hidden shadow-sm rounded-lg">
          <div class="p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                  <svg
                    class="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                    />
                  </svg>
                </div>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Total Blocks</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {format_number(@statistics.total_blocks)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow-sm rounded-lg">
          <div class="p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                  <svg
                    class="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"
                    />
                  </svg>
                </div>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Latest Block Height</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {format_number(@statistics.latest_block_height)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow-sm rounded-lg">
          <div class="p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-yellow-500 rounded-full flex items-center justify-center">
                  <svg
                    class="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                    />
                  </svg>
                </div>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Total Transactions</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {format_number(@statistics.total_transactions)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow-sm rounded-lg">
          <div class="p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-purple-500 rounded-full flex items-center justify-center">
                  <svg
                    class="w-5 h-5 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1"
                    />
                  </svg>
                </div>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Avg TX per Block</p>
                <p class="text-2xl font-semibold text-gray-900">
                  {format_number(@statistics.avg_transactions_per_block)}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Recent Blocks and Issuer Summary -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <!-- Recent Blocks -->
        <div class="bg-white shadow-sm rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Recent Blocks</h3>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <%= for block <- @recent_blocks do %>
                <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div class="flex-1">
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium text-gray-900">
                        Height: {format_number(block.block_height)}
                      </span>
                      <span class="text-sm text-gray-500">
                        {format_timestamp(block.date_time)}
                      </span>
                    </div>
                    <div class="mt-1 text-sm text-gray-600">
                      <span class="mr-4">TX: {block.tx_count}</span>
                      <span class="mr-4">Size: {format_bytes(block.block_size)}</span>
                      <span>Fees: {format_ada_amount(block.fees)}</span>
                    </div>
                    <div class="mt-1 text-xs text-gray-500">
                      Issuer: {String.slice(block.issuer, 0, 20)}...
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Top Issuers -->
        <div class="bg-white shadow-sm rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Top Block Issuers</h3>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <%= for issuer <- @issuer_summary do %>
                <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div class="flex-1">
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium text-gray-900">
                        {String.slice(issuer.issuer, 0, 30)}...
                      </span>
                      <span class="text-sm font-semibold text-blue-600">
                        {format_number(issuer.block_count)} blocks
                      </span>
                    </div>
                    <div class="mt-1 text-sm text-gray-600">
                      <span class="mr-4">Total TX: {format_number(issuer.total_transactions)}</span>
                      <span>Avg TX/Block: {issuer.avg_transactions}</span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Block Distribution and Hourly Stats -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Block Distribution -->
        <div class="bg-white shadow-sm rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Block Distribution by Transaction Count</h3>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <%= for dist <- @block_distribution do %>
                <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div class="flex-1">
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium text-gray-900">
                        {dist.range}
                      </span>
                      <span class="text-sm font-semibold text-green-600">
                        {format_number(dist.count)} blocks
                      </span>
                    </div>
                    <div class="mt-1 text-sm text-gray-600">
                      Avg TX: {dist.avg_tx_count}
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Hourly Block Production -->
        <div class="bg-white shadow-sm rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Hourly Block Production (Last 24h)</h3>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <%= for hour_data <- @hourly_averages do %>
                <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div class="flex-1">
                    <div class="flex items-center justify-between">
                      <span class="text-sm font-medium text-gray-900">
                        Hour {hour_data.hour}:00
                      </span>
                      <span class="text-sm font-semibold text-purple-600">
                        {format_number(hour_data.block_count)} blocks
                      </span>
                    </div>
                    <div class="mt-1 text-sm text-gray-600">
                      <span class="mr-4">
                        Total TX: {format_number(hour_data.total_transactions)}
                      </span>
                      <span>Avg TX/Block: {hour_data.avg_transactions}</span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
