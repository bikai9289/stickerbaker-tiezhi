defmodule Sticker.Repo.Migrations.AddCreditsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :credits, :integer, null: false, default: 3
    end
  end
end
