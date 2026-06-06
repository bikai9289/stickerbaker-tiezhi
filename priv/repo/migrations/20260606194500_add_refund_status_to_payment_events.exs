defmodule Sticker.Repo.Migrations.AddRefundStatusToPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :refund_status, :string, null: false, default: "none"
    end

    create index(:payment_events, [:refund_status])
  end
end
