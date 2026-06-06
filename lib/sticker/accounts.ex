defmodule Sticker.Accounts do
  import Ecto.Query, warn: false

  alias Sticker.Accounts.User
  alias Sticker.Repo

  def get_user(nil), do: nil
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    normalized_email =
      email
      |> String.trim()
      |> String.downcase()

    Repo.one(from u in User, where: u.email == ^normalized_email)
  end

  def get_user_by_public_id(public_id) when is_binary(public_id) do
    Repo.get_by(User, public_id: public_id)
  end

  def get_user_by_public_id(_public_id), do: nil

  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def confirm_user(token) when is_binary(token) do
    case Repo.get_by(User, confirmation_token: token) do
      %User{} = user ->
        user
        |> User.confirm_changeset()
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  def confirm_user(_token), do: {:error, :not_found}

  def send_confirmation_email(%User{confirmation_token: token} = user, url_fun)
      when is_binary(token) and is_function(url_fun, 1) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(user.email)
      |> Swoosh.Email.from({"AI Sticker Maker", support_email()})
      |> Swoosh.Email.subject("Confirm your AI Sticker Maker account")
      |> Swoosh.Email.text_body("""
      Confirm your AI Sticker Maker account to unlock your 3 free sticker credits.

      #{url_fun.(token)}

      If you did not create this account, you can ignore this email.
      """)

    Sticker.Mailer.deliver(email)
  end

  def send_confirmation_email(_user, _url_fun), do: {:error, :missing_confirmation_token}

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    if User.valid_password?(user, password) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_email, _password), do: {:error, :invalid_credentials}

  def change_user_registration(attrs \\ %{}) do
    User.registration_changeset(%User{}, attrs)
  end

  def spend_credit(%User{id: user_id}) do
    {count, _} =
      from(u in User, where: u.id == ^user_id and u.credits > 0)
      |> Repo.update_all(inc: [credits: -1])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :insufficient_credits}
    end
  end

  def spend_credit(_user), do: {:error, :not_signed_in}

  def has_credits?(%User{credits: credits}, amount) when is_integer(amount) and amount > 0,
    do: credits >= amount

  def has_credits?(_user, _amount), do: false

  def spend_credits(%User{id: user_id}, amount) when is_integer(amount) and amount > 0 do
    {count, _} =
      from(u in User, where: u.id == ^user_id and u.credits >= ^amount)
      |> Repo.update_all(inc: [credits: -amount])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :insufficient_credits}
    end
  end

  def spend_credits(_user, _amount), do: {:error, :not_signed_in}

  def refund_credits(%User{id: user_id}, amount) when is_integer(amount) and amount > 0 do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [credits: amount])

    get_user(user_id)
  end

  def refund_credits(user, _amount), do: refund_credit(user)

  def refund_credit(%User{id: user_id}) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [credits: 1])

    get_user(user_id)
  end

  def refund_credit(_user), do: nil

  def refund_credit_by_public_id(public_id) when is_binary(public_id) do
    case get_user_by_public_id(public_id) do
      %User{} = user -> {:ok, refund_credit(user)}
      nil -> {:error, :not_found}
    end
  end

  def refund_credit_by_public_id(_public_id), do: {:error, :not_found}

  def add_credits(user_id, amount) when is_integer(amount) and amount > 0 do
    {count, _} =
      from(u in User, where: u.id == ^user_id)
      |> Repo.update_all(inc: [credits: amount])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :not_found}
    end
  end

  def add_credits(_user_id, _amount), do: {:error, :invalid_amount}

  def deduct_credits(user_id, amount) when is_integer(user_id) and is_integer(amount) and amount > 0 do
    from(u in User,
      where: u.id == ^user_id,
      update: [set: [credits: fragment("GREATEST(? - ?, 0)", u.credits, ^amount)]]
    )
    |> Repo.update_all([])

    {:ok, get_user(user_id)}
  end

  def deduct_credits(_user_id, _amount), do: {:error, :invalid_amount}

  def count_signups_since_ip(ip, since) when is_binary(ip) do
    from(u in User, where: u.signup_ip == ^ip and u.inserted_at >= ^since)
    |> Repo.aggregate(:count)
  end

  def count_signups_since_ip(_ip, _since), do: 0

  def confirmed?(%User{confirmed_at: %DateTime{}}), do: true
  def confirmed?(_user), do: false

  defp support_email do
    System.get_env("SUPPORT_EMAIL", "support@ai-sticker-maker.com")
  end
end
