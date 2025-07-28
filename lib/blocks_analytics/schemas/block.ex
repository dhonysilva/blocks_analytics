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
          issuer_output: String.t(),
          issuer_proof: String.t(),
          issuer_count: integer(),
          issuer_kes_period: integer(),
          issuer_kes_verification_key: String.t(),
          issuer_sigma: String.t(),
          issuer_verification_key: String.t(),
          issuer_vrf_verification_key: String.t(),
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
    field(:issuer_output, :string)
    field(:issuer_proof, :string)
    field(:issuer_count, Ch, type: "UInt32")
    field(:issuer_kes_period, Ch, type: "UInt32")
    field(:issuer_kes_verification_key, :string)
    field(:issuer_sigma, :string)
    field(:issuer_verification_key, :string)
    field(:issuer_vrf_verification_key, :string)
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
      :issuer_output,
      :issuer_proof,
      :issuer_count,
      :issuer_kes_period,
      :issuer_kes_verification_key,
      :issuer_sigma,
      :issuer_verification_key,
      :issuer_vrf_verification_key,
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
      :issuer_output,
      :issuer_proof,
      :issuer_count,
      :issuer_kes_period,
      :issuer_kes_verification_key,
      :issuer_sigma,
      :issuer_verification_key,
      :issuer_vrf_verification_key,
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
