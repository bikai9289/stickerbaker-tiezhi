defmodule Sticker.Payments do
  alias Ecto.Multi
  alias Sticker.Accounts
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Repo

  @stripe_api "https://api.stripe.com/v1"

  def plans do
    [
      %{id: "starter", name: "Starter", price: "$4.99", credits: 50, env: "STRIPE_STARTER_PRICE_ID"},
      %{id: "creator", name: "Creator", price: "$9.99", credits: 150, env: "STRIPE_CREATOR_PRICE_ID"}
    ]
  end

  def get_plan(id), do: Enum.find(plans(), &(&1.id == id))

  def create_checkout_session(plan, user, success_url, cancel_url) do
    body = [
      {"mode", "payment"},
      {"line_items[0][price]", fetch_price_id!(plan)},
      {"line_items[0][quantity]", "1"},
      {"success_url", success_url},
      {"cancel_url", cancel_url},
      {"customer_email", user.email},
      {"metadata[user_id]", Integer.to_string(user.id)},
      {"metadata[credits]", Integer.to_string(plan.credits)},
      {"metadata[plan]", plan.id},
      {"client_reference_id", Integer.to_string(user.id)}
    ]

    case Req.post(url: "#{@stripe_api}/checkout/sessions", form: body, headers: headers()) do
      {:ok, %{status: status, body: %{"url" => url}}} when status in 200..299 ->
        {:ok, url}

      {:ok, %{status: status, body: body}} ->
        {:error, {:stripe_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify_webhook(payload, signature) when is_binary(signature) do
    secret = System.fetch_env!("STRIPE_WEBHOOK_SECRET")

    with %{"t" => timestamp, "v1" => expected} <- parse_signature(signature),
         signed_payload = "#{timestamp}.#{payload}",
         digest <- :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(digest, expected) do
      Jason.decode(payload)
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_payload, _signature), do: {:error, :missing_signature}

  def fulfill_checkout(%{
        "id" => session_id,
        "metadata" => %{"user_id" => user_id, "credits" => credits} = metadata
      }, stripe_event_id) do
    with {user_id, ""} <- Integer.parse(user_id),
         {credits, ""} <- Integer.parse(credits) do
      Multi.new()
      |> Multi.insert(
        :payment_event,
        PaymentEvent.changeset(%PaymentEvent{}, %{
          stripe_session_id: session_id,
          stripe_event_id: stripe_event_id,
          user_id: user_id,
          credits: credits,
          plan: metadata["plan"]
        })
      )
      |> Multi.run(:credits, fn _repo, _changes ->
        Accounts.add_credits(user_id, credits)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _changes} -> :ok
        {:error, :payment_event, %Ecto.Changeset{}, _changes} -> :ok
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      _error -> {:error, :invalid_checkout_metadata}
    end
  end

  def fulfill_checkout(_session, _stripe_event_id), do: {:error, :invalid_checkout_metadata}

  defp fetch_price_id!(plan), do: System.fetch_env!(plan.env)

  defp headers do
    [
      {"authorization", "Bearer #{System.fetch_env!("STRIPE_SECRET_KEY")}"},
      {"content-type", "application/x-www-form-urlencoded"}
    ]
  end

  defp parse_signature(signature) do
    signature
    |> String.split(",")
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.reduce(%{}, fn
      [key, value], acc -> Map.put(acc, key, value)
      _part, acc -> acc
    end)
  end
end
