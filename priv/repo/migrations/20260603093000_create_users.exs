defmodule Sticker.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :public_id, :string, null: false

      timestamps()
    end

    create unique_index(:users, ["lower(email)"], name: :users_email_lower_index)
    create unique_index(:users, [:public_id])
  end
end
