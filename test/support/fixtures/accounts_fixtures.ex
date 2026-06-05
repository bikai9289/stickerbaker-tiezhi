defmodule Sticker.AccountsFixtures do
  def user_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    {confirmed?, attrs} = Map.pop(attrs, :confirmed, true)

    attrs =
      Enum.into(attrs, %{
        email: "user#{unique}@example.com",
        password: "password123"
      })

    {:ok, user} = Sticker.Accounts.register_user(attrs)

    if confirmed? do
      {:ok, user} = Sticker.Accounts.confirm_user(user.confirmation_token)
      user
    else
      user
    end
  end
end
