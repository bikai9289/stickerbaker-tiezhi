defmodule Sticker.Repo.Migrations.CreatePaymentWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:payment_webhook_events) do
      add :provider, :string, null: false, default: "stripe"
      add :stripe_event_id, :string, null: false
      add :event_type, :string, null: false
      add :livemode, :boolean, null: false, default: false
      add :status, :string, null: false, default: "received"
      add :error_reason, :text

      timestamps()
    end

    create unique_index(:payment_webhook_events, [:provider, :stripe_event_id])
    create index(:payment_webhook_events, [:event_type])
    create index(:payment_webhook_events, [:status])
  end
end
