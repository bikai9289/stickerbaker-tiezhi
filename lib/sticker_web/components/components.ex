defmodule StickerWeb.Components do
  use StickerWeb, :html

  @bgs [
    "bg-green-50",
    "bg-pink-50",
    "bg-blue-50",
    "bg-red-50",
    "bg-gray-50",
    "bg-orange-100",
    "bg-teal-50"
  ]
  @text_colors [
    "text-green-300",
    "text-pink-300",
    "text-blue-300",
    "text-red-300",
    "text-gray-300",
    "text-orange-300",
    "text-teal-300"
  ]

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :prediction, :map, required: true
  attr :cancel_event, :string, default: nil
  attr :eager, :boolean, default: false

  def sticker(assigns) do
    ~H"""
    <div
      id={"#{@id}-generation"}
      class={@class}
      data-generation-state={prediction_state(@prediction)}
      data-generation-context="generation_card"
      phx-hook={if active_generation?(@prediction), do: "GenerationStatus"}
    >
      <.image id={@id} prediction={@prediction} cancel_event={@cancel_event} eager={@eager} />
    </div>
    """
  end

  defp image(assigns) do
    color_index = rem(abs(assigns.prediction.id || 0), length(@bgs))

    assigns =
      assigns
      |> assign(:bg, Enum.at(@bgs, color_index))
      |> assign(:text_color, Enum.at(@text_colors, color_index))
      |> assign(:output, assigns.prediction.sticker_output || assigns.prediction.no_bg_output)
      |> assign(:active?, active_generation?(assigns.prediction))
      |> assign(:phase, generation_phase(assigns.prediction))

    ~H"""
    <.link navigate={~p"/sticker/#{@prediction.id}"} class="saas-generated-link">
      <span class="bg-green-50 bg-blue-50 bg-pink-50 bg-red-50 bg-gray-50 bg-orange-100 bg-teal-50 hidden">
      </span>
      <span class="text-green-500 text-pink-500 text-blue-500 text-red-500 text-gray-500 text-orange-500 text-teal-500 hidden">
      </span>
      <div
        id={"#{@id}-preview"}
        class={"saas-generated-frame group #{@bg}"}
        phx-hook="PreviewImage"
        data-preview-context="generation_card"
        data-preview-state={if @output, do: "loading", else: "unavailable"}
      >
        <%= if is_nil(@output) do %>
          <div class="saas-generated-placeholder">
            <div role="status" class="saas-card-status">
              <%= if @active? do %>
                <span class="saas-card-spinner"></span>
                <strong><%= status_label(@prediction) %></strong>
                <span><%= status_hint(@prediction) %></span>
                <ol
                  class="saas-generation-phases"
                  data-active-phase={@phase}
                  aria-label="Generation progress"
                >
                  <li data-phase-state={phase_state(@phase, 1)}>Checking input</li>
                  <li data-phase-state={phase_state(@phase, 2)}>Queued</li>
                  <li data-phase-state={phase_state(@phase, 3)}>Creating sticker</li>
                </ol>
                <p data-slow-message hidden>
                  This is taking longer than usual. You can keep waiting or cancel for a refund.
                </p>
              <% else %>
                <strong><%= status_label(@prediction) %></strong>
                <span><%= status_hint(@prediction) %></span>
                <span :if={credit_returned?(@prediction)} class="saas-status-pill">
                  Credit returned
                </span>
              <% end %>
            </div>
          </div>
        <% else %>
          <img
            src={@output}
            alt={@prediction.prompt}
            class="saas-generated-image pointer-events-none group-hover:opacity-75"
            loading={if @eager, do: "eager", else: "lazy"}
            fetchpriority={if @eager, do: "high", else: "auto"}
            decoding="async"
            width="1024"
            height="1024"
          />
          <span data-preview-error hidden>
            Preview could not be loaded. Retry below.
          </span>
        <% end %>
      </div>

      <div class="saas-generated-caption">
        <span>
          <%= @prediction.prompt %>
        </span>

        <span :if={@prediction.score > 0} class={@text_color}>
          <%= @prediction.score %>
        </span>
      </div>
    </.link>

    <div
      :if={not is_nil(@output) or (@active? and not is_nil(@cancel_event))}
      class="saas-generated-actions"
    >
      <.link
        :if={@prediction.status == :succeeded and not is_nil(@output)}
        href={~p"/sticker/#{@prediction.id}/download"}
        data-analytics-event="download_click"
        data-analytics-context="generation_card"
        data-analytics-download-type="single"
        data-analytics-format="original"
      >
        Download
      </.link>

      <button type="button" data-preview-retry hidden>
        Retry preview
      </button>

      <details :if={@active? and @cancel_event} class="saas-cancel-confirm">
        <summary>Cancel &amp; refund</summary>
        <p>Cancel this generation and return 1 credit?</p>
        <button
          type="button"
          phx-click={@cancel_event}
          phx-value-id={@prediction.id}
          phx-disable-with="Canceling..."
          data-analytics-event="generation_cancel_attempt"
          data-analytics-context="generation_card"
        >
          Cancel generation
        </button>
      </details>
    </div>
    """
  end

  defp status_label(%{status: :processing}), do: "Creating sticker"
  defp status_label(%{status: :moderation_succeeded}), do: "Queued"
  defp status_label(%{status: :starting, model: "face-to-sticker"}), do: "Preparing portrait"
  defp status_label(%{status: :starting}), do: "Checking input"
  defp status_label(%{status: :failed}), do: "Generation failed"
  defp status_label(%{status: :canceled}), do: "Generation canceled"
  defp status_label(%{status: :succeeded}), do: "Preview unavailable"
  defp status_label(%{status: nil}), do: "Unavailable"
  defp status_label(_prediction), do: "Generating"

  defp status_hint(%{status: :processing}), do: "The image service is creating your sticker."
  defp status_hint(%{status: :moderation_succeeded}), do: "Queued for image generation."

  defp status_hint(%{status: :starting, model: "face-to-sticker"}),
    do: "Checking the portrait and preparing the image."

  defp status_hint(%{status: :starting}), do: "Running a safety check before generation."

  defp status_hint(%{status: :failed, model: "face-to-sticker"}),
    do: "Try again with a clear, front-facing portrait."

  defp status_hint(%{status: :failed}), do: "Try again with a shorter, clearer prompt."
  defp status_hint(%{status: :canceled}), do: "This generation was stopped before completion."
  defp status_hint(%{status: :succeeded}), do: "The generated file is not available to download."
  defp status_hint(%{status: nil}), do: "This older generation did not finish."
  defp status_hint(_prediction), do: "Waiting for the generated image."

  defp active_generation?(%{status: status}),
    do: status in [:starting, :moderation_succeeded, :processing]

  defp generation_phase(%{status: :starting}), do: 1
  defp generation_phase(%{status: :moderation_succeeded}), do: 2
  defp generation_phase(%{status: :processing}), do: 3
  defp generation_phase(_prediction), do: nil

  defp phase_state(active_phase, phase) when phase < active_phase, do: "complete"
  defp phase_state(active_phase, phase) when phase == active_phase, do: "active"
  defp phase_state(_active_phase, _phase), do: "upcoming"

  defp prediction_state(%{status: nil}), do: "unavailable"
  defp prediction_state(%{status: status}), do: to_string(status)

  defp credit_returned?(%{status: status, credit_refunded: true})
       when status in [:failed, :canceled],
       do: true

  defp credit_returned?(_prediction), do: false
end
