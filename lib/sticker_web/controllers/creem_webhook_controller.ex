defmodule StickerWeb.CreemWebhookController do
  use StickerWeb, :controller

  alias Sticker.Payments

  def handle(conn, _params) do
    with payload when is_binary(payload) <- conn.private[:raw_body],
         signature when is_binary(signature) <- get_req_header(conn, "creem-signature") |> List.first(),
         {:ok, event} <- Payments.verify_creem_webhook(payload, signature),
         :ok <- handle_event(event) do
      send_resp(conn, 200, "ok")
    else
      _error -> send_resp(conn, 400, "bad request")
    end
  end

  defp handle_event(event) do
    case event_type(event) do
      type when type in ["checkout.completed", "checkout.session.completed"] ->
        Payments.fulfill_creem_checkout(event, event["id"])

      "refund.created" ->
        Payments.refund_creem_checkout(event, event["id"])

      _type ->
        :ok
    end
  end

  defp event_type(event), do: event["eventType"] || event["event_type"] || event["type"]
end
