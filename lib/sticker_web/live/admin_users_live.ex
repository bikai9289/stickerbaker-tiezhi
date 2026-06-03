defmodule StickerWeb.AdminUsersLive do
  use StickerWeb, :live_view

  alias Sticker.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(users: Accounts.list_users())}
  end

  def handle_event("add-credits", %{"id" => id, "amount" => amount}, socket) do
    with {user_id, ""} <- Integer.parse(id),
         {amount, ""} <- Integer.parse(amount),
         {:ok, user} <- Accounts.add_credits(user_id, amount) do
      {:noreply,
       socket
       |> assign(users: Accounts.list_users())
       |> put_flash(:info, "Added #{amount} credits to #{user.email}.")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not add credits.")}
    end
  end
end
