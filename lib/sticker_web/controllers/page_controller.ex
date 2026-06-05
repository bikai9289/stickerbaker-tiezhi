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
    |> assign_structured_data("/face-to-sticker", "Face to Sticker AI Generator",
      steps: [
        "Sign in so your free or paid credits can be checked before generation.",
        "Upload a clear portrait with one visible face and good lighting.",
        "Add an optional style prompt, then let the face to sticker workflow generate automatically.",
        "Open history to download PNG or WebP, save favorites, or create another version."
      ],
      faqs: [
        {"What makes a good face to sticker upload?",
         "A bright portrait with one clear face, natural expression, and minimal blur works best."},
        {"Does face to sticker use credits?",
         "Yes. Each portrait generation uses 1 credit after login, and failed generations refund the credit."},
        {"Can I retry a failed face sticker?",
         "Yes. New upload-based face stickers save a private source image so failed generations can be retried from history."}
      ]
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
    |> assign_structured_data("/custom-sticker-maker", "Custom Sticker Maker Online",
      steps: [
        "Write a short prompt with the subject, mood, and sticker style.",
        "Generate one sticker or add up to 5 prompts on separate lines for a small batch.",
        "Review completed, failed, and processing results in sticker history.",
        "Download original, PNG, or WebP files depending on your design workflow."
      ],
      faqs: [
        {"How do I write a custom sticker prompt?",
         "Start with the subject, then add mood, style, border, and simple background details."},
        {"Can I make custom sticker batches?",
         "Yes. Add one prompt per line and the history page groups the results into a batch."},
        {"What format should I download?",
         "Use PNG for editing compatibility, WebP for smaller web assets, or original to keep the source format."}
      ]
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
    |> assign_structured_data("/cute-sticker-ideas", "Cute Sticker Ideas for AI Stickers",
      steps: [
        "Pick a simple subject such as an animal, snack, flower, object, or mascot.",
        "Choose one emotion like sleepy, happy, proud, surprised, or cozy.",
        "Add a sticker style phrase such as clean border, simple background, or cute icon style.",
        "Generate variations and save the strongest prompt ideas in history."
      ],
      faqs: [
        {"What are easy cute sticker ideas?",
         "Sleepy animals, smiling snacks, tiny household objects, cozy weather icons, and simple mascots are easy starts."},
        {"How do I make a sticker set?",
         "Keep the style consistent and write one prompt per line for a small batch."},
        {"Can I search sticker ideas?",
         "Yes. Use the sticker search page to browse generated examples and reuse prompt directions."}
      ]
    )
    |> render(:cute_sticker_ideas)
  end

  def sticker_maker_online(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/sticker-maker-online",
        title: "Sticker Maker Online - Create AI Stickers",
        description:
          "Use an online sticker maker to create AI stickers from prompts or portraits, manage credits, download files, and build sticker batches."
      )
    )
    |> assign_structured_data("/sticker-maker-online", "Sticker Maker Online",
      steps: [
        "Open the generator and enter a prompt or upload a portrait.",
        "Check credits before generation starts automatically.",
        "Track progress in history, including processing, failed, canceled, and completed stickers.",
        "Download individual stickers or batch ZIP files in original, PNG, or WebP format."
      ],
      faqs: [
        {"What can I make with the online sticker maker?",
         "You can create prompt-based stickers, portrait stickers, avatar stickers, mascot ideas, and small batches."},
        {"Can I manage generated stickers?",
         "Yes. History supports search, filters, favorites, delete, retry, cancel, and batch detail pages."},
        {"Is this online sticker maker credit based?",
         "Yes. New users start with free credits and each generation uses 1 credit."}
      ]
    )
    |> render(:sticker_maker_online)
  end

  def ai_avatar_sticker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/ai-avatar-sticker",
        title: "AI Avatar Sticker Generator",
        description:
          "Create AI avatar stickers from portraits or character prompts. Generate profile-ready sticker art with history, retry, and download options."
      )
    )
    |> assign_structured_data("/ai-avatar-sticker", "AI Avatar Sticker Generator",
      steps: [
        "Upload a clear portrait or write a character avatar prompt.",
        "Use simple style details such as clean border, expressive face, and profile-ready sticker.",
        "Generate, save favorites, and compare variations in history.",
        "Download PNG for editing or WebP for smaller profile and web assets."
      ],
      faqs: [
        {"What is an AI avatar sticker?",
         "An AI avatar sticker is a profile-style sticker generated from a portrait or character prompt."},
        {"Can I make avatar stickers from text?",
         "Yes. Use character prompts for creator avatars, mascots, team icons, or reaction stickers."},
        {"Where do finished avatar stickers go?",
         "Completed results appear in your sticker history with download, favorite, and regenerate options."}
      ]
    )
    |> render(:ai_avatar_sticker)
  end

  def kawaii_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/kawaii-sticker-maker",
        title: "Kawaii Sticker Maker for Cute AI Stickers",
        description:
          "Make kawaii AI stickers with cute prompt ideas for animals, food, mascots, cozy objects, and playful character stickers."
      )
    )
    |> assign_structured_data("/kawaii-sticker-maker", "Kawaii Sticker Maker",
      steps: [
        "Choose one cute subject, such as a kitten, strawberry, coffee cup, cloud, or flower.",
        "Add a soft emotion and small accessory to make the sticker feel expressive.",
        "Keep the prompt simple and repeat the same style for batches.",
        "Regenerate favorites with new poses, expressions, colors, or accessories."
      ],
      faqs: [
        {"What makes a sticker kawaii?",
         "A simple subject, soft expression, rounded details, gentle colors, and a clear sticker silhouette help."},
        {"Can I make a kawaii sticker batch?",
         "Yes. Add several related prompts on separate lines and download the completed batch."},
        {"What prompts work well?",
         "Try a tiny strawberry waving, sleepy kitten with moon pillow, smiling cloud, or happy coffee cup."}
      ]
    )
    |> render(:kawaii_sticker_maker)
  end

  def transparent_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/transparent-sticker-maker",
        title: "Transparent Sticker Maker with PNG and WebP Downloads",
        description:
          "Generate sticker-style images and download PNG or WebP files. Learn when to use transparent-style sticker outputs for editing and web use."
      )
    )
    |> assign_structured_data("/transparent-sticker-maker", "Transparent Sticker Maker",
      steps: [
        "Generate a sticker with a clear subject and simple background direction.",
        "Open the completed sticker detail or history page.",
        "Choose PNG for editing compatibility or WebP for smaller web files.",
        "For multiple results, select completed stickers and download a ZIP in your preferred format."
      ],
      faqs: [
        {"Does the generator create transparent sticker files?",
         "The app creates sticker-style images and supports PNG or WebP delivery for completed stickers."},
        {"Should I download PNG or WebP?",
         "PNG is best for editing and compatibility, while WebP is smaller for websites and previews."},
        {"Can I download multiple stickers at once?",
         "Yes. Select completed stickers in history and download a batch ZIP as original, PNG, or WebP."}
      ]
    )
    |> render(:transparent_sticker_maker)
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
      "/sticker-maker-online",
      "/ai-avatar-sticker",
      "/kawaii-sticker-maker",
      "/transparent-sticker-maker",
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

  defp assign_structured_data(conn, path, name, opts) do
    assign(conn, :structured_data, [
      breadcrumb_schema(path, name),
      how_to_schema(name, Keyword.fetch!(opts, :steps)),
      faq_schema(Keyword.fetch!(opts, :faqs))
    ])
  end

  defp breadcrumb_schema(path, name) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => [
        %{
          "@type" => "ListItem",
          "position" => 1,
          "name" => "AI Sticker Maker",
          "item" => "https://ai-sticker-maker.com/"
        },
        %{
          "@type" => "ListItem",
          "position" => 2,
          "name" => name,
          "item" => "https://ai-sticker-maker.com#{path}"
        }
      ]
    }
  end

  defp how_to_schema(name, steps) do
    %{
      "@context" => "https://schema.org",
      "@type" => "HowTo",
      "name" => "How to use #{name}",
      "step" =>
        Enum.with_index(steps, 1)
        |> Enum.map(fn {text, position} ->
          %{"@type" => "HowToStep", "position" => position, "text" => text}
        end)
    }
  end

  defp faq_schema(faqs) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        Enum.map(faqs, fn {question, answer} ->
          %{
            "@type" => "Question",
            "name" => question,
            "acceptedAnswer" => %{"@type" => "Answer", "text" => answer}
          }
        end)
    }
  end
end
