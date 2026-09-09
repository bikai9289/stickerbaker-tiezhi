defmodule Sticker.BuildInfo do
  @moduledoc "Public identifiers baked into the release, never credentials."

  def revision, do: System.get_env("BUILD_REVISION", "local")
  def built_at, do: System.get_env("BUILD_TIME", "unknown")
end
