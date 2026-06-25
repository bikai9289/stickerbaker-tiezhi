defmodule Sticker.Repo.Migrations.HardenPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :payment_attempt_id, references(:payment_attempts, on_delete: :nothing)
      add :amount, :integer
      add :currency, :string
      add :stripe_price_id, :string
    end

    create index(:payment_events, [:payment_attempt_id])
  end
end
