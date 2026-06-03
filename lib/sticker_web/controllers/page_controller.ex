defmodule StickerWeb.PageController do
  use StickerWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def contact(conn, _params) do
    render(conn, :contact)
  end

  def pricing(conn, _params) do
    render(conn, :pricing)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def terms_of_service(conn, _params) do
    render(conn, :terms_of_service)
  end
end
