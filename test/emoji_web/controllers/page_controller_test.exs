defmodule StickerWeb.PageControllerTest do
  use StickerWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AI Sticker Maker"
  end

  test "public SEO pages render focused content", %{conn: conn} do
    conn = get(conn, ~p"/face-to-sticker")
    body = html_response(conn, 200)
    assert body =~ "Face to Sticker AI Generator"
    assert body =~ "What makes a good face to sticker upload?"

    conn = get(build_conn(), ~p"/custom-sticker-maker")
    assert html_response(conn, 200) =~ "How do I write a custom sticker prompt?"

    conn = get(build_conn(), ~p"/cute-sticker-ideas")
    assert html_response(conn, 200) =~ "What are easy cute sticker ideas?"

    conn = get(build_conn(), ~p"/sticker-maker-online")
    assert html_response(conn, 200) =~ "Sticker Maker Online"

    conn = get(build_conn(), ~p"/ai-avatar-sticker")
    assert html_response(conn, 200) =~ "AI Avatar Sticker Generator"

    conn = get(build_conn(), ~p"/kawaii-sticker-maker")
    assert html_response(conn, 200) =~ "Kawaii Sticker Maker"

    conn = get(build_conn(), ~p"/transparent-sticker-maker")
    assert html_response(conn, 200) =~ "Transparent Sticker Maker"
  end

  test "sitemap includes public SEO landing pages", %{conn: conn} do
    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert body =~ "/face-to-sticker"
    assert body =~ "/custom-sticker-maker"
    assert body =~ "/cute-sticker-ideas"
    assert body =~ "/sticker-maker-online"
    assert body =~ "/ai-avatar-sticker"
    assert body =~ "/kawaii-sticker-maker"
    assert body =~ "/transparent-sticker-maker"
    refute body =~ "/account"
  end

  test "batch download without selection redirects to history", %{conn: conn} do
    conn = get(conn, ~p"/stickers/download")

    assert redirected_to(conn, 302) == ~p"/stickers"
  end
end
