defmodule BlocksAnalyticsWeb.TemperatureLive do
  use BlocksAnalyticsWeb, :live_view

  alias BlocksAnalytics.ClickhouseRepo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Schedule periodic updates every 30 seconds
      :timer.send_interval(30_000, self(), :update_data)
    end

    socket = load_temperature_data(socket)
    {:ok, socket}
  end

  @impl true
  def handle_info(:update_data, socket) do
    socket = load_temperature_data(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket = load_temperature_data(socket)
    {:noreply, socket}
  end

  defp load_temperature_data(socket) do
    statistics = get_statistics()
    recent_readings = get_recent_readings()
    device_summary = get_device_summary()
    temperature_distribution = get_temperature_distribution()
    daily_averages = get_daily_averages()

    socket
    |> assign(:statistics, statistics)
    |> assign(:recent_readings, recent_readings)
    |> assign(:device_summary, device_summary)
    |> assign(:temperature_distribution, temperature_distribution)
    |> assign(:daily_averages, daily_averages)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp get_statistics do
    case ClickhouseRepo.query(
           "SELECT COUNT(*) as total_records, AVG(value) as avg_temp, MIN(value) as min_temp, MAX(value) as max_temp FROM temperatures"
         ) do
      {:ok, %{rows: [[total, avg, min, max]]}} ->
        %{
          total_records: total,
          avg_temp: Float.round(avg, 2),
          min_temp: min,
          max_temp: max
        }

      {:error, _error} ->
        %{total_records: 0, avg_temp: 0, min_temp: 0, max_temp: 0}
    end
  end

  defp get_recent_readings do
    case ClickhouseRepo.query(
           "SELECT device_id, value, timestamp FROM temperatures ORDER BY timestamp DESC LIMIT 15"
         ) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [device_id, value, timestamp] ->
          %{
            device_id: device_id,
            value: value,
            timestamp: timestamp
          }
        end)

      {:error, _error} ->
        []
    end
  end

  defp get_device_summary do
    case ClickhouseRepo.query(
           "SELECT device_id, COUNT(*) as readings_count, AVG(value) as avg_temp, MIN(value) as min_temp, MAX(value) as max_temp FROM temperatures GROUP BY device_id ORDER BY readings_count DESC LIMIT 10"
         ) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [device_id, count, avg, min, max] ->
          %{
            device_id: device_id,
            readings_count: count,
            avg_temp: Float.round(avg, 1),
            min_temp: min,
            max_temp: max
          }
        end)

      {:error, _error} ->
        []
    end
  end

  defp get_temperature_distribution do
    case ClickhouseRepo.query("""
         SELECT
           CASE
             WHEN value < -10 THEN 'Very Cold (<-10°C)'
             WHEN value < 0 THEN 'Cold (-10°C to 0°C)'
             WHEN value < 10 THEN 'Cool (0°C to 10°C)'
             WHEN value < 20 THEN 'Mild (10°C to 20°C)'
             WHEN value < 30 THEN 'Warm (20°C to 30°C)'
             ELSE 'Hot (>30°C)'
           END as temp_range,
           COUNT(*) as count
         FROM temperatures
         GROUP BY temp_range
         ORDER BY count DESC
         """) do
      {:ok, %{rows: rows}} ->
        total = Enum.sum(Enum.map(rows, fn [_, count] -> count end))

        Enum.map(rows, fn [range, count] ->
          %{
            range: range,
            count: count,
            percentage: Float.round(count / total * 100, 1)
          }
        end)

      {:error, _error} ->
        []
    end
  end

  defp get_daily_averages do
    case ClickhouseRepo.query("""
         SELECT
           toDate(timestamp) as date,
           COUNT(*) as readings,
           AVG(value) as avg_temp,
           MIN(value) as min_temp,
           MAX(value) as max_temp
         FROM temperatures
         WHERE timestamp >= now() - INTERVAL 10 DAY
         GROUP BY date
         ORDER BY date DESC
         LIMIT 10
         """) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [date, readings, avg, min, max] ->
          %{
            date: date,
            readings: readings,
            avg_temp: Float.round(avg, 1),
            min_temp: min,
            max_temp: max
          }
        end)

      {:error, _error} ->
        []
    end
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, dt} ->
        "#{dt.year}-#{String.pad_leading(to_string(dt.month), 2, "0")}-#{String.pad_leading(to_string(dt.day), 2, "0")} #{String.pad_leading(to_string(dt.hour), 2, "0")}:#{String.pad_leading(to_string(dt.minute), 2, "0")}"

      {:error, _} ->
        timestamp
    end
  end

  defp format_timestamp(timestamp), do: to_string(timestamp)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900 mb-2">🌡️ Temperature Data Dashboard</h1>
        <div class="flex items-center justify-between">
          <p class="text-gray-600">
            Last updated: {if @last_updated,
              do: Calendar.strftime(@last_updated, "%Y-%m-%d %H:%M:%S UTC"),
              else: "Loading..."}
          </p>
          <button
            phx-click="refresh"
            class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
          >
            Refresh Data
          </button>
        </div>
      </div>
      
    <!-- Statistics Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                  <span class="text-white font-semibold">📊</span>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">Total Records</dt>
                  <dd class="text-lg font-medium text-gray-900">
                    {format_number(@statistics.total_records)}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center">
                  <span class="text-white font-semibold">📈</span>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">Average Temperature</dt>
                  <dd class="text-lg font-medium text-gray-900">
                    {@statistics.avg_temp}°C
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-blue-300 rounded-full flex items-center justify-center">
                  <span class="text-white font-semibold">❄️</span>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">Minimum Temperature</dt>
                  <dd class="text-lg font-medium text-gray-900">
                    {@statistics.min_temp}°C
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <div class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center">
                  <span class="text-white font-semibold">🔥</span>
                </div>
              </div>
              <div class="ml-5 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">Maximum Temperature</dt>
                  <dd class="text-lg font-medium text-gray-900">
                    {@statistics.max_temp}°C
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Main Content Grid -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Recent Readings -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">🕐 Recent Temperature Readings</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Device ID
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Temperature
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Timestamp
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for reading <- @recent_readings do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {reading.device_id}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <span class={temp_color_class(reading.value)}>
                        {reading.value}°C
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {format_timestamp(reading.timestamp)}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
        
    <!-- Device Summary -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">🌡️ Device Summary (Top 10)</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Device
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Readings
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Avg Temp
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Range
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for device <- @device_summary do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {device.device_id}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {format_number(device.readings_count)}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <span class={temp_color_class(device.avg_temp)}>
                        {device.avg_temp}°C
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {device.min_temp}°C - {device.max_temp}°C
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
        
    <!-- Temperature Distribution -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">📈 Temperature Distribution</h2>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <%= for dist <- @temperature_distribution do %>
                <div class="flex items-center justify-between">
                  <div class="flex-1">
                    <div class="flex items-center justify-between mb-1">
                      <span class="text-sm font-medium text-gray-700">{dist.range}</span>
                      <span class="text-sm text-gray-500">
                        {format_number(dist.count)} ({dist.percentage}%)
                      </span>
                    </div>
                    <div class="bg-gray-200 rounded-full h-2">
                      <div class="bg-blue-500 h-2 rounded-full" style={"width: #{dist.percentage}%"}>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        
    <!-- Daily Averages -->
        <div class="bg-white shadow rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-xl font-semibold text-gray-900">📅 Daily Temperature Averages</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Date
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Readings
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Avg Temp
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Range
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for day <- @daily_averages do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      {day.date}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {format_number(day.readings)}
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <span class={temp_color_class(day.avg_temp)}>
                        {day.avg_temp}°C
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {day.min_temp}°C - {day.max_temp}°C
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp temp_color_class(temp) when temp < -10, do: "text-blue-600 font-semibold"
  defp temp_color_class(temp) when temp < 0, do: "text-blue-500"
  defp temp_color_class(temp) when temp < 10, do: "text-green-600"
  defp temp_color_class(temp) when temp < 20, do: "text-green-500"
  defp temp_color_class(temp) when temp < 30, do: "text-yellow-500"
  defp temp_color_class(_temp), do: "text-red-500 font-semibold"
end
