defmodule Sticker.Repo.Migrations.AddCreditSourceToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :credit_source, :string, null: false, default: "account"
      add :credit_owner_id, :string
    end

    create index(:predictions, [:credit_source, :credit_owner_id])

    create constraint(:predictions, :predictions_credit_source_known,
             check: "credit_source IN ('account', 'guest')"
           )
  end
end
