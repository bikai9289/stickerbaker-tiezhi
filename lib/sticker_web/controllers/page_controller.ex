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

  def payment_and_credits(conn, _params) do
    render(conn, :payment_and_credits)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def refund_policy(conn, _params) do
    render(conn, :refund_policy)
  end

  def sitemap(conn, _params) do
    render(conn, :sitemap)
  end

  def sitemap_xml(conn, _params) do
    base_url = "https://ai-sticker-maker.com"

    paths = [
      "/",
      "/pricing",
      "/contact",
      "/payment-and-credits",
      "/privacy-policy",
      "/refund-policy",
      "/terms-of-service",
      "/search"
    ]

    urls =
      Enum.map(paths, fn path ->
        """
        <url>
          <loc>#{base_url}#{path}</loc>
        </url>
        """
      end)
      |> Enum.join("\n")

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def terms_of_service(conn, _params) do
    render(conn, :terms_of_service)
  end
end
