defmodule Sticker.Repo.Migrations.OptimizeHistoryQueries do
  use Ecto.Migration

  def change do
    create index(:predictions, [:local_user_id, :inserted_at])
    create index(:predictions, [:local_user_id, :is_favorite, :updated_at])
    create index(:payment_events, [:user_id, :inserted_at])
    create index(:payment_attempts, [:user_id, :inserted_at])
  end
end
