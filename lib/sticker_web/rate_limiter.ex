defmodule StickerWeb.RateLimiter do
  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :bag, read_concurrency: true])
    {:ok, %{}}
  end

  def check(key, limit, window_seconds)
      when is_binary(key) and is_integer(limit) and is_integer(window_seconds) do
    now = System.system_time(:second)
    window_started_at = now - window_seconds

    prune(key, window_started_at)

    count =
      @table
      |> :ets.lookup(key)
      |> Enum.count(fn {_key, timestamp} -> timestamp >= window_started_at end)

    if count >= limit do
      {:error, :rate_limited}
    else
      :ets.insert(@table, {key, now})
      :ok
    end
  end

  defp prune(key, window_started_at) do
    @table
    |> :ets.lookup(key)
    |> Enum.each(fn
      {^key, timestamp} when timestamp < window_started_at ->
        :ets.delete_object(@table, {key, timestamp})

      _entry ->
        :ok
    end)
  end
end
