defmodule Sticker.Repo.Migrations.CreatePaymentEvents do
  use Ecto.Migration

  def change do
    create table(:payment_events) do
      add :stripe_session_id, :string, null: false
      add :stripe_event_id, :string
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :credits, :integer, null: false
      add :plan, :string

      timestamps()
    end

    create unique_index(:payment_events, [:stripe_session_id])
    create index(:payment_events, [:user_id])
  end
end
