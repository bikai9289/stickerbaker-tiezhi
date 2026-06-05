defmodule Sticker.Repo.Migrations.AddEmailConfirmationToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :confirmed_at, :utc_datetime
      add :confirmation_token, :string
      add :confirmation_sent_at, :utc_datetime
      add :signup_ip, :string
    end

    create unique_index(:users, [:confirmation_token])
    create index(:users, [:signup_ip, :inserted_at])
  end
end
