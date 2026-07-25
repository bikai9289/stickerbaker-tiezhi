defmodule Sticker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    if sentry_configured?() do
      Logger.add_backend(Sentry.LoggerBackend)
    end

    children = [
      # Start the Telemetry supervisor
      StickerWeb.Telemetry,
      # Start the Ecto repository
      Sticker.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Sticker.PubSub},
      {Task.Supervisor, name: Sticker.GenerationTaskSupervisor},
      StickerWeb.RateLimiter,
      # Start Finch
      {Finch, name: Sticker.Finch},
      # Start the Endpoint (http/https)
      StickerWeb.Endpoint
      # Start a worker by calling: Sticker.Worker.start_link(arg)
      # {Sticker.Worker, arg}
    ]

    children =
      if Application.get_env(:sticker, :start_background_workers, true) do
        children ++
          [
            Sticker.Autoplay,
            {Sticker.Embeddings.Index, []},
            Sticker.Embeddings.Worker
          ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sticker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StickerWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp sentry_configured? do
    :sentry
    |> Application.get_env(:dsn)
    |> is_binary()
  end
end
