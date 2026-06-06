defmodule Sticker.Repo.Migrations.AddProviderToPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :provider, :string, null: false, default: "stripe"
    end
  end
end
