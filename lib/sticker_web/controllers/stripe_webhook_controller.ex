defmodule StickerWeb.StripeWebhookController do
  use StickerWeb, :controller

  alias Sticker.Payments

  def handle(conn, _params) do
    with payload when is_binary(payload) <- conn.private[:raw_body],
         signature when is_binary(signature) <- get_req_header(conn, "stripe-signature") |> List.first(),
         {:ok, event} <- Payments.verify_webhook(payload, signature),
         :ok <- handle_event(event) do
      send_resp(conn, 200, "ok")
    else
      _error -> send_resp(conn, 400, "bad request")
    end
  end

  defp handle_event(%{
         "id" => event_id,
         "type" => "checkout.session.completed",
         "data" => %{
           "object" => session
         }
       }) do
    Payments.fulfill_checkout(session, event_id)
  end

  defp handle_event(_event), do: :ok
end
