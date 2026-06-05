defmodule Sticker.Repo.Migrations.AddFailureDetailsToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :failure_reason, :text
      add :failure_stage, :string
    end

    create index(:predictions, [:local_user_id, :status])
  end
end
