defmodule Sticker.LoadTelemetry do
  @moduledoc """
  Measures UI data loads without exposing user or generated-content metadata.
  """

  @event [:sticker, :ui_load]
  @allowed_metadata_keys [:limit, :page, :per_page]

  def measure(section, metadata \\ %{}, fun)
      when is_atom(section) and is_map(metadata) and is_function(fun, 0) do
    metadata =
      metadata
      |> Map.take(@allowed_metadata_keys)
      |> Map.put(:section, section)

    :telemetry.span(@event, metadata, fn ->
      result = fun.()

      stop_metadata =
        Map.merge(metadata, %{status: :ok, item_count: item_count(result)})

      {result, stop_metadata}
    end)
  end

  defp item_count(result) when is_list(result), do: length(result)
  defp item_count(%{entries: entries}) when is_list(entries), do: length(entries)
  defp item_count(_result), do: nil
end
