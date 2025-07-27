defmodule BlocksAnalytics.Schemas.Block do
  @moduledoc """
  ClickHouse schema for Cardano blocks
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          block_id: String.t(),
          block_size: integer(),
          block_height: integer(),
          block_slot: integer(),
          issuer: String.t(),
          tx_count: integer(),
          ada_output: integer(),
          fees: integer(),
          date_time: NaiveDateTime.t(),
          inserted_at: NaiveDateTime.t(),
          __meta__: Ecto.Schema.Metadata.t()
        }

  @primary_key false
  schema "blocks" do
    field(:block_id, :string)
    field(:block_size, Ch, type: "UInt32")
    field(:block_height, Ch, type: "UInt64")
    field(:block_slot, Ch, type: "UInt64")
    field(:issuer, :string)
    field(:tx_count, Ch, type: "UInt32")
    field(:ada_output, Ch, type: "UInt32")
    field(:fees, Ch, type: "UInt32")
    field(:date_time, Ch, type: "DateTime")
    field(:inserted_at, Ch, type: "DateTime")
  end

  def changeset(block, attrs) do
    block
    |> Ecto.Changeset.cast(attrs, [
      :block_id,
      :block_size,
      :block_height,
      :block_slot,
      :issuer,
      :tx_count,
      :ada_output,
      :fees,
      :date_time,
      :inserted_at
    ])
    |> Ecto.Changeset.validate_required([
      :block_id,
      :block_size,
      :block_height,
      :block_slot,
      :issuer,
      :tx_count,
      :ada_output,
      :fees,
      :date_time
    ])
    |> Ecto.Changeset.put_change(
      :inserted_at,
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
    |> truncate_datetime_fields()
  end

  defp truncate_datetime_fields(changeset) do
    changeset
    |> truncate_datetime_field(:date_time)
    |> truncate_datetime_field(:inserted_at)
  end

  defp truncate_datetime_field(changeset, field) do
    case Ecto.Changeset.get_change(changeset, field) do
      %NaiveDateTime{} = datetime ->
        Ecto.Changeset.put_change(changeset, field, NaiveDateTime.truncate(datetime, :second))

      _ ->
        changeset
    end
  end
end
