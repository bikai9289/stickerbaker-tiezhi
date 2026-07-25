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

  def sticker(assigns) do
    ~H"""
    <div class={@class}>
      <.image id={@id} prediction={@prediction} />
    </div>
    """
  end

  defp image(assigns) do
    color_index = Enum.random(0..6)

    assigns =
      assigns
      |> assign(:bg, Enum.at(@bgs, color_index))
      |> assign(:text_color, Enum.at(@text_colors, color_index))

    ~H"""
    <.link navigate={~p"/sticker/#{@prediction.id}"} class="saas-generated-link">
      <span class="bg-green-50 bg-blue-50 bg-pink-50 bg-red-50 bg-gray-50 bg-orange-100 bg-teal-50 hidden">
      </span>
      <span class="text-green-500 text-pink-500 text-blue-500 text-red-500 text-gray-500 text-orange-500 text-teal-500 hidden">
      </span>

      <div class={"saas-generated-frame group #{@bg}"}>
        <%= if is_nil(@prediction.sticker_output) and is_nil(@prediction.no_bg_output) do %>
          <div class="saas-generated-placeholder">
            <div role="status" class="saas-card-status">
              <%= if @prediction.status in [:failed, nil] do %>
                <strong><%= status_label(@prediction) %></strong>
                <span><%= status_hint(@prediction) %></span>
                <span :if={credit_returned?(@prediction)} class="saas-status-pill">
                  Credit returned
                </span>
              <% else %>
                <span class="saas-card-spinner"></span>
                <strong><%= status_label(@prediction) %></strong>
                <span><%= status_hint(@prediction) %></span>
              <% end %>
            </div>
          </div>
        <% else %>
          <img
            src={@prediction.sticker_output}
            alt={@prediction.prompt}
            class="saas-generated-image pointer-events-none group-hover:opacity-75"
          />
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
    """
  end

  defp status_label(%{status: :processing}), do: "Generating"
  defp status_label(%{status: :moderation_succeeded}), do: "Queued"
  defp status_label(%{status: :starting, model: "face-to-sticker"}), do: "Preparing portrait"
  defp status_label(%{status: :starting}), do: "Checking prompt"
  defp status_label(%{status: :failed}), do: "No result"
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
  defp status_hint(%{status: nil}), do: "This older generation did not finish."
  defp status_hint(_prediction), do: "Waiting for the generated image."

  defp credit_returned?(%{status: :failed, credit_refunded: true}), do: true
  defp credit_returned?(_prediction), do: false
end
