# Script for populating the ClickHouse temperature table with 1 million rows
# Run it as: mix run priv/clickhouse_repo/temperature_seed.exs

alias BlocksAnalytics.ClickhouseRepo

defmodule TemperatureSeed do
  @batch_size 10_000
  @total_rows 1_000_000
  @num_devices 500
  @start_date ~D[2023-01-01]
  @end_date ~D[2024-12-31]

  def run do
    IO.puts("Starting temperature data seeding...")
    IO.puts("Target: #{@total_rows} rows")
    IO.puts("Batch size: #{@batch_size}")
    IO.puts("Number of devices: #{@num_devices}")
    IO.puts("Date range: #{@start_date} to #{@end_date}")

    # Calculate total number of batches
    total_batches = div(@total_rows, @batch_size)

    # Generate and insert data in batches
    Enum.each(1..total_batches, fn batch_num ->
      batch_data = generate_batch_data(batch_num)
      insert_batch(batch_data)

      if rem(batch_num, 10) == 0 do
        progress = (batch_num / total_batches * 100) |> Float.round(1)
        IO.puts("Progress: #{progress}% (#{batch_num * @batch_size} rows inserted)")
      end
    end)

    IO.puts("Temperature data seeding completed!")
  end

  defp generate_batch_data(batch_num) do
    # Generate deterministic but varied data for each batch
    :rand.seed(:exsplus, {batch_num, 42, 123})

    Enum.map(1..@batch_size, fn _ ->
      device_id = :rand.uniform(@num_devices)
      timestamp = generate_random_timestamp()
      temperature = generate_realistic_temperature(timestamp)

      %{
        device_id: device_id,
        value: temperature,
        timestamp: timestamp
      }
    end)
  end

  defp generate_random_timestamp do
    start_days = Date.diff(@start_date, ~D[1970-01-01])
    end_days = Date.diff(@end_date, ~D[1970-01-01])

    random_days = :rand.uniform(end_days - start_days) + start_days
    # 0 to 86399 seconds in a day
    random_seconds = :rand.uniform(86400) - 1

    base_date = Date.add(~D[1970-01-01], random_days)
    {:ok, datetime} = NaiveDateTime.new(base_date, ~T[00:00:00])
    NaiveDateTime.add(datetime, random_seconds, :second)
  end

  defp generate_realistic_temperature(timestamp) do
    # Generate temperature based on season and time of day
    month = timestamp.month
    hour = timestamp.hour

    # Base temperature by season (Celsius)
    seasonal_base =
      case month do
        # Winter
        month when month in [12, 1, 2] -> -5
        # Spring
        month when month in [3, 4, 5] -> 10
        # Summer
        month when month in [6, 7, 8] -> 25
        # Fall
        month when month in [9, 10, 11] -> 12
      end

    # Daily temperature variation
    daily_variation =
      case hour do
        # Night
        hour when hour in [0, 1, 2, 3, 4, 5] -> -8
        # Morning
        hour when hour in [6, 7, 8, 9] -> -3
        # Midday
        hour when hour in [10, 11, 12, 13, 14] -> 5
        # Afternoon
        hour when hour in [15, 16, 17, 18] -> 3
        # Evening
        hour when hour in [19, 20, 21, 22, 23] -> -2
      end

    # Add some random variation (-5 to +5 degrees)
    random_variation = :rand.uniform(11) - 6

    # Calculate final temperature
    temperature = seasonal_base + daily_variation + random_variation

    # Ensure reasonable bounds (-30 to 50 Celsius)
    temperature
    |> max(-30)
    |> min(50)
  end

  defp insert_batch(batch_data) do
    # Convert to the format expected by ClickHouse
    values =
      Enum.map(batch_data, fn row ->
        "(#{row.device_id}, #{row.value}, '#{NaiveDateTime.to_string(row.timestamp)}')"
      end)

    values_string = Enum.join(values, ",\n")

    sql = """
    INSERT INTO temperatures (device_id, value, timestamp) VALUES
    #{values_string}
    """

    case ClickhouseRepo.query(sql) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        IO.puts("Error inserting batch: #{inspect(error)}")
        raise "Failed to insert batch"
    end
  end
end

# Run the seeding
TemperatureSeed.run()
