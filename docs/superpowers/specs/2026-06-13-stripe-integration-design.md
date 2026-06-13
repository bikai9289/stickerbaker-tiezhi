# Stripe Integration Design

## Goal

Use Stripe as the primary checkout provider for credit purchases. A signed Stripe webhook should add credits after a successful Checkout payment, and Stripe refund events should either deduct the original credits or mark the payment for manual review when the user no longer has enough credits.

## Current Context

The application already has a Phoenix checkout flow:

- `/pricing` posts selected plans to `/checkout`.
- `StickerWeb.CheckoutController` redirects signed-in users to a provider checkout URL.
- `Sticker.Payments` already creates Stripe Checkout Sessions using `STRIPE_SECRET_KEY` and plan-specific Stripe price IDs.
- `/webhooks/stripe` verifies Stripe signatures and fulfills `checkout.session.completed`.
- `payment_events` records provider, session/event IDs, credits, plan, provider order ID, and refund status.
- Creem remains implemented as an alternate provider behind `PAYMENT_PROVIDER=creem`.

## Chosen Approach

Keep Stripe as the default provider and preserve the existing Creem path as a fallback. This avoids unnecessary removal risk while making the production path Stripe-first.

The implementation will:

- Keep one-time Stripe Checkout Sessions for credit purchases.
- Continue using Stripe-hosted Checkout instead of adding card collection UI.
- Add Stripe refund webhook handling.
- Reuse the existing payment event table and refund status fields.
- Share refund bookkeeping between Stripe and Creem where practical.

## User Flow

1. Signed-in user selects a credit plan on `/pricing`.
2. `/checkout` validates the plan and user, then calls `Payments.create_checkout_session/4`.
3. With the default provider, `Payments.create_stripe_checkout_session/4` creates a Stripe Checkout Session.
4. Stripe redirects the user to hosted Checkout.
5. On payment completion, Stripe sends `checkout.session.completed` to `/webhooks/stripe`.
6. The webhook signature is verified with `STRIPE_WEBHOOK_SECRET`.
7. The app records the payment event and adds the configured credits.
8. Duplicate checkout webhooks are idempotent because the payment event has a unique session ID.

## Refund Flow

Stripe refund events should be handled by `/webhooks/stripe`.

The implementation should support the practical event shape from Stripe, starting with `charge.refunded`. The handler should extract the charge ID and, when available, the payment intent ID. The original checkout fulfillment should store a Stripe lookup ID that lets refunds find the corresponding payment event.

Refund bookkeeping:

- If the payment event has not already been refunded and the user's current credit balance is at least the purchased credit amount, deduct the purchased credits and mark the event `refunded`.
- If the user's balance is lower than the purchased credits, keep the balance unchanged and mark the event `review_required`.
- If the same refund webhook arrives again, return `:ok` without changing credits again.
- If no matching payment is found, return `:ok` to keep webhook delivery idempotent.

## Data Model

No new table is required.

The existing `payment_events` schema will be reused:

- `stripe_session_id`: keeps the Checkout Session ID.
- `stripe_event_id`: stores the fulfillment webhook event ID.
- `provider`: remains `stripe` or `creem`.
- `provider_order_id`: will store a Stripe lookup ID, preferably `payment_intent`, for Stripe payments.
- `refund_event_id`: stores the Stripe refund webhook event ID.
- `refund_status`: remains `none`, `refunded`, or `review_required`.

## Configuration

Required production variables:

- `PAYMENT_PROVIDER=stripe` or omitted, since Stripe is the default.
- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_STARTER_PRICE_ID`
- `STRIPE_CREATOR_PRICE_ID`

Stripe Dashboard setup:

- Create two one-time prices:
  - Starter: 50 credits, USD 4.99
  - Creator: 150 credits, USD 9.99
- Add webhook endpoint: `https://<host>/webhooks/stripe`
- Listen for:
  - `checkout.session.completed`
  - `charge.refunded`

## Error Handling

- Missing Stripe keys or price IDs return `:checkout_not_configured` and the controller shows the existing friendly checkout error.
- Invalid webhook signatures return HTTP 400.
- Unsupported Stripe events return HTTP 200 with no action.
- Duplicate fulfillment or refund events are idempotent.

## Testing

Add or update tests for:

- `fulfill_checkout/2` adds credits and records `provider: "stripe"`.
- Duplicate Stripe checkout fulfillment does not add credits twice.
- Stripe webhook signature verification accepts valid signatures and rejects invalid ones.
- Stripe refund handling deducts credits when the balance can cover the refund.
- Stripe refund handling marks `review_required` when the balance is too low.
- Stripe refund handling is idempotent.

## Out of Scope

- Subscription billing.
- Customer portal.
- Tax calculation.
- Removing Creem code.
- Creating Stripe products through the Stripe API.
