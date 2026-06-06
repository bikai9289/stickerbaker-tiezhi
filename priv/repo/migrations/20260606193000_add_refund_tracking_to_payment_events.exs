defmodule Sticker.Repo.Migrations.AddRefundTrackingToPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :provider_order_id, :string
      add :refunded_at, :utc_datetime
      add :refund_event_id, :string
    end

    create index(:payment_events, [:provider_order_id])
    create unique_index(:payment_events, [:refund_event_id])
  end
end
