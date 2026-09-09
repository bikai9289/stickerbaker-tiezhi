defmodule Sticker.BuildInfo do
  @moduledoc "Public identifiers baked into the release, never credentials."
  @revision System.get_env("BUILD_REVISION", "local")
  @built_at System.get_env("BUILD_TIME", "unknown")

  def revision, do: @revision
  def built_at, do: @built_at
end
