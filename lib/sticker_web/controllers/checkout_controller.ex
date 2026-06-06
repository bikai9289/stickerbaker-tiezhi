defmodule StickerWeb.CheckoutController do
  use StickerWeb, :controller

  alias Sticker.Payments

  def create(conn, %{"plan" => plan_id}) do
    with %{current_user: user} when not is_nil(user) <- conn.assigns,
         plan when not is_nil(plan) <- Payments.get_plan(plan_id),
         {:ok, url} <-
           Payments.create_checkout_session(
             plan,
             user,
             url(~p"/account?checkout=success"),
             url(~p"/pricing?checkout=canceled")
           ) do
      redirect(conn, external: url)
    else
      %{current_user: nil} ->
        conn
        |> put_flash(:error, "Please sign in before buying credits.")
        |> redirect(to: ~p"/users/log-in")

      nil ->
        conn
        |> put_flash(:error, "Unknown credit plan.")
        |> redirect(to: ~p"/pricing")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Checkout is not ready yet. Please try again later.")
        |> redirect(to: ~p"/pricing")
    end
  end
end
