defmodule Sticker.Repo.Migrations.AddUploadSourceToPredictions do
  use Ecto.Migration

  def change do
    alter table(:predictions) do
      add :source_image_url, :string
      add :source_image_content_type, :string
    end
  end
end
