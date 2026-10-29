defmodule StickerWeb.StructuredData do
  @moduledoc false

  @base_url "https://ai-sticker-maker.com"

  def for_page(path, name, opts) do
    [
      breadcrumb(path, name),
      how_to(name, Keyword.fetch!(opts, :steps)),
      faq(Keyword.fetch!(opts, :faqs))
    ]
  end

  def for_home do
    [
      how_to("AI Sticker Maker", [
        "Describe a sticker idea or upload a clear portrait. Sign up for 1 free credit to generate.",
        "Generate a sticker. Sign up for 1 free credit to start. Each generation uses 1 credit.",
        "If a generation fails, the credit is returned automatically. Try a shorter prompt or a clearer portrait.",
        "Download completed stickers as PNG or WebP from history, including batch ZIP downloads."
      ]),
      faq([
        {"What is an AI sticker maker?",
         "An AI sticker maker turns a text prompt or portrait into a sticker-style image you can use for avatars, chats, thumbnails, and creative projects."},
        {"How do free generations and credits work?",
         "Sign up for 1 free credit with no payment card. Each text or portrait generation uses 1 credit. When you need more, buy a one-time credit pack. There is no subscription."},
        {"What happens if a generation fails?",
         "Failed generations automatically return the credit. Try again with a shorter prompt, or use a clear, front-facing portrait with one person and good lighting."},
        {"Do I need an account?",
         "Sign up for 1 free credit to generate. Guest results from an earlier trial remain available through the current guest identity; sign in to buy credits and attach eligible results to your account."},
        {"Which download formats are available?",
         "Completed stickers can be downloaded as PNG or WebP files. Your history also supports individual downloads and batch ZIP downloads for completed results."}
      ])
    ]
  end

  defp breadcrumb(path, name) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => [
        %{
          "@type" => "ListItem",
          "position" => 1,
          "name" => "AI Sticker Maker",
          "item" => "#{@base_url}/"
        },
        %{
          "@type" => "ListItem",
          "position" => 2,
          "name" => name,
          "item" => "#{@base_url}#{path}"
        }
      ]
    }
  end

  defp how_to(name, steps) do
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

  defp faq(faqs) do
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
