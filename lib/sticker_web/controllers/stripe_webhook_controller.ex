defmodule StickerWeb.StripeWebhookController do
  use StickerWeb, :controller

  alias Sticker.Payments

  def handle(conn, _params) do
    with payload when is_binary(payload) <- conn.private[:raw_body],
         signature when is_binary(signature) <-
           get_req_header(conn, "stripe-signature") |> List.first(),
         {:ok, event} <- Payments.verify_webhook(payload, signature) do
      handle_verified_event(conn, event)
    else
      _error -> send_resp(conn, 400, "bad request")
    end
  end

  defp handle_verified_event(conn, event) do
    case Payments.record_webhook_event(event) do
      {:ok, webhook_event} ->
        {status, body} =
          event
          |> handle_event()
          |> mark_webhook_event(webhook_event)

        send_resp(conn, status, body)

      {:error, :duplicate_event} ->
        send_resp(conn, 200, "ok")

      {:error, :invalid_event} ->
        send_resp(conn, 200, "ok")
    end
  end

  defp mark_webhook_event(:ok, webhook_event),
    do: mark_processed(webhook_event)

  defp mark_webhook_event(:ignored, webhook_event),
    do: mark_ignored(webhook_event)

  defp mark_webhook_event({:error, reason}, webhook_event) do
    Payments.mark_webhook_event_failed(webhook_event, reason)

    if terminal_webhook_error?(reason) do
      {200, "ok"}
    else
      {500, "error"}
    end
  end

  defp mark_processed(webhook_event) do
    Payments.mark_webhook_event_processed(webhook_event)
    {200, "ok"}
  end

  defp mark_ignored(webhook_event) do
    Payments.mark_webhook_event_ignored(webhook_event)
    {200, "ok"}
  end

  defp terminal_webhook_error?(reason)
       when reason in [
              :invalid_checkout_metadata,
              :payment_attempt_not_found,
              :unpaid_checkout,
              :invalid_checkout_mode,
              :checkout_session_mismatch,
              :checkout_payment_intent_mismatch,
              :checkout_user_mismatch,
              :checkout_credits_mismatch,
              :checkout_plan_mismatch,
              :checkout_amount_mismatch,
              :checkout_currency_mismatch,
              :invalid_refund_metadata
            ],
       do: true

  defp terminal_webhook_error?(_reason), do: false

  defp handle_event(%{
         "id" => event_id,
         "type" => "checkout.session.completed",
         "data" => %{
           "object" => session
         }
       }) do
    Payments.fulfill_checkout(session, event_id)
  end

  defp handle_event(%{"id" => event_id, "type" => "charge.refunded"} = event) do
    Payments.refund_stripe_checkout(event, event_id)
  end

  defp handle_event(_event), do: :ignored
end
