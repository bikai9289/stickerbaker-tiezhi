defmodule StickerWeb.HistoryLive do
  use StickerWeb, :live_view
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO
  @per_page 24

  def mount(_params, session, socket) do
    local_user_id = session["local_user_id"]
    filters = %{status: "all", query: "", batch_id: "all"}
    page = if local_user_id, do: Predictions.paginate_user_predictions(local_user_id, filters), else: empty_page()
    batches = Predictions.list_user_batches(local_user_id)

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/stickers",
         title: "Sticker History",
         description: "View and manage your generated AI sticker history, saved stickers, and downloads."
       )
     )
     |> assign(local_user_id: local_user_id)
     |> assign(filters: filters)
     |> assign(batches: batches)
     |> assign(page: page.page)
     |> assign(per_page: page.per_page)
     |> assign(has_more?: page.has_more?)
     |> assign(prediction_count: page.total)
     |> assign(selected_ids: MapSet.new())
     |> assign(download_format: "original")
     |> assign(results: [])
     |> stream(:predictions, page.entries)}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    page = Predictions.paginate_user_predictions(user_id, socket.assigns.filters, 0, socket.assigns.per_page)

    {:noreply,
     socket
     |> assign(local_user_id: user_id)
     |> assign(batches: Predictions.list_user_batches(user_id))
     |> assign_page(page)
     |> stream(:predictions, page.entries, reset: true)}
  end

  def handle_event("filter", params, socket) do
    filters = %{
      status: Map.get(params, "status", socket.assigns.filters.status),
      query: Map.get(params, "query", socket.assigns.filters.query),
      batch_id: Map.get(params, "batch_id", socket.assigns.filters.batch_id)
    }
    page = Predictions.paginate_user_predictions(socket.assigns.local_user_id, filters, 0, socket.assigns.per_page)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(selected_ids: MapSet.new())
     |> assign_page(page)
     |> stream(:predictions, page.entries, reset: true)}
  end

  def handle_event("load-more", _params, socket) do
    next_page = socket.assigns.page + 1

    page =
      Predictions.paginate_user_predictions(
        socket.assigns.local_user_id,
        socket.assigns.filters,
        next_page,
        socket.assigns.per_page
      )

    {:noreply,
     socket
     |> assign_page(page)
     |> stream(:predictions, page.entries)}
  end

  def handle_event("set-download-format", %{"format" => format}, socket) do
    {:noreply, assign(socket, download_format: download_format(format))}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected_ids = socket.assigns.selected_ids

    selected_ids =
      if MapSet.member?(selected_ids, id),
        do: MapSet.delete(selected_ids, id),
        else: MapSet.put(selected_ids, id)

    {:noreply, assign(socket, selected_ids: selected_ids)}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("delete-selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)
    {count, _} = Predictions.delete_user_predictions(ids, socket.assigns.local_user_id)
    page = Predictions.paginate_user_predictions(socket.assigns.local_user_id, socket.assigns.filters, 0, socket.assigns.per_page)

    {:noreply,
     socket
     |> assign(selected_ids: MapSet.new())
     |> assign(batches: Predictions.list_user_batches(socket.assigns.local_user_id))
     |> assign_page(page)
     |> stream(:predictions, page.entries, reset: true)
     |> put_flash(:info, "#{count} stickers deleted.")}
  end

  def handle_event("retry", %{"id" => id}, socket) do
    with {:ok, _prediction} <- Predictions.retry_user_prediction(id, socket.assigns.local_user_id),
         {:ok, current_user} <- Sticker.Accounts.spend_credit(socket.assigns.current_user),
         {:ok, prediction} <- Predictions.restart_user_prediction(id, socket.assigns.local_user_id) do
      send(self(), {:retry_sticker, prediction})

      {:noreply,
       socket
       |> assign(current_user: current_user)
       |> assign(batches: Predictions.list_user_batches(socket.assigns.local_user_id))
       |> assign(prediction_count: socket.assigns.prediction_count)
       |> stream_insert(:predictions, prediction)
       |> put_flash(:info, "Retry started. 1 credit was used.")}
    else
      {:error, :insufficient_credits} ->
        {:noreply, put_flash(socket, :error, "Not enough credits to retry this sticker.")}

      {:error, :not_signed_in} ->
        {:noreply, put_flash(socket, :error, "Sign in before retrying this sticker.")}

      {:error, :not_retryable} ->
        {:noreply, put_flash(socket, :error, "Upload-based stickers must be regenerated from a new upload.")}

      {:error, _reason} ->
        current_user =
          socket.assigns.current_user &&
            Sticker.Accounts.refund_credit(socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> put_flash(:error, "Could not restart this sticker. Your credit was refunded.")}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    case Predictions.cancel_user_prediction(id, socket.assigns.local_user_id) do
      {:ok, prediction} ->
        current_user =
          socket.assigns.current_user &&
            Sticker.Accounts.get_user(socket.assigns.current_user.id)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> assign(batches: Predictions.list_user_batches(socket.assigns.local_user_id))
         |> assign(prediction_count: socket.assigns.prediction_count)
         |> stream_insert(:predictions, prediction)
         |> put_flash(:info, "Generation canceled and 1 credit was refunded.")}

      {:error, :not_cancelable} ->
        {:noreply, put_flash(socket, :error, "Only queued or processing stickers can be canceled.")}
    end
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.toggle_favorite(id, socket.assigns.local_user_id)
    {:noreply, stream_insert(socket, :predictions, prediction)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.delete_user_prediction(id, socket.assigns.local_user_id)

    {:noreply,
     socket
     |> assign(batches: Predictions.list_user_batches(socket.assigns.local_user_id))
     |> assign(prediction_count: max(socket.assigns.prediction_count - 1, 0))
     |> stream_delete(:predictions, prediction)
     |> put_flash(:info, "Sticker deleted.")}
  end

  def handle_info({:retry_sticker, prediction}, socket) do
    Predictions.moderate(prediction.prompt, prediction.local_user_id, prediction.id)
    {:noreply, socket}
  end

  def selected?(selected_ids, id), do: MapSet.member?(selected_ids, id)

  def selected_ids_param(selected_ids) do
    selected_ids
    |> MapSet.to_list()
    |> Enum.join(",")
  end

  def download_format_param("png"), do: "png"
  def download_format_param("webp"), do: "webp"
  def download_format_param(_format), do: "original"

  def processing?(prediction),
    do: prediction.status in [:starting, :processing, :moderation_succeeded]

  def failed_or_canceled?(prediction), do: prediction.status in [:failed, :canceled]

  def batch_label(%{batch_id: batch_id, total: total, completed: completed, failed: failed}) do
    "#{String.replace_prefix(batch_id, "batch-", "Batch ")} - #{completed}/#{total} done, #{failed} failed"
  end

  defp download_format(format) when format in ["original", "png", "webp"], do: format
  defp download_format(_format), do: "original"

  defp assign_page(socket, page) do
    socket
    |> assign(page: page.page)
    |> assign(per_page: page.per_page)
    |> assign(has_more?: page.has_more?)
    |> assign(prediction_count: page.total)
  end

  defp empty_page do
    %{entries: [], page: 0, per_page: @per_page, total: 0, has_more?: false}
  end
end
