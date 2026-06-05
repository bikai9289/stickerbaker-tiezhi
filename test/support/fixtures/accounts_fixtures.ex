defmodule Sticker.AccountsFixtures do
  def user_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        email: "user#{unique}@example.com",
        password: "password123"
      })

    {:ok, user} = Sticker.Accounts.register_user(attrs)
    user
  end
end
