defmodule Sticker.Repo.Migrations.AddSignupGuestUserIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :signup_guest_user_id, :string
    end

    create index(:users, [:signup_guest_user_id])
  end
end
