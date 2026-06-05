defmodule StickerWeb.PageController do
  use StickerWeb, :controller

  alias StickerWeb.SEO, as: PageSEO

  def home(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/",
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
      PageSEO.page("/contact",
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
      PageSEO.page("/pricing",
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
      PageSEO.page("/payment-and-credits",
        title: "AI Sticker Credits - Payment and Billing Help",
        description:
          "Learn how AI Sticker Maker credits work, how checkout adds credits to your account, and where to get billing support."
      )
    )
    |> render(:payment_and_credits)
  end

  def face_to_sticker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/face-to-sticker",
        title: "Face to Sticker AI Generator",
        description:
          "Turn a portrait into a sticker-style image with the AI face to sticker generator. Upload a face, use 1 credit, and download the result."
      )
    )
    |> render(:face_to_sticker)
  end

  def custom_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/custom-sticker-maker",
        title: "Custom Sticker Maker Online",
        description:
          "Create custom stickers online from prompts or portraits. Use AI Sticker Maker to generate sticker-ready artwork and variations."
      )
    )
    |> render(:custom_sticker_maker)
  end

  def cute_sticker_ideas(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/cute-sticker-ideas",
        title: "Cute Sticker Ideas for AI Stickers",
        description:
          "Browse cute sticker ideas for AI prompts, mascots, pets, food stickers, cozy objects, and playful character sticker concepts."
      )
    )
    |> render(:cute_sticker_ideas)
  end

  def privacy_policy(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/privacy-policy",
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
      PageSEO.page("/refund-policy",
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
      PageSEO.page("/sitemap",
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
      "/face-to-sticker",
      "/custom-sticker-maker",
      "/cute-sticker-ideas",
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
      PageSEO.page("/terms-of-service",
        title: "AI Sticker Maker Terms of Service",
        description:
          "Read the AI Sticker Maker terms for AI generation, accounts, credits, payments, acceptable use, and generated sticker downloads."
      )
    )
    |> render(:terms_of_service)
  end
end
