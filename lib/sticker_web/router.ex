defmodule StickerWeb.Router do
  use StickerWeb, :router
  import StickerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {StickerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
  end

  pipeline :admins_only do
    plug :admin_basic_auth
  end

  defp admin_basic_auth(conn, _opts) do
    username = System.fetch_env!("ADMIN_USERNAME")
    password = System.fetch_env!("ADMIN_PASSWORD")

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  scope "/admin", StickerWeb do
    pipe_through [:browser, :admins_only]
    import Phoenix.LiveDashboard.Router

    live "/", AdminLive, :index
    live "/users", AdminUsersLive, :index
    live "/payments", AdminPaymentsLive, :index
    live_dashboard "/dashboard", metrics: StickerWeb.Telemetry
  end

  scope "/", StickerWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/account", AccountLive, :index
    live "/sticker/:id", ShowLive, :show
    get "/stickers/download", StickerBatchDownloadController, :show
    get "/sticker/:id/download", StickerDownloadController, :show
    live "/stickers", HistoryLive, :index
    live "/stickers/batches/:id", BatchLive, :show
    live "/search", SearchLive, :index

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete

    get "/pricing", PageController, :pricing
    post "/checkout", CheckoutController, :create
    get "/face-to-sticker", PageController, :face_to_sticker
    get "/custom-sticker-maker", PageController, :custom_sticker_maker
    get "/cute-sticker-ideas", PageController, :cute_sticker_ideas
    get "/sticker-maker-online", PageController, :sticker_maker_online
    get "/ai-avatar-sticker", PageController, :ai_avatar_sticker
    get "/kawaii-sticker-maker", PageController, :kawaii_sticker_maker
    get "/transparent-sticker-maker", PageController, :transparent_sticker_maker
    get "/contact", PageController, :contact
    get "/payment-and-credits", PageController, :payment_and_credits
    get "/privacy-policy", PageController, :privacy_policy
    get "/refund-policy", PageController, :refund_policy
    get "/sitemap", PageController, :sitemap
    get "/sitemap.xml", PageController, :sitemap_xml
    get "/terms-of-service", PageController, :terms_of_service
  end

  # Other scopes may use custom stacks.
  scope "/api", StickerWeb do
    pipe_through :api
    post "/session", SessionController, :set
  end

  scope "/webhooks", StickerWeb do
    post "/replicate", ReplicateWebhookController, :handle
    post "/stripe", StripeWebhookController, :handle
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sticker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).

    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
