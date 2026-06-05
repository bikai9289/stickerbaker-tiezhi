defmodule StickerWeb.BatchLive do
  use StickerWeb, :live_view

  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def mount(%{"id" => batch_id}, session, socket) do
    local_user_id = session["local_user_id"]
    {batch, predictions} = load_batch(local_user_id, batch_id)

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/stickers/batches/#{batch_id}",
         title: "Sticker Batch",
         description:
           "Review a sticker batch, retry failed prompts, cancel processing items, and download completed stickers."
       )
     )
     |> assign(local_user_id: local_user_id)
     |> assign(batch_id: batch_id)
     |> assign(batch: batch)
     |> assign(download_format: "original")
     |> assign(download_ids: download_ids(predictions))
     |> stream(:predictions, predictions)}
  end

  def handle_event("download-format", %{"format" => format}, socket) do
    {:noreply, assign(socket, download_format: download_format(format))}
  end

  def handle_event("retry-failed", _params, socket) do
    retryable =
      Predictions.list_retryable_batch_predictions(
        socket.assigns.batch_id,
        socket.assigns.local_user_id
      )

    with true <- retryable != [],
         {:ok, current_user} <-
           Sticker.Accounts.spend_credits(socket.assigns.current_user, length(retryable)) do
      predictions =
        retryable
        |> Enum.map(& &1.id)
        |> Predictions.restart_user_predictions(socket.assigns.local_user_id)

      Enum.each(predictions, &send(self(), {:retry_sticker, &1}))

      {:noreply,
       socket
       |> assign(current_user: current_user)
       |> refresh_batch()
       |> put_flash(:info, "#{length(predictions)} failed stickers restarted.")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "No retryable stickers in this batch.")}

      {:error, :insufficient_credits} ->
        {:noreply, put_flash(socket, :error, "Not enough credits to retry this batch.")}

      {:error, :not_signed_in} ->
        {:noreply, put_flash(socket, :error, "Sign in before retrying this batch.")}
    end
  end

  def handle_event("cancel-processing", _params, socket) do
    case Predictions.cancel_user_batch(socket.assigns.batch_id, socket.assigns.local_user_id) do
      {:ok, []} ->
        {:noreply, put_flash(socket, :error, "No processing stickers to cancel.")}

      {:ok, predictions} ->
        current_user =
          socket.assigns.current_user &&
            Sticker.Accounts.get_user(socket.assigns.current_user.id)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> refresh_batch()
         |> put_flash(:info, "#{length(predictions)} stickers canceled and refunded.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not cancel this batch.")}
    end
  end

  def handle_info({:retry_sticker, prediction}, socket) do
    Predictions.moderate(prediction.prompt, prediction.local_user_id, prediction.id)
    {:noreply, socket}
  end

  def failed_reason(prediction) do
    [prediction.failure_stage, prediction.failure_reason]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(": ")
    |> case do
      "" -> "No detailed failure reason recorded."
      reason -> reason
    end
  end

  defp refresh_batch(socket) do
    {batch, predictions} = load_batch(socket.assigns.local_user_id, socket.assigns.batch_id)

    socket
    |> assign(batch: batch)
    |> assign(download_ids: download_ids(predictions))
    |> stream(:predictions, predictions, reset: true)
  end

  defp load_batch(nil, _batch_id), do: {nil, []}

  defp load_batch(local_user_id, batch_id) do
    batch =
      case Predictions.get_user_batch(local_user_id, batch_id) do
        {:ok, batch} -> batch
        {:error, :not_found} -> nil
      end

    {batch, Predictions.list_user_batch_predictions(local_user_id, batch_id)}
  end

  defp download_ids(predictions) do
    predictions
    |> Enum.filter(& &1.sticker_output)
    |> Enum.map(& &1.id)
    |> Enum.join(",")
  end

  defp download_format(format) when format in ["original", "png", "webp"], do: format
  defp download_format(_format), do: "original"
end
