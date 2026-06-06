defmodule Sticker.Payments.PaymentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_events" do
    field :stripe_session_id, :string
    field :stripe_event_id, :string
    field :provider, :string, default: "stripe"
    field :provider_order_id, :string
    field :user_id, :integer
    field :credits, :integer
    field :plan, :string
    field :refunded_at, :utc_datetime
    field :refund_event_id, :string

    timestamps()
  end

  def changeset(payment_event, attrs) do
    payment_event
    |> cast(attrs, [
      :stripe_session_id,
      :stripe_event_id,
      :provider,
      :provider_order_id,
      :user_id,
      :credits,
      :plan,
      :refunded_at,
      :refund_event_id
    ])
    |> validate_required([:stripe_session_id, :user_id, :credits])
    |> validate_inclusion(:provider, ["stripe", "creem"])
    |> validate_number(:credits, greater_than: 0)
    |> unique_constraint(:stripe_session_id)
    |> unique_constraint(:refund_event_id)
  end
end
