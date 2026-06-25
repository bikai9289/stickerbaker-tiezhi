# StickerBaker

<blockquote class="twitter-tweet" data-media-max-width="560"><p lang="en" dir="ltr">Announcing StickerBaker!<br><br>Make stickers with AI. Powered by <a href="https://twitter.com/replicate?ref_src=twsrc%5Etfw">@replicate</a> and <a href="https://twitter.com/flydotio?ref_src=twsrc%5Etfw">@flydotio</a>, and 100% open-source.<a href="https://t.co/8vucCsHtAd">https://t.co/8vucCsHtAd</a> <a href="https://t.co/tBhDyGrOx0">pic.twitter.com/tBhDyGrOx0</a></p>&mdash; Charlie Holtz (@charliebholtz) <a href="https://twitter.com/charliebholtz/status/1762232726361633018?ref_src=twsrc%5Etfw">February 26, 2024</a></blockquote>

## How it works

Enter a prompt and generating a sticker using https://replicate.com/fofr/sticker-maker.

Here's an overview of the architecture:
![](./architecture.png)

The home page is rendered in `lib/sticker_web/home_live.ex`. When the prompt form is submitted, this handle_event gets called:

```elixir
  def handle_event("save", %{"prompt" => prompt}, socket) do
    user_id = socket.assigns.local_user_id

    {:ok, prediction} =
      Predictions.create_prediction(%{
        prompt: prompt,
        local_user_id: user_id
      })

    send(self(), {:kick_off, prediction})

    {:noreply,
     socket
     |> assign(form: to_form(%{"prompt" => ""}))
     |> stream_insert(:my_predictions, prediction, at: 0)}
  end
```

This sends a `:kick_off` message to the LiveView (so there is no lag) which calls `Predictions.moderate/3` in `lib/sticker/predictions.ex`:

```elixir
  @doc """
  Moderates a prediction.
  The logic in replicate_webhook_controller.ex handles
  the webhook. Once the moderation is complete, the webhook controller automatically
  called gen_image.
  """
  def moderate(prompt, user_id, prediction_id) do
    "fofr/prompt-classifier"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_latest_version!()
    |> Replicate.Predictions.create(
      %{
        prompt: "[PROMPT] #{prompt} [/PROMPT] [SAFETY_RANKING]",
        max_new_tokens: 128,
        temperature: 0.2,
        top_p: 0.9,
        top_k: 50,
        stop_sequences: "[/SAFETY_RANKING]"
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end
```

We pass a webhook to [Replicate](https://replicate.com). All the logic for the webhook lives in `lib/sticker_web/controllers/replicate_webhook_controller.ex`. The nice thing about this webhook is that we can refresh the page or disconnect and [Replicate](https://replicate.com) still handles the prediction queue for us. Once the prediction is ready,
we upload it to [Tigris](https://fly.io/docs/reference/tigris/) (Replicate doesn't save our data for us) and then the sticker gets broadcast back to our `home_live.ex`.

**Importantly**, because we're passing Replicate a webhook, for local dev you'll need [ngrok](https://ngrok.com) running to tunnel your localhost to a URL. Once you install ngrok run it with `ngrok http 4000` and paste the URL into your copied `.env` file.

## Stack

StickerBaker runs on:

- [Replicate](https://replicate.com/fofr/sticker-maker?utm_source=project&utm_campaign=stickerbaker) to generate the stickers
- [Fly.io](https://fly.io) for infrastructure
- [Tigris](https://www.tigrisdata.com) for image hosting

## Dev

To start your Phoenix server:

- Run `mix setup` to install and setup dependencies
- Create an env file with `cp .env.copy .env`
  - Add your [Replicate](https://replicate.com) tokens
  - Add [Tigris](https://fly.io/docs/reference/tigris/) tokens
  - Start ngrok with `ngrok http 4000` and add that to your env
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
- Add a .env file with REPLICATE_API_TOKEN set to your [Replicate](https://replicate.com/) token

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Stripe payments

Credit purchases use Stripe Checkout by default. Create two one-time Stripe prices in the Stripe Dashboard and configure these environment variables:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_STARTER_PRICE_ID` for the Starter plan: 50 credits, USD 4.99
- `STRIPE_CREATOR_PRICE_ID` for the Creator plan: 150 credits, USD 9.99
- `PAYMENT_PROVIDER=stripe` is optional because Stripe is the default provider.

Add a Stripe webhook endpoint:

- URL: `https://ai-sticker-maker.com/webhooks/stripe`
- Events: `checkout.session.completed`, `charge.refunded`

For local webhook testing, run the Stripe CLI and forward events to the Phoenix server:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

Use the signing secret printed by the Stripe CLI as `STRIPE_WEBHOOK_SECRET`.

### Production payment checklist

Before enabling public paid traffic:

1. Confirm Stripe live mode has these webhook events enabled:
   - `checkout.session.completed`
   - `charge.refunded`
2. Run a live minimum-value purchase from the deployed domain.
3. Confirm `/account` shows the checkout attempt and the credited payment.
4. Refund that live payment from Stripe Dashboard.
5. Confirm `/account` and `/admin/payments` show the refund state.
6. Rotate any live Stripe secret key that was copied into chat, tickets, logs, or screenshots.
7. Update the deployed `STRIPE_SECRET_KEY` after rotation and restart the app.

Refund policy in code:

- Full refunds automatically remove the original purchased credits if the account balance can cover them.
- Low-balance refunds are marked `review_required`.
- Partial refunds are marked `partial_refund_review`; credits are not automatically changed.

## Prod

Update the `url` and `check_origin` origin in `prod.exs`
Deploy with `fly launch`
Make sure when you `fly launch` you set up a Postgres DB!
