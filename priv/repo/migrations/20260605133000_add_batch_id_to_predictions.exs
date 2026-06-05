defmodule Sticker.Repo.Migrations.AddBatchIdToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :batch_id, :string
    end

    create index(:predictions, [:local_user_id, :batch_id])
  end
end
