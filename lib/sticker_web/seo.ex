defmodule StickerWeb.SEO do
  @base_url "https://ai-sticker-maker.com"

  use SEO,
    json_library: Jason,
    # a function reference will be called with a conn during render
    site: &__MODULE__.site_config/1,
    open_graph:
      SEO.OpenGraph.build(
        description:
          "Create custom stickers in seconds with our AI sticker maker. Start free, generate cute AI stickers from text prompts, and download your favorite designs online.",
        site_name: "AI Sticker Maker",
        locale: "en_US",
        image: "/og.webp"
      ),
    twitter:
      SEO.Twitter.build(
        card: :summary,
        summary_card_image: "/og.webp"
      )

  def site_config(_conn) do
    SEO.Site.build(
      default_title: "AI Sticker Maker - Free AI Sticker Generator Online",
      description:
        "Create custom stickers in seconds with our AI sticker maker. Start free, generate cute AI stickers from text prompts, and download your favorite designs online.",
      theme_color: "#ff6b1a",
      windows_tile_color: "#ff6b1a",
      mask_icon_color: "#ff6b1a"
    )
  end

  def page(path, opts \\ []) do
    path = normalize_path(path)
    description = Keyword.fetch!(opts, :description)
    title = Keyword.fetch!(opts, :title)

    %{
      title: title,
      description: description,
      image: Keyword.get(opts, :image, "/og.webp"),
      canonical_url: @base_url <> path,
      url: @base_url <> path,
      robots: Keyword.get(opts, :robots)
    }
  end

  def noindex(path, opts \\ []) do
    page(path, Keyword.put(opts, :robots, ["noindex", "follow"]))
  end

  def base_url, do: @base_url

  defp normalize_path(path) when is_binary(path) do
    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end
end
