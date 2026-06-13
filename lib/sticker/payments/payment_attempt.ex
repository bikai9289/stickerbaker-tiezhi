defmodule Sticker.Payments.PaymentAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["created", "open", "completed", "credited", "canceled", "expired", "failed"]

  schema "payment_attempts" do
    field :provider, :string, default: "stripe"
    field :user_id, :integer
    field :plan, :string
    field :credits, :integer
    field :amount, :integer
    field :currency, :string
    field :status, :string, default: "created"
    field :stripe_price_id, :string
    field :stripe_session_id, :string
    field :provider_order_id, :string
    field :checkout_url, :string
    field :failure_reason, :string

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :provider,
      :user_id,
      :plan,
      :credits,
      :amount,
      :currency,
      :status,
      :stripe_price_id,
      :stripe_session_id,
      :provider_order_id,
      :checkout_url,
      :failure_reason
    ])
    |> validate_required([
      :provider,
      :user_id,
      :plan,
      :credits,
      :amount,
      :currency,
      :status,
      :stripe_price_id
    ])
    |> validate_inclusion(:provider, ["stripe"])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:credits, greater_than: 0)
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint(:stripe_session_id)
  end
end
