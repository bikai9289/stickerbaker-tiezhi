defmodule Sticker.Payments.PaymentWebhookEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_webhook_events" do
    field :provider, :string, default: "stripe"
    field :stripe_event_id, :string
    field :event_type, :string
    field :livemode, :boolean, default: false
    field :status, :string, default: "received"
    field :error_reason, :string

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:provider, :stripe_event_id, :event_type, :livemode, :status, :error_reason])
    |> validate_required([:provider, :stripe_event_id, :event_type, :livemode, :status])
    |> validate_inclusion(:provider, ["stripe"])
    |> validate_inclusion(:status, ["received", "processed", "ignored", "failed"])
    |> unique_constraint(:stripe_event_id,
      name: :payment_webhook_events_provider_stripe_event_id_index
    )
  end
end
