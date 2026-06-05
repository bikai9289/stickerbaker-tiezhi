defmodule Sticker.Repo.Migrations.AddCreditRefundedToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :credit_refunded, :boolean, null: false, default: false
    end
  end
end
