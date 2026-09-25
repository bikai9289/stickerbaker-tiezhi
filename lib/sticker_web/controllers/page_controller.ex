defmodule StickerWeb.PageController do
  use StickerWeb, :controller

  alias StickerWeb.SEO, as: PageSEO
  alias StickerWeb.StructuredData

  def home(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/",
        title: "AI Sticker Maker - Make Custom Stickers from Text or Photo",
        description:
          "Create custom AI stickers from text prompts or portraits. Try 3 free guest generations and download sticker-ready designs online."
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

  def pricing(conn, params) do
    conn
    |> SEO.assign(
      PageSEO.page("/pricing",
        title: "AI Sticker Maker Pricing - Buy Sticker Credits",
        description:
          "Compare the free guest trial with one-time Starter and Creator credit packs for text-to-sticker and portrait-to-sticker generation."
      )
    )
    |> assign(:checkout, params["checkout"])
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
        title: "Face to Sticker - Free, No Sign Up",
        description:
          "Turn a portrait into a sticker with no sign up. Get 3 free guest generations, portrait tips, and PNG or WebP downloads."
      )
    )
    |> assign_structured_data("/face-to-sticker", "Face to Sticker AI Generator",
      steps: [
        "Open the portrait generator. No account is required for the 3 free guest generations.",
        "Upload a clear portrait with one visible face and good lighting.",
        "Add an optional style prompt, then let the face to sticker workflow generate automatically.",
        "Open history to download PNG or WebP, save favorites, or create another version."
      ],
      faqs: [
        {"What makes a good face to sticker upload?",
         "A bright portrait with one clear face, natural expression, and minimal blur works best."},
        {"Does face to sticker use credits?",
         "Yes. Each portrait generation uses 1 credit, including the 3 free guest generations. Failed generations refund the credit."},
        {"Can I retry a failed face sticker?",
         "Yes. New upload-based face stickers save a private source image so failed generations can be retried from history."}
      ]
    )
    |> render(:face_to_sticker)
  end

  def photo_to_sticker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/photo-to-sticker",
        title: "Photo to Sticker - Free, No Sign Up",
        description:
          "Turn a photo into a sticker with no sign up. Get 3 free guest generations, photo tips, prompt examples, and PNG or WebP downloads."
      )
    )
    |> assign_structured_data("/photo-to-sticker", "Photo to Sticker - Free, No Sign Up",
      steps: [
        "Upload a JPG or PNG photo up to 8 MB. No account is required for 3 free guest generations.",
        "Add an optional prompt to steer the style, or leave it blank for the default sticker look.",
        "Generate. Each photo generation uses 1 credit and failed generations return the credit.",
        "Download the sticker as PNG or WebP, then resize it for the app where you plan to use it."
      ],
      faqs: [
        {"How do I turn a photo into a sticker?",
         "Upload a JPG or PNG photo, add an optional prompt, and generate. The finished sticker appears in your history as a PNG or WebP file."},
        {"What photo formats and sizes can I upload?",
         "Upload JPG or PNG images up to 8 MB. Use the largest clear version available; compressed screenshots give the generator less detail."},
        {"How many photos can I convert for free?",
         "Guests get 3 free generations with no sign up. Each photo generation uses 1 credit."},
        {"Do I need an account to turn a photo into a sticker?",
         "No. Guest results remain available through the current guest identity. Sign in to buy credits and attach eligible results to your account."},
        {"What happens if a generation fails?",
         "The credit is returned automatically. Upload-based stickers save a private source image so a failed generation can be retried without uploading again."},
        {"Can I use photo stickers commercially?",
         "Review the terms of service for the current usage terms before using generated stickers in paid or branded work."},
        {"Can I turn a photo into a WhatsApp sticker directly?",
         "Not in one step. Generate and download here first, then resize and convert the file to the destination platform's current requirements."}
      ]
    )
    |> render(:photo_to_sticker)
  end

  def custom_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/custom-sticker-maker",
        title: "Custom Sticker Maker - Free, No Sign Up",
        description:
          "Create custom stickers from prompts, portraits, or product photos. Get 3 free guest generations with no sign up and download PNG, WebP, or original files."
      )
    )
    |> assign_structured_data("/custom-sticker-maker", "Custom Sticker Maker - Free, No Sign Up",
      steps: [
        "Choose one main subject, such as a pet, mascot, product, character, object, or portrait.",
        "Add a style such as cute, clean, bold outline, white border, or simple background.",
        "Describe the mood or action, then generate one sticker or a small prompt batch.",
        "Use history to retry failed prompts, favorite strong results, and download files."
      ],
      faqs: [
        {"How do I write a custom sticker prompt?",
         "Start with the subject, then add mood, style, and use case. Try cheerful coffee cup mascot, clean white border, cute reaction sticker, simple background."},
        {"Can I make custom sticker batches?",
         "Add multiple prompts on separate lines. History groups generated stickers into batches, shows progress, and supports batch download."},
        {"What format should I download?",
         "PNG is useful for editing and broad compatibility. WebP is smaller for websites and social assets. Original keeps the generated format."},
        {"Do I need an account to make a custom sticker?",
         "No. Guests can try 3 custom generations with no sign up, and each generation uses 1 credit."},
        {"What happens if a custom generation fails?",
         "The credit is returned automatically, and the prompt stays in history so you can retry it without typing it again."},
        {"Can I make a sticker from my own photo?",
         "Yes. Upload a JPG or PNG up to 8 MB, such as a pet, product, or portrait, and add a short style prompt."},
        {"Can I use custom stickers commercially?",
         "Review the current terms of service before using generated stickers in paid or branded work, since usage terms can change."}
      ]
    )
    |> render(:custom_sticker_maker)
  end

  def reaction_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/reaction-sticker-maker",
        title: "Reaction Sticker Maker for Chat Stickers",
        description:
          "Make reaction stickers from prompts or portraits. Create expressive happy, sad, surprised, angry, and cozy sticker ideas for chats."
      )
    )
    |> assign_structured_data("/reaction-sticker-maker", "Reaction Sticker Maker",
      steps: [
        "Pick one emotion or chat reaction, such as excited, sleepy, surprised, or frustrated.",
        "Describe the subject and sticker style with a clean border and readable expression.",
        "Generate one reaction sticker or add multiple prompts for a small reaction set.",
        "Review completed results in history and download PNG or WebP files."
      ],
      faqs: [
        {"What is a reaction sticker?",
         "A reaction sticker is a small expressive image for chats, comments, communities, or social posts."},
        {"Can I make a reaction sticker set?",
         "Yes. Add one emotion prompt per line to generate a small set with consistent style."},
        {"Does this upload stickers to chat apps?",
         "No. The app generates downloadable sticker files; platform upload and pack setup happen outside the app."}
      ]
    )
    |> render(:reaction_sticker_maker)
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
        title: "Sticker Maker Online - Free, No Sign Up",
        description:
          "Make stickers online from a prompt or portrait. Get 3 free guest generations with no sign up, no install, and PNG, WebP, or original downloads."
      )
    )
    |> assign_structured_data("/sticker-maker-online", "Sticker Maker Online - Free, No Sign Up",
      steps: [
        "Start with text to sticker for an idea, object, mascot, or reaction.",
        "Use face or photo to sticker for an avatar-style result from a picture.",
        "Track processing and failed stickers in history, then retry or cancel when needed.",
        "Select completed stickers and download single files or batch ZIP packages."
      ],
      faqs: [
        {"What can I make with the online sticker maker?",
         "You can create prompt-based stickers, portrait stickers, avatar stickers, mascot ideas, and small batches."},
        {"Can I manage generated stickers?",
         "Yes. History supports search, filters, favorites, delete, retry, cancel, and batch detail pages."},
        {"Is this online sticker maker credit based?",
         "Yes. Guests can try 3 generations before signup, and each generation uses 1 credit. A failed generation returns its credit."},
        {"Do I need to install anything or create an account?",
         "No. It runs in the browser with nothing to install, and the 3 free guest generations need no account."},
        {"What formats can I download?",
         "Original, PNG, or WebP. PNG is safer for editing, WebP is smaller for the web, and original keeps the generated format."},
        {"Can I make several stickers at once?",
         "Yes. Add one prompt per line to run a small batch, then track progress and failed items in history. Each generation uses 1 credit."},
        {"What size do stickers need to be for Discord or WhatsApp?",
         "Discord custom stickers must be 320 x 320 px PNG or APNG within 512 KB. WhatsApp stickers must be 512 x 512 px WebP with transparency and static files under 100 KB. Resize after downloading."}
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

  def anime_avatar_sticker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/anime-avatar-sticker",
        title: "Anime Avatar Sticker Generator",
        description:
          "Create anime avatar stickers from character prompts or portraits. Try profile-ready anime sticker ideas, prompt examples, and downloads."
      )
    )
    |> assign_structured_data("/anime-avatar-sticker", "Anime Avatar Sticker Generator",
      steps: [
        "Choose a portrait or write a character prompt for an anime-style avatar sticker.",
        "Add readable style details such as expressive face, clean outline, and simple background.",
        "Generate variations until the avatar works at profile or chat size.",
        "Save favorites in history and download PNG or WebP files."
      ],
      faqs: [
        {"What is an anime avatar sticker?",
         "It is an avatar-style sticker with anime-inspired character styling, readable expression, and a clean sticker frame."},
        {"Can I create anime avatar stickers from text?",
         "Yes. Character prompts work well for fictional avatars, creator icons, gaming profiles, and mascot stickers."},
        {"Can I use a portrait for an anime avatar?",
         "You can upload a clear portrait and add an anime avatar prompt to guide the sticker style."}
      ]
    )
    |> render(:anime_avatar_sticker)
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

  def ai_sticker_generator(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/ai-sticker-generator",
        title: "AI Sticker Generator - Free, No Sign Up",
        description:
          "Use a free AI sticker generator with no sign up for 3 guest generations. Create stickers from text or portraits and download PNG or WebP files."
      )
    )
    |> assign_structured_data("/ai-sticker-generator", "AI Sticker Generator",
      steps: [
        "Open the generator. No sign up is required for the 3 free guest generations.",
        "Write a short prompt or upload a portrait, then generate the sticker.",
        "Each generation uses 1 credit. Failed generations return the credit automatically.",
        "Download completed stickers as PNG or WebP from history."
      ],
      faqs: [
        {"Is this AI sticker generator free?",
         "Yes. Guests can create up to 3 stickers for free with no sign up and no payment card."},
        {"Do I need an account to generate stickers?",
         "No. Guests can create up to 3 stickers without an account and can access generated results through the current guest identity. Sign in to buy credits and attach eligible guest-generated stickers to your account later."},
        {"What can I generate?",
         "You can generate prompt-based stickers, portrait stickers, avatars, mascots, and small batches."},
        {"How do I write a good sticker prompt?",
         "Start with one subject, then add an emotion, pose, style, border, and simple background. Short prompts are easier to refine than crowded scene descriptions."},
        {"Can I generate a sticker from a portrait?",
         "Yes. Switch to portrait mode and upload a clear JPG or PNG with one visible face, good lighting, and minimal blur."},
        {"What is the difference between PNG and WebP?",
         "PNG is convenient for editing and compatibility. WebP is usually smaller for websites, previews, and chat workflows."},
        {"Do failed generations use a credit?",
         "A failed generation automatically returns its credit. You can retry with a shorter prompt or a clearer portrait."}
      ]
    )
    |> render(:ai_sticker_generator)
  end

  def christmas_ai_sticker_maker(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.page("/christmas-ai-sticker-maker",
        title: "Christmas AI Sticker Maker - Make Holiday Stickers",
        description:
          "Make Christmas stickers with AI. Generate holiday characters, cozy icons, and festive reaction stickers from a prompt. Try 3 free generations with no sign up."
      )
    )
    |> assign_structured_data("/christmas-ai-sticker-maker", "Christmas AI Sticker Maker",
      steps: [
        "Describe a Christmas subject such as a cozy tree, gift mascot, or festive portrait.",
        "Add holiday style words like clean border, snowy colors, or cute winter icon.",
        "Generate one sticker or a small set of holiday prompts.",
        "Download PNG or WebP files for chats, cards, and social posts."
      ],
      faqs: [
        {"Can I make Christmas stickers with AI?",
         "Yes. Write a holiday prompt or upload a festive portrait and generate a sticker-style image."},
        {"Do I need to sign up?",
         "No. Guests can try 3 Christmas sticker generations without an account."},
        {"What Christmas sticker ideas work well?",
         "Keep one subject: a cocoa mug, tree ornament character, gift box mascot, or cozy winter portrait."},
        {"What should I include in a Christmas sticker prompt?",
         "Name one holiday subject, then add an emotion, action, palette, and simple sticker style. For example, try a cheerful gingerbread cookie waving with a clean white border."},
        {"Can I make a matching Christmas sticker set?",
         "Yes. Repeat the same border, palette, and style words while changing the subject or emotion. Batch mode supports one Christmas prompt per line for a small set."},
        {"Can I use a portrait for a Christmas sticker?",
         "Yes. Upload a clear portrait and add a festive style prompt for a holiday avatar or reaction. No account is required for the 3 free guest generations."},
        {"Which download format should I use?",
         "PNG is convenient for editing and compatibility. WebP is usually smaller for websites, previews, and chats."}
      ]
    )
    |> render(:christmas_ai_sticker_maker)
  end

  def ai_christmas_sticker_generator(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/christmas-ai-sticker-maker")
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
      {"/", "2026-09-25", "1.0"},
      {"/pricing", "2026-06-13", "0.8"},
      {"/face-to-sticker", "2026-09-25", "0.9"},
      {"/photo-to-sticker", "2026-09-25", "0.9"},
      {"/custom-sticker-maker", "2026-09-25", "0.9"},
      {"/reaction-sticker-maker", "2026-06-25", "0.8"},
      {"/cute-sticker-ideas", "2026-06-13", "0.8"},
      {"/sticker-maker-online", "2026-09-25", "0.9"},
      {"/ai-avatar-sticker", "2026-06-13", "0.8"},
      {"/anime-avatar-sticker", "2026-06-25", "0.8"},
      {"/kawaii-sticker-maker", "2026-06-13", "0.8"},
      {"/transparent-sticker-maker", "2026-06-13", "0.8"},
      {"/ai-sticker-generator", "2026-09-25", "0.9"},
      {"/christmas-ai-sticker-maker", "2026-09-25", "0.8"},
      {"/search", "2026-06-13", "0.7"},
      {"/contact", "2026-06-13", "0.5"},
      {"/payment-and-credits", "2026-06-13", "0.5"},
      {"/privacy-policy", "2026-06-13", "0.4"},
      {"/refund-policy", "2026-06-13", "0.5"},
      {"/terms-of-service", "2026-09-25", "0.4"},
      {"/sitemap", "2026-06-13", "0.3"}
    ]

    urls =
      Enum.map(paths, fn {path, lastmod, priority} ->
        """
        <url>
          <loc>#{base_url}#{path}</loc>
          <lastmod>#{lastmod}</lastmod>
          <priority>#{priority}</priority>
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
    assign(conn, :structured_data, StructuredData.for_page(path, name, opts))
  end
end
