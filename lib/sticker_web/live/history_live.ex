defmodule StickerWeb.HistoryLive do
  use StickerWeb, :live_view
  alias Sticker.GenerationCredits
  alias Sticker.GuestTrials
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO
  @per_page 24
  @history_statuses ["all", "completed", "processing", "failed", "canceled", "favorites"]

  def mount(params, session, socket) do
    local_user_id = session["local_user_id"]
    filters = initial_filters(params)

    socket =
      socket
      |> SEO.assign(
        PageSEO.noindex("/stickers",
          title: "Sticker History",
          description:
            "View and manage your generated AI sticker history, saved stickers, and downloads."
        )
      )
      |> assign(local_user_id: local_user_id)
      |> assign(guest_trial: nil)
      |> assign(filters: filters)
      |> assign(batches: [])
      |> assign(batches_state: :loading)
      |> assign(history_state: :loading)
      |> assign(load_more_state: :idle)
      |> assign(history_request_ref: nil)
      |> assign(history_more_ref: nil)
      |> assign(page: 0)
      |> assign(per_page: @per_page)
      |> assign(has_more?: false)
      |> assign(prediction_count: 0)
      |> assign(shown_count: 0)
      |> assign(history_eager_ids: [])
      |> assign(selected_ids: MapSet.new())
      |> assign(download_format: "original")
      |> assign(results: [])
      |> stream(:predictions, [])

    socket =
      if connected?(socket) and is_binary(local_user_id) do
        socket
        |> assign(guest_trial: guest_trial_for(socket.assigns[:current_user], local_user_id))
        |> start_history_page(local_user_id, filters)
        |> start_history_batches(local_user_id, true)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event(
        "assign-user-id",
        %{"userId" => user_id},
        %{assigns: %{local_user_id: user_id}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(local_user_id: user_id)
     |> assign(guest_trial: guest_trial_for(socket.assigns[:current_user], user_id))
     |> start_history_page(user_id, socket.assigns.filters)
     |> start_history_batches(user_id, true)}
  end

  def handle_event("filter", params, socket) do
    filters = %{
      status: Map.get(params, "status", socket.assigns.filters.status),
      query: Map.get(params, "query", socket.assigns.filters.query),
      batch_id: Map.get(params, "batch_id", socket.assigns.filters.batch_id)
    }

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(selected_ids: MapSet.new())
     |> start_history_page(socket.assigns.local_user_id, filters)}
  end

  def handle_event("load-more", _params, %{assigns: %{load_more_state: :loading}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load-more", _params, %{assigns: %{has_more?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load-more", _params, socket) do
    next_page = socket.assigns.page + 1
    ref = next_request_ref()
    user_id = socket.assigns.local_user_id
    filters = socket.assigns.filters
    per_page = socket.assigns.per_page

    {:noreply,
     socket
     |> assign(load_more_state: :loading, history_more_ref: ref)
     |> start_async({:history_more, ref, next_page}, fn ->
       Sticker.LoadTelemetry.measure(:history_more, %{page: next_page, per_page: per_page}, fn ->
         Predictions.paginate_user_predictions(user_id, filters, next_page, per_page)
       end)
     end)}
  end

  def handle_event("retry-history", _params, socket) do
    {:noreply, start_history_page(socket, socket.assigns.local_user_id, socket.assigns.filters)}
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
    user_id = socket.assigns.local_user_id

    {:noreply,
     socket
     |> assign(selected_ids: MapSet.new())
     |> start_history_page(user_id, socket.assigns.filters)
     |> start_history_batches(user_id, false)
     |> put_flash(:info, "#{count} stickers deleted.")}
  end

  def handle_event("retry", %{"id" => id}, socket) do
    case Predictions.retry_user_prediction(id, socket.assigns.local_user_id) do
      {:ok, _prediction} ->
        retry_prediction(socket, id)

      {:error, :not_retryable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This older upload sticker has no saved source image. Upload it again."
         )}
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
         |> assign(prediction_count: socket.assigns.prediction_count)
         |> stream_insert(:predictions, prediction)
         |> start_history_batches(socket.assigns.local_user_id, false)
         |> put_flash(:info, "Generation canceled and 1 credit was refunded.")}

      {:error, :not_cancelable} ->
        {:noreply,
         put_flash(socket, :error, "Only queued or processing stickers can be canceled.")}
    end
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.toggle_favorite(id, socket.assigns.local_user_id)

    if socket.assigns.filters.status == "favorites" do
      {:noreply, start_history_page(socket, socket.assigns.local_user_id, socket.assigns.filters)}
    else
      {:noreply, stream_insert(socket, :predictions, prediction)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.delete_user_prediction(id, socket.assigns.local_user_id)

    {:noreply,
     socket
     |> assign(prediction_count: max(socket.assigns.prediction_count - 1, 0))
     |> assign(shown_count: max(socket.assigns.shown_count - 1, 0))
     |> stream_delete(:predictions, prediction)
     |> start_history_batches(socket.assigns.local_user_id, false)
     |> put_flash(:info, "Sticker deleted.")}
  end

  def handle_async(
        {:history_page, ref},
        {:ok, page},
        %{assigns: %{history_request_ref: ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(history_state: :loaded, shown_count: length(page.entries))
     |> assign(history_eager_ids: eager_prediction_ids(page.entries))
     |> assign_page(page)
     |> stream(:predictions, page.entries, reset: true)}
  end

  def handle_async(
        {:history_page, ref},
        {:exit, _reason},
        %{assigns: %{history_request_ref: ref}} = socket
      ) do
    {:noreply, assign(socket, :history_state, :failed)}
  end

  def handle_async({:history_page, _stale_ref}, _result, socket), do: {:noreply, socket}

  def handle_async(
        {:history_more, ref, _page_number},
        {:ok, page},
        %{assigns: %{history_more_ref: ref}} = socket
      ) do
    shown_count = min(socket.assigns.shown_count + length(page.entries), page.total)

    {:noreply,
     socket
     |> assign(load_more_state: :idle, shown_count: shown_count)
     |> assign_page(page)
     |> stream(:predictions, page.entries)}
  end

  def handle_async(
        {:history_more, ref, _page_number},
        {:exit, _reason},
        %{assigns: %{history_more_ref: ref}} = socket
      ) do
    {:noreply, assign(socket, :load_more_state, :failed)}
  end

  def handle_async({:history_more, _stale_ref, _page_number}, _result, socket),
    do: {:noreply, socket}

  def handle_async(:history_batches, {:ok, batches}, socket) do
    {:noreply, assign(socket, batches: batches, batches_state: :loaded)}
  end

  def handle_async(:history_batches, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :batches_state, :failed)}
  end

  def handle_info({:retry_sticker, prediction}, socket) do
    StickerWeb.PredictionRetry.start(prediction)
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

  defp initial_filters(params) do
    status = Map.get(params, "status", "all")
    query = Map.get(params, "query", "")
    batch_id = Map.get(params, "batch_id", "all")

    %{
      status: if(status in @history_statuses, do: status, else: "all"),
      query: if(is_binary(query), do: String.slice(query, 0, 200), else: ""),
      batch_id: if(is_binary(batch_id) and batch_id != "", do: batch_id, else: "all")
    }
  end

  defp start_history_page(socket, user_id, filters) do
    ref = next_request_ref()
    per_page = socket.assigns.per_page

    socket
    |> assign(
      history_request_ref: ref,
      history_more_ref: nil,
      history_state: :loading,
      load_more_state: :idle,
      shown_count: 0
    )
    |> assign_page(empty_page())
    |> stream(:predictions, [], reset: true)
    |> start_async({:history_page, ref}, fn ->
      Sticker.LoadTelemetry.measure(:history_page, %{page: 0, per_page: per_page}, fn ->
        Predictions.paginate_user_predictions(user_id, filters, 0, per_page)
      end)
    end)
  end

  defp start_history_batches(socket, user_id, show_loading?) do
    socket =
      if show_loading? do
        assign(socket, :batches_state, :loading)
      else
        socket
      end

    start_async(socket, :history_batches, fn ->
      Sticker.LoadTelemetry.measure(:history_batches, fn ->
        Predictions.list_user_batches(user_id)
      end)
    end)
  end

  defp next_request_ref, do: System.unique_integer([:positive, :monotonic])

  defp eager_prediction_ids(predictions) do
    predictions |> Enum.take(4) |> Enum.map(& &1.id)
  end

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

  defp retry_prediction(socket, id) do
    user_id = socket.assigns.local_user_id

    case GenerationCredits.spend(socket.assigns.current_user, user_id, 1) do
      {:ok, credit_result} ->
        case Predictions.restart_user_prediction(id, user_id, credit_attrs(credit_result)) do
          {:ok, prediction} ->
            send(self(), {:retry_sticker, prediction})

            {:noreply,
             socket
             |> assign_credit_result(credit_result)
             |> assign(prediction_count: socket.assigns.prediction_count)
             |> stream_insert(:predictions, prediction)
             |> start_history_batches(user_id, false)
             |> put_flash(:info, "Retry started. 1 credit was used.")}

          {:error, _reason} ->
            {:ok, refreshed} =
              GenerationCredits.refund(
                credit_result.credit_source,
                credit_result.credit_owner_id,
                1
              )

            {:noreply,
             socket
             |> assign_credit_result(refresh_credit_result(credit_result, refreshed))
             |> put_flash(:error, "Could not restart this sticker. Your credit was refunded.")}
        end

      {:error, :guest_insufficient_credits} ->
        {:noreply,
         put_flash(socket, :error, "No guest trial generations left to retry this sticker.")}

      {:error, :insufficient_credits} ->
        {:noreply, put_flash(socket, :error, "Not enough credits to retry this sticker.")}

      {:error, :missing_guest_identity} ->
        {:noreply, put_flash(socket, :error, "Refresh the page or sign in before retrying.")}

      {:error, :invalid_guest_identity} ->
        {:noreply, put_flash(socket, :error, "Refresh the page or sign in before retrying.")}

      {:error, :not_signed_in} ->
        {:noreply, put_flash(socket, :error, "Sign in before retrying this sticker.")}
    end
  end

  defp credit_attrs(credit_result) do
    %{
      credit_source: credit_result.credit_source,
      credit_owner_id: credit_result.credit_owner_id
    }
  end

  defp guest_trial_for(nil, local_user_id) when is_binary(local_user_id) do
    case GuestTrials.get_or_create_allowance(local_user_id) do
      {:ok, guest_trial} -> guest_trial
      {:error, _reason} -> nil
    end
  end

  defp guest_trial_for(_current_user, _local_user_id), do: nil

  defp assign_credit_result(socket, %{current_user: current_user, guest_trial: guest_trial}) do
    socket
    |> assign(current_user: current_user)
    |> assign(guest_trial: guest_trial)
  end

  defp refresh_credit_result(%{credit_source: "guest"} = credit_result, refreshed),
    do: %{credit_result | guest_trial: refreshed}

  defp refresh_credit_result(%{credit_source: "account"} = credit_result, refreshed),
    do: %{credit_result | current_user: refreshed}
end
