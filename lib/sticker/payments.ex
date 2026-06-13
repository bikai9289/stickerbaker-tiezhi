defmodule Sticker.Payments do
  alias Ecto.Multi
  alias Sticker.Accounts
  alias Sticker.Payments.PaymentAttempt
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Payments.PaymentWebhookEvent
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
        amount: 499,
        currency: "usd",
        env: "STRIPE_STARTER_PRICE_ID"
      },
      %{
        id: "creator",
        name: "Creator",
        price: "$9.99",
        credits: 150,
        amount: 999,
        currency: "usd",
        env: "STRIPE_CREATOR_PRICE_ID"
      }
    ]
  end

  def get_plan(id), do: Enum.find(plans(), &(&1.id == id))

  def create_payment_attempt(plan, user) do
    with {:ok, price_id} <- fetch_price_id(plan) do
      create_payment_attempt(plan, user, price_id)
    end
  end

  def mark_payment_attempt_open(%PaymentAttempt{} = attempt, session) do
    attempt
    |> PaymentAttempt.changeset(%{
      status: "open",
      stripe_session_id: session["id"],
      provider_order_id: session["payment_intent"],
      checkout_url: session["url"]
    })
    |> Repo.update()
  end

  def mark_payment_attempt_failed(%PaymentAttempt{} = attempt, reason) do
    attempt
    |> PaymentAttempt.changeset(%{status: "failed", failure_reason: failure_reason(reason)})
    |> Repo.update()
  end

  def list_payment_events(limit \\ 100) do
    import Ecto.Query

    Repo.all(
      from e in PaymentEvent,
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  def list_payment_attempts(limit \\ 200) do
    import Ecto.Query

    Repo.all(
      from a in PaymentAttempt,
        order_by: [desc: a.inserted_at],
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

  def list_user_payment_attempts(user_id) do
    import Ecto.Query

    Repo.all(
      from a in PaymentAttempt,
        where: a.user_id == ^user_id,
        order_by: [desc: a.inserted_at],
        limit: 20
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
         {:ok, attempt} <- create_payment_attempt(plan, user, price_id) do
      case headers() do
        {:ok, headers} ->
          do_create_stripe_checkout_session(price_id, attempt, plan, user, success_url, cancel_url, headers)

        {:error, reason} ->
          mark_payment_attempt_failed(attempt, reason)
          {:error, reason}
      end
    end
  end

  defp do_create_stripe_checkout_session(price_id, attempt, plan, user, success_url, cancel_url, headers) do
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
      {"metadata[payment_attempt_id]", Integer.to_string(attempt.id)},
      {"client_reference_id", Integer.to_string(user.id)}
    ]

    case Req.post(url: "#{stripe_api_base()}/checkout/sessions", form: body, headers: headers) do
      {:ok, %{status: status, body: %{"url" => url} = session}} when status in 200..299 ->
        case mark_payment_attempt_open(attempt, session) do
          {:ok, _attempt} -> {:ok, url}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status: status, body: body}} ->
        mark_payment_attempt_failed(attempt, "stripe_error:#{status}")
        {:error, {:stripe_error, status, body}}

      {:error, reason} ->
        mark_payment_attempt_failed(attempt, reason)
        {:error, reason}
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
          {:ok, normalize_creem_checkout_url(url)}

        {:ok, %{status: status, body: body}} ->
          {:error, {:creem_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def record_webhook_event(%{"id" => event_id, "type" => event_type} = event) do
    %PaymentWebhookEvent{}
    |> PaymentWebhookEvent.changeset(%{
      provider: "stripe",
      stripe_event_id: event_id,
      event_type: event_type,
      livemode: Map.get(event, "livemode", false),
      status: "received"
    })
    |> Repo.insert()
    |> case do
      {:ok, webhook_event} ->
        {:ok, webhook_event}

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_webhook_event_error?(changeset) do
          duplicate_webhook_event_result(event_id)
        else
          {:error, :invalid_event}
        end
    end
  end

  def record_webhook_event(_event), do: {:error, :invalid_event}

  def mark_webhook_event_processed(%PaymentWebhookEvent{} = event),
    do: update_webhook_event_status(event, "processed")

  def mark_webhook_event_ignored(%PaymentWebhookEvent{} = event),
    do: update_webhook_event_status(event, "ignored")

  def mark_webhook_event_failed(%PaymentWebhookEvent{} = event, reason),
    do: update_webhook_event_status(event, "failed", failure_reason(reason))

  def verify_webhook(payload, signature) when is_binary(signature) do
    with {:ok, secret} <- System.fetch_env("STRIPE_WEBHOOK_SECRET"),
         %{"t" => timestamp, "v1" => expected_signatures} <- parse_signature(signature),
         {timestamp, ""} <- Integer.parse(timestamp),
         true <- fresh_signature_timestamp?(timestamp),
         signed_payload = "#{timestamp}.#{payload}",
         digest <-
           :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- matching_signature?(digest, expected_signatures) do
      Jason.decode(payload)
    else
      _ -> {:error, :invalid_signature}
    end
  end

  def verify_webhook(_payload, _signature), do: {:error, :missing_signature}

  defp fresh_signature_timestamp?(timestamp) do
    abs(System.system_time(:second) - timestamp) <= 300
  end

  defp matching_signature?(digest, signatures) when is_list(signatures) do
    Enum.any?(signatures, &matching_signature?(digest, &1))
  end

  defp matching_signature?(digest, signature) when is_binary(signature) do
    byte_size(digest) == byte_size(signature) and Plug.Crypto.secure_compare(digest, signature)
  end

  defp matching_signature?(_digest, _signature), do: false

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
          "id" => _session_id,
          "metadata" => %{
            "user_id" => user_id,
            "credits" => credits,
            "plan" => plan_id,
            "payment_attempt_id" => attempt_id
          }
        } = session,
        stripe_event_id
      ) do
    with {attempt_id, ""} <- Integer.parse(attempt_id),
         {user_id, ""} <- Integer.parse(user_id),
         {credits, ""} <- Integer.parse(credits),
         %PaymentAttempt{} = attempt <- Repo.get(PaymentAttempt, attempt_id),
         :ok <- validate_checkout_session(session, attempt, user_id, credits, plan_id) do
      credit_validated_checkout(session, attempt, stripe_event_id)
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :payment_attempt_not_found}
      _error -> {:error, :invalid_checkout_metadata}
    end
  end

  def fulfill_checkout(_session, _stripe_event_id), do: {:error, :invalid_checkout_metadata}

  defp validate_checkout_session(session, attempt, user_id, credits, plan_id) do
    cond do
      session["payment_status"] != "paid" ->
        {:error, :unpaid_checkout}

      session["mode"] != "payment" ->
        {:error, :invalid_checkout_mode}

      session["id"] != attempt.stripe_session_id ->
        {:error, :checkout_session_mismatch}

      payment_intent_mismatch?(session, attempt) ->
        {:error, :checkout_payment_intent_mismatch}

      user_id != attempt.user_id ->
        {:error, :checkout_user_mismatch}

      credits != attempt.credits ->
        {:error, :checkout_credits_mismatch}

      plan_id != attempt.plan ->
        {:error, :checkout_plan_mismatch}

      session["amount_total"] != attempt.amount ->
        {:error, :checkout_amount_mismatch}

      String.downcase(to_string(session["currency"])) != attempt.currency ->
        {:error, :checkout_currency_mismatch}

      true ->
        :ok
    end
  end

  defp credit_validated_checkout(session, attempt, stripe_event_id) do
    provider_order_id = stripe_object_id(session["payment_intent"]) || attempt.provider_order_id

    Multi.new()
    |> Multi.insert(
      :payment_event,
      PaymentEvent.changeset(%PaymentEvent{}, %{
        stripe_session_id: session["id"],
        stripe_event_id: stripe_event_id,
        provider: "stripe",
        provider_order_id: provider_order_id,
        payment_attempt_id: attempt.id,
        user_id: attempt.user_id,
        credits: attempt.credits,
        plan: attempt.plan,
        amount: attempt.amount,
        currency: attempt.currency,
        stripe_price_id: attempt.stripe_price_id
      })
    )
    |> Multi.run(:credits, fn _repo, _changes ->
      Accounts.add_credits(attempt.user_id, attempt.credits)
    end)
    |> Multi.update(:payment_attempt, fn _changes ->
      PaymentAttempt.changeset(attempt, %{status: "credited"})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, :payment_event, %Ecto.Changeset{} = changeset, _changes} ->
        if duplicate_payment_event_error?(changeset) do
          handle_duplicate_checkout(session, attempt)
        else
          {:error, changeset}
        end

      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp stripe_object_id(%{"id" => id}) when is_binary(id), do: id
  defp stripe_object_id(id) when is_binary(id), do: id
  defp stripe_object_id(_value), do: nil

  defp payment_intent_mismatch?(session, attempt) do
    session_payment_intent = stripe_object_id(session["payment_intent"])
    attempt_payment_intent = stripe_object_id(attempt.provider_order_id)

    is_binary(session_payment_intent) and session_payment_intent != "" and
      is_binary(attempt_payment_intent) and attempt_payment_intent != "" and
      session_payment_intent != attempt_payment_intent
  end

  defp handle_duplicate_checkout(session, attempt) do
    case Repo.get_by(PaymentEvent, stripe_session_id: session["id"]) do
      %PaymentEvent{} = payment ->
        if duplicate_checkout_matches?(payment, session, attempt) do
          ensure_attempt_credited(attempt)
        else
          {:error, :duplicate_checkout_mismatch}
        end

      nil ->
        {:error, :duplicate_checkout_mismatch}
    end
  end

  defp duplicate_checkout_matches?(payment, session, attempt) do
    provider_order_id = stripe_object_id(session["payment_intent"]) || attempt.provider_order_id

    payment.provider == "stripe" and
      payment.provider_order_id == provider_order_id and
      payment.payment_attempt_id == attempt.id and
      payment.user_id == attempt.user_id and
      payment.credits == attempt.credits and
      payment.plan == attempt.plan and
      payment.amount == attempt.amount and
      payment.currency == attempt.currency and
      payment.stripe_price_id == attempt.stripe_price_id
  end

  defp ensure_attempt_credited(%PaymentAttempt{status: "credited"}), do: :ok

  defp ensure_attempt_credited(%PaymentAttempt{} = attempt) do
    attempt
    |> PaymentAttempt.changeset(%{status: "credited"})
    |> Repo.update()
    |> case do
      {:ok, _attempt} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp duplicate_payment_event_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:stripe_session_id, {_message, opts}} -> opts[:constraint] == :unique
      {_field, {_message, opts}} -> opts[:constraint_name] == "payment_events_stripe_session_id_index"
      _error -> false
    end)
  end

  def fulfill_creem_checkout(event, creem_event_id) do
    checkout = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    metadata = Map.get(checkout, "metadata", %{})
    session_id = checkout["id"] || checkout["checkout_id"] || creem_event_id

    order_id =
      checkout["order"] || checkout["order_id"] || get_in(checkout, ["transaction", "order"])

    fulfill_provider_checkout("creem", session_id, creem_event_id, metadata, order_id)
  end

  def refund_creem_checkout(event, refund_event_id) do
    refund = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    order_id = refund["order"] || refund["order_id"] || get_in(refund, ["transaction", "order"])
    checkout_id = refund["checkout"] || refund["checkout_id"]

    refund_provider_checkout("creem", order_id, checkout_id, refund_event_id)
  end

  def refund_stripe_checkout(event, refund_event_id) do
    charge = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    payment_intent = stripe_object_id(charge["payment_intent"])
    charge_id = charge["id"]

    if partial_stripe_refund?(charge) do
      mark_refund_review_provider_checkout(
        "stripe",
        payment_intent,
        charge_id,
        refund_event_id,
        "partial_refund_review"
      )
    else
      refund_provider_checkout("stripe", payment_intent, charge_id, refund_event_id, [
        "none",
        "partial_refund_review"
      ])
    end
  end

  defp fulfill_provider_checkout(provider, session_id, event_id, metadata, provider_order_id) do
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
          provider_order_id: provider_order_id,
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

  defp refund_provider_checkout(provider, order_id, checkout_id, refund_event_id) do
    refund_provider_checkout(provider, order_id, checkout_id, refund_event_id, ["none"])
  end

  defp refund_provider_checkout(provider, order_id, checkout_id, refund_event_id, refundable_statuses)
       when is_binary(refund_event_id) and refund_event_id != "" do
    if blank?(order_id) and blank?(checkout_id) do
      {:error, :invalid_refund_metadata}
    else
      do_refund_provider_checkout(provider, order_id, checkout_id, refund_event_id, refundable_statuses)
    end
  end

  defp refund_provider_checkout(_provider, _order_id, _checkout_id, _refund_event_id, _refundable_statuses),
    do: {:error, :invalid_refund_metadata}

  defp mark_refund_review_provider_checkout(provider, order_id, checkout_id, refund_event_id, refund_status)
       when is_binary(refund_event_id) and refund_event_id != "" do
    if blank?(order_id) and blank?(checkout_id) do
      {:error, :invalid_refund_metadata}
    else
      do_mark_refund_review_provider_checkout(provider, order_id, checkout_id, refund_event_id, refund_status)
    end
  end

  defp mark_refund_review_provider_checkout(
         _provider,
         _order_id,
         _checkout_id,
         _refund_event_id,
         _refund_status
       ),
       do: {:error, :invalid_refund_metadata}

  defp do_mark_refund_review_provider_checkout(
         provider,
         order_id,
         checkout_id,
         refund_event_id,
         refund_status
       ) do
    import Ecto.Query

    query =
      from e in PaymentEvent,
        where: e.provider == ^provider,
        where: e.refund_status == "none",
        lock: "FOR UPDATE",
        limit: 1

    query =
      cond do
        is_binary(order_id) and order_id != "" ->
          from e in query, where: e.provider_order_id == ^order_id

        is_binary(checkout_id) and checkout_id != "" ->
          from e in query, where: e.stripe_session_id == ^checkout_id

        true ->
          query
      end

    Repo.transaction(fn ->
      case Repo.one(query) do
        %PaymentEvent{} = payment ->
          payment
          |> PaymentEvent.changeset(%{
            refunded_at: DateTime.utc_now() |> DateTime.truncate(:second),
            refund_event_id: refund_event_id,
            refund_status: refund_status
          })
          |> Repo.update()
          |> case do
            {:ok, _payment} -> :ok
            {:error, %Ecto.Changeset{} = changeset} ->
              if duplicate_refund_event_error?(changeset), do: :ok, else: Repo.rollback(changeset)
          end

        nil ->
          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_refund_provider_checkout(provider, order_id, checkout_id, refund_event_id, refundable_statuses) do
    Multi.new()
    |> Multi.run(:payment_event, fn repo, _changes ->
      import Ecto.Query

      query =
        from e in PaymentEvent,
          where: e.provider == ^provider,
          where: e.refund_status in ^refundable_statuses,
          lock: "FOR UPDATE",
          limit: 1

      query =
        cond do
          is_binary(order_id) and order_id != "" ->
            from e in query, where: e.provider_order_id == ^order_id

          is_binary(checkout_id) and checkout_id != "" ->
            from e in query, where: e.stripe_session_id == ^checkout_id

          true ->
            query
        end

      case repo.one(query) do
        %PaymentEvent{} = payment -> {:ok, payment}
        nil -> {:error, :payment_not_found}
      end
    end)
    |> Multi.run(:refund_decision, fn repo, %{payment_event: payment} ->
      import Ecto.Query

      user =
        Accounts.User
        |> where([u], u.id == ^payment.user_id)
        |> lock("FOR UPDATE")
        |> repo.one()

      cond do
        is_nil(user) ->
          {:error, :user_not_found}

        user.credits >= payment.credits ->
          {1, _} =
            from(u in Accounts.User, where: u.id == ^user.id)
            |> repo.update_all(inc: [credits: -payment.credits])

          {:ok, :refunded}

        true ->
          {:ok, :review_required}
      end
    end)
    |> Multi.update(:refund, fn %{payment_event: payment, refund_decision: refund_status} ->
      PaymentEvent.changeset(payment, %{
        refunded_at: DateTime.utc_now() |> DateTime.truncate(:second),
        refund_event_id: refund_event_id,
        refund_status: Atom.to_string(refund_status)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, :payment_event, :payment_not_found, _changes} -> :ok
      {:error, :refund, %Ecto.Changeset{}, _changes} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp partial_stripe_refund?(%{"amount" => amount, "amount_refunded" => refunded})
       when is_integer(amount) and is_integer(refunded) do
    refunded > 0 and refunded < amount
  end

  defp partial_stripe_refund?(_charge), do: false

  defp duplicate_refund_event_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:refund_event_id, {_message, opts}} -> opts[:constraint] == :unique
      {_field, {_message, opts}} -> opts[:constraint_name] == "payment_events_refund_event_id_index"
      _error -> false
    end)
  end

  defp fetch_price_id(plan) do
    case System.fetch_env(plan.env) do
      {:ok, price_id} when price_id != "" -> {:ok, price_id}
      _ -> {:error, :checkout_not_configured}
    end
  end

  defp create_payment_attempt(plan, user, price_id) do
    %PaymentAttempt{}
    |> PaymentAttempt.changeset(%{
      provider: "stripe",
      user_id: user.id,
      plan: plan.id,
      credits: plan.credits,
      amount: plan.amount,
      currency: plan.currency,
      status: "created",
      stripe_price_id: price_id
    })
    |> Repo.insert()
  end

  defp failure_reason(reason) when is_binary(reason), do: reason
  defp failure_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_reason(reason), do: inspect(reason)

  defp update_webhook_event_status(event, status, error_reason \\ nil) do
    event
    |> PaymentWebhookEvent.changeset(%{status: status, error_reason: error_reason})
    |> Repo.update()
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

  defp stripe_api_base do
    System.get_env("STRIPE_API_BASE", @stripe_api)
  end

  defp creem_api_base do
    case System.get_env("CREEM_TEST_MODE", "true") |> String.downcase() do
      value when value in ["false", "0", "no"] -> @creem_live_api
      _value -> @creem_test_api
    end
  end

  defp normalize_creem_checkout_url("https://creem.io/" <> _path = url),
    do: String.replace_prefix(url, "https://creem.io/", "https://www.creem.io/")

  defp normalize_creem_checkout_url(url), do: url

  defp blank?(value), do: not is_binary(value) or value == ""

  defp get_webhook_event(event_id) do
    import Ecto.Query

    Repo.one(
      from e in PaymentWebhookEvent,
        where: e.provider == "stripe" and e.stripe_event_id == ^event_id,
        limit: 1
    )
  end

  defp duplicate_webhook_event_result(event_id) do
    case get_webhook_event(event_id) do
      %PaymentWebhookEvent{status: status} = event when status in ["received", "failed"] ->
        {:ok, event}

      %PaymentWebhookEvent{status: status} when status in ["processed", "ignored"] ->
        {:error, :duplicate_event}

      _event ->
        {:error, :invalid_event}
    end
  end

  defp duplicate_webhook_event_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_field, {_message, opts}} ->
        opts[:constraint] == :unique and
          opts[:constraint_name] == "payment_webhook_events_provider_stripe_event_id_index"

      _error ->
        false
    end)
  end

  defp parse_signature(signature) do
    signature
    |> String.split(",")
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.reduce(%{}, fn
      ["v1", value], acc -> Map.update(acc, "v1", [value], &[value | &1])
      [key, value], acc -> Map.put(acc, key, value)
      _part, acc -> acc
    end)
  end
end
