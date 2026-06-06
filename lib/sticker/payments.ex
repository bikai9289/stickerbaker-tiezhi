defmodule Sticker.Payments do
  alias Ecto.Multi
  alias Sticker.Accounts
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Repo

  @stripe_api "https://api.stripe.com/v1"
  @creem_live_api "https://api.creem.io"
  @creem_test_api "https://test-api.creem.io"

  def plans do
    [
      %{
        id: "starter",
        name: "Starter",
        price: "$4.99",
        credits: 50,
        env: "STRIPE_STARTER_PRICE_ID"
      },
      %{
        id: "creator",
        name: "Creator",
        price: "$9.99",
        credits: 150,
        env: "STRIPE_CREATOR_PRICE_ID"
      }
    ]
  end

  def get_plan(id), do: Enum.find(plans(), &(&1.id == id))

  def list_payment_events(limit \\ 100) do
    import Ecto.Query

    Repo.all(
      from e in PaymentEvent,
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  def list_user_payment_events(user_id) do
    import Ecto.Query

    Repo.all(
      from e in PaymentEvent,
        where: e.user_id == ^user_id,
        order_by: [desc: e.inserted_at]
    )
  end

  def create_checkout_session(plan, user, success_url, cancel_url) do
    case payment_provider() do
      "creem" -> create_creem_checkout_session(plan, user, success_url)
      _provider -> create_stripe_checkout_session(plan, user, success_url, cancel_url)
    end
  end

  def create_stripe_checkout_session(plan, user, success_url, cancel_url) do
    with {:ok, price_id} <- fetch_price_id(plan),
         {:ok, headers} <- headers() do
      body = [
        {"mode", "payment"},
        {"line_items[0][price]", price_id},
        {"line_items[0][quantity]", "1"},
        {"success_url", success_url},
        {"cancel_url", cancel_url},
        {"customer_email", user.email},
        {"metadata[user_id]", Integer.to_string(user.id)},
        {"metadata[credits]", Integer.to_string(plan.credits)},
        {"metadata[plan]", plan.id},
        {"client_reference_id", Integer.to_string(user.id)}
      ]

      case Req.post(url: "#{@stripe_api}/checkout/sessions", form: body, headers: headers) do
        {:ok, %{status: status, body: %{"url" => url}}} when status in 200..299 ->
          {:ok, url}

        {:ok, %{status: status, body: body}} ->
          {:error, {:stripe_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def create_creem_checkout_session(plan, user, success_url) do
    with {:ok, product_id} <- fetch_creem_product_id(plan),
         {:ok, headers} <- creem_headers() do
      body = %{
        "product_id" => product_id,
        "request_id" => "checkout-#{user.id}-#{plan.id}-#{System.system_time(:millisecond)}",
        "success_url" => success_url,
        "customer" => %{"email" => user.email},
        "metadata" => %{
          "user_id" => Integer.to_string(user.id),
          "credits" => Integer.to_string(plan.credits),
          "plan" => plan.id
        }
      }

      case Req.post(url: "#{creem_api_base()}/v1/checkouts", json: body, headers: headers) do
        {:ok, %{status: status, body: %{"checkout_url" => url}}} when status in 200..299 ->
          {:ok, url}

        {:ok, %{status: status, body: body}} ->
          {:error, {:creem_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def verify_webhook(payload, signature) when is_binary(signature) do
    secret = System.fetch_env!("STRIPE_WEBHOOK_SECRET")

    with %{"t" => timestamp, "v1" => expected} <- parse_signature(signature),
         signed_payload = "#{timestamp}.#{payload}",
         digest <-
           :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(digest, expected) do
      Jason.decode(payload)
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_payload, _signature), do: {:error, :missing_signature}

  def verify_creem_webhook(payload, signature) when is_binary(signature) do
    secret = System.fetch_env!("CREEM_WEBHOOK_SECRET")

    digest =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    expected = String.downcase(signature)

    if byte_size(digest) == byte_size(expected) and Plug.Crypto.secure_compare(digest, expected) do
      Jason.decode(payload)
    else
      {:error, :invalid_signature}
    end
  end

  def verify_creem_webhook(_payload, _signature), do: {:error, :missing_signature}

  def fulfill_checkout(
        %{
          "id" => session_id,
          "metadata" => %{"user_id" => user_id, "credits" => credits} = metadata
        },
        stripe_event_id
      ) do
    with {user_id, ""} <- Integer.parse(user_id),
         {credits, ""} <- Integer.parse(credits) do
      Multi.new()
      |> Multi.insert(
        :payment_event,
        PaymentEvent.changeset(%PaymentEvent{}, %{
          stripe_session_id: session_id,
          stripe_event_id: stripe_event_id,
          provider: "stripe",
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

  def fulfill_creem_checkout(event, creem_event_id) do
    checkout = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    metadata = Map.get(checkout, "metadata", %{})
    session_id = checkout["id"] || checkout["checkout_id"] || creem_event_id

    fulfill_provider_checkout("creem", session_id, creem_event_id, metadata)
  end

  defp fulfill_provider_checkout(provider, session_id, event_id, metadata) do
    with true <- is_binary(session_id) and session_id != "",
         %{"user_id" => user_id, "credits" => credits} <- metadata,
         {user_id, ""} <- Integer.parse(user_id),
         {credits, ""} <- Integer.parse(credits) do
      Multi.new()
      |> Multi.insert(
        :payment_event,
        PaymentEvent.changeset(%PaymentEvent{}, %{
          stripe_session_id: session_id,
          stripe_event_id: event_id,
          provider: provider,
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

  defp fetch_price_id(plan) do
    case System.fetch_env(plan.env) do
      {:ok, price_id} when price_id != "" -> {:ok, price_id}
      _ -> {:error, :checkout_not_configured}
    end
  end

  defp fetch_creem_product_id(plan) do
    env =
      case plan.id do
        "starter" -> "CREEM_STARTER_PRODUCT_ID"
        "creator" -> "CREEM_CREATOR_PRODUCT_ID"
        _plan -> nil
      end

    case env && System.fetch_env(env) do
      {:ok, product_id} when product_id != "" -> {:ok, product_id}
      _ -> {:error, :checkout_not_configured}
    end
  end

  defp headers do
    case System.fetch_env("STRIPE_SECRET_KEY") do
      {:ok, secret_key} when secret_key != "" ->
        {:ok,
         [
           {"authorization", "Bearer #{secret_key}"},
           {"content-type", "application/x-www-form-urlencoded"}
         ]}

      _ ->
        {:error, :checkout_not_configured}
    end
  end

  defp creem_headers do
    case System.fetch_env("CREEM_API_KEY") do
      {:ok, api_key} when api_key != "" ->
        {:ok,
         [
           {"x-api-key", api_key},
           {"content-type", "application/json"}
         ]}

      _ ->
        {:error, :checkout_not_configured}
    end
  end

  defp payment_provider do
    System.get_env("PAYMENT_PROVIDER", "stripe")
    |> String.downcase()
  end

  defp creem_api_base do
    case System.get_env("CREEM_TEST_MODE", "true") |> String.downcase() do
      value when value in ["false", "0", "no"] -> @creem_live_api
      _value -> @creem_test_api
    end
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
