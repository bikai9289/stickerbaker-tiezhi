defmodule StickerWeb.AdminPaymentsLive do
  use StickerWeb, :live_view

  alias Sticker.Accounts
  alias Sticker.Payments

  def mount(_params, _session, socket) do
    users = Accounts.list_users() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:attempts, Payments.list_payment_attempts())
     |> assign(:payments, Payments.list_payment_events(200))
     |> assign(:users, users)}
  end

  defp payment_status(%{refund_status: "refunded"}), do: "Refunded"
  defp payment_status(%{refund_status: "review_required"}), do: "Review required"
  defp payment_status(%{refund_status: "partial_refund_review"}), do: "Partial refund review"
  defp payment_status(_payment), do: "Paid"
end
