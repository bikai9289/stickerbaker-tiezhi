defmodule Sticker.Repo.Migrations.AddOutputMetadataToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :output_format, :string
      add :output_content_type, :string
    end
  end
end
