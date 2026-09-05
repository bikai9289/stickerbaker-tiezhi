defmodule StickerWeb.SEO do
  @base_url "https://ai-sticker-maker.com"
  @og_image_path "/og.webp"

  use SEO,
    json_library: Jason,
    # a function reference will be called with a conn during render
    site: &__MODULE__.site_config/1,
    open_graph:
      SEO.OpenGraph.build(
        description:
          "Create up to 3 custom stickers from text or portraits without an account, then download completed designs as PNG or WebP files.",
        site_name: "AI Sticker Maker",
        locale: "en_US",
        image: @base_url <> @og_image_path
      ),
    twitter:
      SEO.Twitter.build(
        card: :summary,
        summary_card_image: @base_url <> @og_image_path
      )

  def site_config(_conn) do
    SEO.Site.build(
      default_title: "AI Sticker Maker - Free AI Sticker Generator Online",
      description:
        "Create up to 3 custom stickers from text or portraits without an account, then download completed designs as PNG or WebP files.",
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
      image: absolute_image_url(Keyword.get(opts, :image)),
      canonical_url: @base_url <> path,
      url: @base_url <> path,
      robots: Keyword.get(opts, :robots)
    }
  end

  def noindex(path, opts \\ []) do
    page(path, Keyword.put(opts, :robots, ["noindex", "follow"]))
  end

  def base_url, do: @base_url

  def og_image_url, do: @base_url <> @og_image_path

  def absolute_image_url(nil), do: og_image_url()

  def absolute_image_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "https://") or String.starts_with?(url, "http://") -> url
      String.starts_with?(url, "/") -> @base_url <> url
      true -> @base_url <> "/" <> url
    end
  end

  defp normalize_path(path) when is_binary(path) do
    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end
end
