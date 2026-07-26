defmodule StickerWeb.AdminLiveIdentityTest do
  use ExUnit.Case, async: true

  alias StickerWeb.AdminLive

  test "stale assign-user-id is always a no-op" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, local_user_id: "server-user"}
    }

    assert {:noreply, ^socket} =
             AdminLive.handle_event("assign-user-id", %{"userId" => "attacker-user"}, socket)
  end
end
