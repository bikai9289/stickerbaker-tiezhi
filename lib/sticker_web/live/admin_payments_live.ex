defmodule StickerWeb.AdminPaymentsLive do
  use StickerWeb, :live_view

  alias Sticker.Accounts
  alias Sticker.Payments

  def mount(_params, _session, socket) do
    users = Accounts.list_users() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:payments, Payments.list_payment_events(200))
     |> assign(:users, users)}
  end
end
