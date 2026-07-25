defmodule StickerWeb.AccountLive do
  use StickerWeb, :live_view

  alias Sticker.Payments
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  @account_tasks [:account_summary, :account_recent, :account_favorites, :account_payments]
  @retry_sections %{
    "summary" => :account_summary,
    "recent" => :account_recent,
    "favorites" => :account_favorites,
    "payments" => :account_payments
  }
  @empty_counts %{total: nil, completed: nil, failed: nil, favorites: nil}

  def mount(_params, _session, %{assigns: %{current_user: nil}} = socket) do
    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/account",
         title: "AI Sticker Maker Account",
         description: "Manage AI Sticker Maker credits, saved stickers, generation history, and billing records."
       )
     )
     |> put_flash(:error, "Please sign in to view your account.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_id = user.public_id

    socket =
      socket
      |> SEO.assign(
        PageSEO.noindex("/account",
          title: "AI Sticker Maker Account",
          description: "Manage AI Sticker Maker credits, saved stickers, generation history, and billing records."
        )
      )
      |> assign(:summary_state, :loading)
      |> assign(:recent_state, :loading)
      |> assign(:favorites_state, :loading)
      |> assign(:payments_state, :loading)
      |> assign(:counts, @empty_counts)
      |> assign(:payment_attempts, [])
      |> assign(:payments, [])
      |> assign(:recent_empty?, false)
      |> assign(:favorites_empty?, false)
      |> stream(:recent_predictions, [])
      |> stream(:favorite_predictions, [])

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Sticker.PubSub, "user:#{user_id}")
        start_account_loads(socket, user)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_params(%{"checkout" => "success"}, _uri, socket) do
    {:noreply,
     socket
     |> refresh_account_data()
     |> put_flash(:info, "Payment received. Credits may take a moment to appear.")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_info({event, prediction}, socket)
      when event in [:prediction_loading, :prediction_completed, :prediction_failed] do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:recent_empty?, false)
     |> stream_insert(:recent_predictions, prediction, at: 0)
     |> refresh_prediction_sections(user)}
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    {:ok, prediction} = Predictions.toggle_favorite(id, user.public_id)

    socket =
      socket
      |> stream_insert(:recent_predictions, prediction)
      |> update_favorite_stream(prediction)
      |> start_account_task(:account_summary, user, false)
      |> start_account_task(:account_favorites, user, false)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    {:ok, prediction} = Predictions.delete_user_prediction(id, user.public_id)

    {:noreply,
     socket
     |> stream_delete(:recent_predictions, prediction)
     |> stream_delete(:favorite_predictions, prediction)
     |> refresh_prediction_sections(user)
     |> put_flash(:info, "Sticker deleted.")}
  end

  def handle_event("retry-section", %{"section" => section}, socket) do
    case Map.fetch(@retry_sections, section) do
      {:ok, task_name} ->
        {:noreply, start_account_task(socket, task_name, socket.assigns.current_user, true)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_async(:account_summary, {:ok, counts}, socket) do
    {:noreply, socket |> assign(:counts, counts) |> assign(:summary_state, :loaded)}
  end

  def handle_async(:account_recent, {:ok, predictions}, socket) do
    {:noreply,
     socket
     |> assign(:recent_state, :loaded)
     |> assign(:recent_empty?, predictions == [])
     |> stream(:recent_predictions, predictions, reset: true)}
  end

  def handle_async(:account_favorites, {:ok, predictions}, socket) do
    {:noreply,
     socket
     |> assign(:favorites_state, :loaded)
     |> assign(:favorites_empty?, predictions == [])
     |> stream(:favorite_predictions, predictions, reset: true)}
  end

  def handle_async(:account_payments, {:ok, {attempts, payments}}, socket) do
    {:noreply,
     socket
     |> assign(:payment_attempts, attempts)
     |> assign(:payments, payments)
     |> assign(:payments_state, :loaded)}
  end

  def handle_async(name, {:exit, _reason}, socket) when name in @account_tasks do
    {:noreply, assign(socket, state_key(name), :failed)}
  end

  defp refresh_account_data(socket) do
    current_user = socket.assigns[:current_user]
    user = current_user && Sticker.Accounts.get_user(current_user.id)

    if is_nil(user) do
      socket
    else
      refresh_account_data(socket, user)
    end
  end

  defp refresh_account_data(socket, user) do
    socket
    |> assign(:current_user, user)
    |> start_account_task(:account_summary, user, false)
    |> start_account_task(:account_payments, user, false)
  end

  defp start_account_loads(socket, user) do
    Enum.reduce(@account_tasks, socket, fn task_name, acc ->
      start_account_task(acc, task_name, user, true)
    end)
  end

  defp start_account_task(socket, task_name, user, show_loading?) do
    socket =
      if show_loading? do
        assign(socket, state_key(task_name), :loading)
      else
        socket
      end

    case task_name do
      :account_summary ->
        start_async(socket, task_name, fn ->
          Sticker.LoadTelemetry.measure(:account_summary, fn ->
            Predictions.user_prediction_counts(user.public_id)
          end)
        end)

      :account_recent ->
        start_async(socket, task_name, fn ->
          Sticker.LoadTelemetry.measure(:account_recent, %{limit: 12}, fn ->
            Predictions.list_user_recent_predictions(user.public_id, 12)
          end)
        end)

      :account_favorites ->
        start_async(socket, task_name, fn ->
          Sticker.LoadTelemetry.measure(:account_favorites, %{limit: 12}, fn ->
            Predictions.list_user_favorite_predictions(user.public_id, 12)
          end)
        end)

      :account_payments ->
        start_async(socket, task_name, fn ->
          Sticker.LoadTelemetry.measure(:account_payments, %{limit: 20}, fn ->
            {Payments.list_user_payment_attempts(user.id),
             Payments.list_user_payment_events(user.id, 20)}
          end)
        end)
    end
  end

  defp refresh_prediction_sections(socket, user) do
    socket
    |> start_account_task(:account_summary, user, false)
    |> start_account_task(:account_recent, user, false)
    |> start_account_task(:account_favorites, user, false)
  end

  defp update_favorite_stream(socket, %{is_favorite: true} = prediction) do
    socket
    |> assign(:favorites_empty?, false)
    |> stream_insert(:favorite_predictions, prediction, at: 0)
  end

  defp update_favorite_stream(socket, prediction) do
    stream_delete(socket, :favorite_predictions, prediction)
  end

  defp state_key(:account_summary), do: :summary_state
  defp state_key(:account_recent), do: :recent_state
  defp state_key(:account_favorites), do: :favorites_state
  defp state_key(:account_payments), do: :payments_state

  defp payment_status(%{refund_status: "refunded"}), do: "Refunded"
  defp payment_status(%{refund_status: "review_required"}), do: "Review required"
  defp payment_status(%{refund_status: "partial_refund_review"}), do: "Partial refund review"
  defp payment_status(_payment), do: "Paid"

  defp checkout_status(%{status: "created"}), do: "Checkout started"
  defp checkout_status(%{status: "open"}), do: "Checkout open"
  defp checkout_status(%{status: "completed"}), do: "Payment received"
  defp checkout_status(%{status: "credited"}), do: "Credits added"
  defp checkout_status(%{status: "canceled"}), do: "Canceled"
  defp checkout_status(%{status: "expired"}), do: "Expired"
  defp checkout_status(%{status: "failed"}), do: "Failed"
  defp checkout_status(_attempt), do: "Checkout started"
end
