defmodule Sticker.Repo.Migrations.MakeFaceStickersPrivate do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE predictions
    SET is_featured = NULL
    WHERE model = 'face-to-sticker' AND is_featured = 'true'
    """)
  end

  def down do
    :ok
  end
end
