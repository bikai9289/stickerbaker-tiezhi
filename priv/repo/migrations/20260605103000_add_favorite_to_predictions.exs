defmodule Sticker.Repo.Migrations.AddFavoriteToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :is_favorite, :boolean, null: false, default: false
    end
  end
end
