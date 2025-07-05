# Script for displaying temperature data from ClickHouse
# Run it as: mix run priv/clickhouse_repo/show_temperatures.exs

alias BlocksAnalytics.ClickhouseRepo

defmodule TemperatureDisplay do
  def run do
    IO.puts("=== Temperature Data Dashboard ===\n")

    # Show basic statistics
    show_statistics()

    # Show recent readings
    show_recent_readings()

    # Show device summary
    show_device_summary()

    # Show temperature distribution
    show_temperature_distribution()

    # Show daily averages
    show_daily_averages()
  end

  defp show_statistics do
    IO.puts("📊 Overall Statistics")
    IO.puts("=" <> String.duplicate("=", 50))

    case ClickhouseRepo.query(
           "SELECT COUNT(*) as total_records, AVG(value) as avg_temp, MIN(value) as min_temp, MAX(value) as max_temp FROM temperatures"
         ) do
      {:ok, %{rows: [[total, avg, min, max]]}} ->
        IO.puts("Total Records: #{format_number(total)}")
        IO.puts("Average Temperature: #{Float.round(avg, 2)}°C")
        IO.puts("Minimum Temperature: #{min}°C")
        IO.puts("Maximum Temperature: #{max}°C")

      {:error, error} ->
        IO.puts("Error fetching statistics: #{inspect(error)}")
    end

    IO.puts("")
  end

  defp show_recent_readings do
    IO.puts("🕐 Recent Temperature Readings")
    IO.puts("=" <> String.duplicate("=", 50))

    case ClickhouseRepo.query(
           "SELECT device_id, value, timestamp FROM temperatures ORDER BY timestamp DESC LIMIT 15"
         ) do
      {:ok, %{rows: rows}} ->
        IO.puts(format_row(["Device ID", "Temperature", "Timestamp"], [10, 12, 20]))
        IO.puts(String.duplicate("-", 50))

        Enum.each(rows, fn [device_id, value, timestamp] ->
          formatted_timestamp = format_timestamp(timestamp)
          IO.puts(format_row([device_id, "#{value}°C", formatted_timestamp], [10, 12, 20]))
        end)

      {:error, error} ->
        IO.puts("Error fetching recent readings: #{inspect(error)}")
    end

    IO.puts("")
  end

  defp show_device_summary do
    IO.puts("🌡️  Device Summary (Top 10)")
    IO.puts("=" <> String.duplicate("=", 50))

    case ClickhouseRepo.query(
           "SELECT device_id, COUNT(*) as readings_count, AVG(value) as avg_temp, MIN(value) as min_temp, MAX(value) as max_temp FROM temperatures GROUP BY device_id ORDER BY readings_count DESC LIMIT 10"
         ) do
      {:ok, %{rows: rows}} ->
        IO.puts(format_row(["Device", "Readings", "Avg Temp", "Min", "Max"], [8, 10, 10, 6, 6]))
        IO.puts(String.duplicate("-", 50))

        Enum.each(rows, fn [device_id, count, avg, min, max] ->
          IO.puts(
            format_row(
              [
                device_id,
                format_number(count),
                "#{Float.round(avg, 1)}°C",
                "#{min}°C",
                "#{max}°C"
              ],
              [8, 10, 10, 6, 6]
            )
          )
        end)

      {:error, error} ->
        IO.puts("Error fetching device summary: #{inspect(error)}")
    end

    IO.puts("")
  end

  defp show_temperature_distribution do
    IO.puts("📈 Temperature Distribution")
    IO.puts("=" <> String.duplicate("=", 50))

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
        IO.puts(format_row(["Temperature Range", "Count", "Percentage"], [20, 10, 12]))
        IO.puts(String.duplicate("-", 50))

        total = Enum.sum(Enum.map(rows, fn [_, count] -> count end))

        Enum.each(rows, fn [range, count] ->
          percentage = Float.round(count / total * 100, 1)
          IO.puts(format_row([range, format_number(count), "#{percentage}%"], [20, 10, 12]))
        end)

      {:error, error} ->
        IO.puts("Error fetching temperature distribution: #{inspect(error)}")
    end

    IO.puts("")
  end

  defp show_daily_averages do
    IO.puts("📅 Daily Temperature Averages (Last 10 Days)")
    IO.puts("=" <> String.duplicate("=", 50))

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
        IO.puts(format_row(["Date", "Readings", "Avg", "Min", "Max"], [12, 10, 8, 6, 6]))
        IO.puts(String.duplicate("-", 50))

        Enum.each(rows, fn [date, readings, avg, min, max] ->
          IO.puts(
            format_row(
              [
                date,
                format_number(readings),
                "#{Float.round(avg, 1)}°C",
                "#{min}°C",
                "#{max}°C"
              ],
              [12, 10, 8, 6, 6]
            )
          )
        end)

      {:error, error} ->
        IO.puts("Error fetching daily averages: #{inspect(error)}")
    end

    IO.puts("")
  end

  defp format_row(items, widths) do
    items
    |> Enum.zip(widths)
    |> Enum.map(fn {item, width} -> String.pad_trailing(to_string(item), width) end)
    |> Enum.join(" ")
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
      {:ok, dt} -> format_timestamp(dt)
      {:error, _} -> timestamp
    end
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    "#{dt.year}-#{String.pad_leading(to_string(dt.month), 2, "0")}-#{String.pad_leading(to_string(dt.day), 2, "0")} #{String.pad_leading(to_string(dt.hour), 2, "0")}:#{String.pad_leading(to_string(dt.minute), 2, "0")}"
  end

  defp format_timestamp(timestamp) do
    to_string(timestamp)
  end
end

# Run the display
TemperatureDisplay.run()
