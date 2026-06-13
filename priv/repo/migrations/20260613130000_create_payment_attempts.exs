defmodule Sticker.Repo.Migrations.CreatePaymentAttempts do
  use Ecto.Migration

  def change do
    create table(:payment_attempts) do
      add :provider, :string, null: false, default: "stripe"
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :plan, :string, null: false
      add :credits, :integer, null: false
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :status, :string, null: false, default: "created"
      add :stripe_price_id, :string, null: false
      add :stripe_session_id, :string
      add :provider_order_id, :string
      add :checkout_url, :text
      add :failure_reason, :text

      timestamps()
    end

    create index(:payment_attempts, [:user_id])
    create index(:payment_attempts, [:status])
    create unique_index(:payment_attempts, [:stripe_session_id])
  end
end
