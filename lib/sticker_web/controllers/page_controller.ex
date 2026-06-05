defmodule StickerWeb.PageController do
  use StickerWeb, :controller

  alias StickerWeb.SEO

  def home(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/",
        title: "AI Sticker Maker - Free AI Sticker Generator Online",
        description:
          "Create custom AI stickers from text prompts or portraits. Start with 3 free credits and download sticker-ready designs online."
      )
    )
    |> render(:home, layout: false)
  end

  def contact(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/contact",
        title: "Contact AI Sticker Maker Support",
        description:
          "Contact AI Sticker Maker for help with accounts, credits, billing, sticker generation, abuse reports, and business requests."
      )
    )
    |> render(:contact)
  end

  def pricing(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/pricing",
        title: "AI Sticker Maker Pricing - Buy Sticker Credits",
        description:
          "View AI Sticker Maker pricing, free starter credits, and paid credit packs for text-to-sticker and face-to-sticker generation."
      )
    )
    |> render(:pricing)
  end

  def payment_and_credits(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/payment-and-credits",
        title: "AI Sticker Credits - Payment and Billing Help",
        description:
          "Learn how AI Sticker Maker credits work, how checkout adds credits to your account, and where to get billing support."
      )
    )
    |> render(:payment_and_credits)
  end

  def privacy_policy(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/privacy-policy",
        title: "AI Sticker Maker Privacy Policy",
        description:
          "Read the AI Sticker Maker privacy policy for account data, uploaded images, generated stickers, payments, and support requests."
      )
    )
    |> render(:privacy_policy)
  end

  def refund_policy(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/refund-policy",
        title: "AI Sticker Maker Refund Policy",
        description:
          "Review the AI Sticker Maker refund policy for unused credits, completed sticker generations, billing issues, and support contact."
      )
    )
    |> render(:refund_policy)
  end

  def sitemap(conn, _params) do
    conn
    |> SEO.assign(
      SEO.page("/sitemap",
        title: "AI Sticker Maker Sitemap",
        description:
          "Find AI Sticker Maker product, pricing, support, payment, privacy, refund, and terms pages from one sitemap."
      )
    )
    |> render(:sitemap)
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
    conn
    |> SEO.assign(
      SEO.page("/terms-of-service",
        title: "AI Sticker Maker Terms of Service",
        description:
          "Read the AI Sticker Maker terms for AI generation, accounts, credits, payments, acceptable use, and generated sticker downloads."
      )
    )
    |> render(:terms_of_service)
  end
end
