defmodule Sticker.Payments.PaymentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_events" do
    field :stripe_session_id, :string
    field :stripe_event_id, :string
    field :user_id, :integer
    field :credits, :integer
    field :plan, :string

    timestamps()
  end

  def changeset(payment_event, attrs) do
    payment_event
    |> cast(attrs, [:stripe_session_id, :stripe_event_id, :user_id, :credits, :plan])
    |> validate_required([:stripe_session_id, :user_id, :credits])
    |> validate_number(:credits, greater_than: 0)
    |> unique_constraint(:stripe_session_id)
  end
end
