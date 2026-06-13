defmodule Sticker.Payments.PaymentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_events" do
    field :stripe_session_id, :string
    field :stripe_event_id, :string
    field :provider, :string, default: "stripe"
    field :provider_order_id, :string
    field :payment_attempt_id, :integer
    field :user_id, :integer
    field :credits, :integer
    field :plan, :string
    field :amount, :integer
    field :currency, :string
    field :stripe_price_id, :string
    field :refunded_at, :utc_datetime
    field :refund_event_id, :string
    field :refund_status, :string, default: "none"

    timestamps()
  end

  def changeset(payment_event, attrs) do
    payment_event
    |> cast(attrs, [
      :stripe_session_id,
      :stripe_event_id,
      :provider,
      :provider_order_id,
      :payment_attempt_id,
      :user_id,
      :credits,
      :plan,
      :amount,
      :currency,
      :stripe_price_id,
      :refunded_at,
      :refund_event_id,
      :refund_status
    ])
    |> validate_required([:stripe_session_id, :user_id, :credits])
    |> validate_inclusion(:provider, ["stripe", "creem"])
    |> validate_inclusion(:refund_status, [
      "none",
      "refunded",
      "review_required",
      "partial_refund_review"
    ])
    |> validate_number(:credits, greater_than: 0)
    |> unique_constraint(:stripe_session_id)
    |> unique_constraint(:refund_event_id)
  end
end
