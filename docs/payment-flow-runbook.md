# Payment Flow Runbook

This runbook covers production Stripe credit purchases for AI Sticker Maker. Use it before price changes, after payment deployments, and during payment or refund incidents.

## Production Shape

- Site: `https://ai-sticker-maker.com`
- App host: Tencent Cloud VM, Docker Compose in `/opt/stickerbaker`
- Public app container: `stickerbaker-app`
- Database container: `stickerbaker-db`
- Public reverse proxy: Caddy, forwarding the domain to app port `4000`
- Stripe webhook endpoint: `https://ai-sticker-maker.com/webhooks/stripe`
- Required Stripe events:
  - `checkout.session.completed`
  - `charge.refunded`

## Plans

| Plan | Credits | Display Price | Amount | Currency | Env Var |
| --- | ---: | --- | ---: | --- | --- |
| Starter | 50 | `$4.99` | `499` | `usd` | `STRIPE_STARTER_PRICE_ID` |
| Creator | 150 | `$9.99` | `999` | `usd` | `STRIPE_CREATOR_PRICE_ID` |

The runtime plan, Stripe Price object, and public `/pricing` page must agree before the payment flow is considered ready.

## Read-Only Production Checks

Run commands through SSH as an operator with key access. Do not print `.env`, API keys, webhook secrets, passwords, or full Docker environment output.

```bash
cd /opt/stickerbaker
docker compose ps
```

Verify runtime plans:

```bash
docker exec stickerbaker-app /app/bin/sticker eval '
Enum.each(["starter", "creator"], fn id ->
  p = Sticker.Payments.get_plan(id)
  price_id = System.get_env(p.env, "")
  IO.puts([p.id, p.price, Integer.to_string(p.amount), p.currency, Integer.to_string(p.credits), price_id] |> Enum.join("|"))
end)'
```

Expected:

```text
starter|$4.99|499|usd|50|price_...
creator|$9.99|999|usd|150|price_...
```

Verify the public pricing page:

```bash
curl -fsS https://ai-sticker-maker.com/pricing | grep -Eo '\$[0-9]+\.[0-9]{2}|Buy [0-9]+ Credits' | sort | uniq -c
```

Expected:

```text
1 $4.99
1 $9.99
1 Buy 150 Credits
1 Buy 50 Credits
```

Verify Stripe Price objects without exposing secrets:

```bash
cd /opt/stickerbaker
set -a
. ./.env
set +a
python3 - <<'PY'
import os, json, urllib.request

key = os.environ["STRIPE_SECRET_KEY"]

def stripe_get(path):
    req = urllib.request.Request(
        "https://api.stripe.com" + path,
        headers={"Authorization": "Bearer " + key},
    )
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.loads(response.read().decode())

for price_id in [os.environ["STRIPE_STARTER_PRICE_ID"], os.environ["STRIPE_CREATOR_PRICE_ID"]]:
    p = stripe_get("/v1/prices/" + price_id)
    print(
        "price|{}|active={}|livemode={}|amount={}|currency={}|type={}".format(
            p["id"], p["active"], p["livemode"], p["unit_amount"], p["currency"], p["type"]
        )
    )
PY
```

Expected:

```text
price|price_...|active=True|livemode=True|amount=499|currency=usd|type=one_time
price|price_...|active=True|livemode=True|amount=999|currency=usd|type=one_time
```

## Checkout Verification

After a signed-in user buys credits through Stripe Checkout, verify:

```bash
docker exec stickerbaker-db psql -U sticker -d sticker_prod -F '|' -Atc \
"select id,user_id,provider,plan,credits,amount,currency,status,stripe_price_id,stripe_session_id,provider_order_id,inserted_at,updated_at from payment_attempts order by id desc limit 5;"
```

The matching attempt must show:

- `provider`: `stripe`
- `plan`: purchased plan, such as `starter`
- `credits`: purchased credits
- `amount`: plan amount in cents
- `currency`: `usd`
- `status`: `credited` after webhook fulfillment
- `stripe_price_id`: active live Price ID
- `stripe_session_id`: Checkout Session ID

Then verify the ledger:

```bash
docker exec stickerbaker-db psql -U sticker -d sticker_prod -F '|' -Atc \
"select id,user_id,provider,plan,credits,amount,currency,stripe_price_id,stripe_session_id,provider_order_id,stripe_event_id,refund_status,refund_event_id,refunded_at,inserted_at,updated_at from payment_events order by id desc limit 5;"
```

The matching payment event must show:

- `provider`: `stripe`
- `provider_order_id`: Stripe PaymentIntent ID
- `stripe_event_id`: `checkout.session.completed` event ID
- `refund_status`: `none` before refund, or the current refund state after refund processing

Verify webhook processing:

```bash
docker exec stickerbaker-db psql -U sticker -d sticker_prod -F '|' -Atc \
"select id,provider,stripe_event_id,event_type,livemode,status,error_reason,inserted_at,updated_at from payment_webhook_events order by id desc limit 10;"
```

The `checkout.session.completed` row must be `processed`.

## Refund Verification

After issuing a full Stripe refund, verify:

- Stripe refund API or Dashboard shows a successful refund.
- A `charge.refunded` webhook row exists and is `processed`.
- The matching `payment_events` row moved to `refund_status = refunded`.
- `refund_event_id` and `refunded_at` are present.
- User credits decreased by the purchased credits if the user balance can cover the deduction.

Check the user:

```bash
docker exec stickerbaker-db psql -U sticker -d sticker_prod -F '|' -Atc \
"select id,email,credits from users where email='<customer email>';"
```

Application credit rollback is immediate after the webhook is processed. Card or bank settlement is separate and can take several business days depending on the payment method and issuing bank.

## Refund Review States

| State | Meaning | Operator Action |
| --- | --- | --- |
| `none` | Paid, not refunded | No action |
| `refunded` | Full refund processed and credits deducted | Confirm account and Stripe record |
| `review_required` | Full refund received but user balance was too low to deduct credits | Manually review account and credit usage |
| `partial_refund_review` | Partial refund received | Manually decide credit adjustment |

## Deployment

Use for payment-related production changes:

```bash
cd /opt/stickerbaker
docker compose build app
docker compose up -d app
docker exec stickerbaker-app /app/bin/migrate
docker compose ps
docker logs --tail 100 stickerbaker-app
```

Then run the runtime plan, `/pricing`, Stripe Price, webhook, and database checks above.

## Price Rollback

If a temporary live Price ID was used:

1. Restore the production Price ID in `/opt/stickerbaker/.env`.
2. Rebuild and restart `stickerbaker-app`.
3. Run release migrations if code changed.
4. Verify runtime plans:
   - Starter: `$4.99`, `499`, `usd`, `50`
   - Creator: `$9.99`, `999`, `usd`, `150`
5. Verify Stripe Price objects are active, live, one-time, and match amounts.
6. Verify `/pricing` displays the expected prices.

## SEO And Indexing Checks

Before asking search engines to index production pages:

```bash
curl -fsS https://ai-sticker-maker.com/robots.txt
curl -fsS https://ai-sticker-maker.com/sitemap.xml
```

Expected:

- `robots.txt` does not disallow `/`.
- `robots.txt` declares `Sitemap: https://ai-sticker-maker.com/sitemap.xml`.
- `sitemap.xml` returns `200` and includes public indexable pages only.
- Login, account, history, and admin pages are not in XML sitemap.

Submit `https://ai-sticker-maker.com/sitemap.xml` in Google Search Console after deployment.

## Google Search Console Launch Verification

Use after payment launch, pricing changes, sitemap changes, or SEO page changes.

1. Verify ownership for `ai-sticker-maker.com` in Google Search Console. Domain-property DNS verification is preferred. URL-prefix verification is acceptable as a fallback.
2. Submit the production sitemap:

```text
https://ai-sticker-maker.com/sitemap.xml
```

3. Confirm the submitted sitemap status is successful and the discovered URL count is plausible.
4. Manually inspect and request indexing for priority public pages:

```text
https://ai-sticker-maker.com/
https://ai-sticker-maker.com/pricing
https://ai-sticker-maker.com/face-to-sticker
https://ai-sticker-maker.com/custom-sticker-maker
https://ai-sticker-maker.com/sticker-maker-online
https://ai-sticker-maker.com/ai-avatar-sticker
https://ai-sticker-maker.com/kawaii-sticker-maker
https://ai-sticker-maker.com/transparent-sticker-maker
```

5. Let lower-priority utility pages, such as `/search`, be discovered through the sitemap unless they are strengthened with unique index-worthy content.
6. Re-check the Pages and Sitemaps reports after 24 to 72 hours. Indexing is controlled by Google and is not immediate even after a successful request.

## GA4 Launch Verification

Use after changing Google Analytics tags or creating a new GA4 property.

1. Confirm the production HTML includes the current Measurement ID and does not include an obsolete ID:

```bash
curl -fsS https://ai-sticker-maker.com/ | grep -E 'G-[A-Z0-9]+|googletagmanager'
```

2. Open the site in a normal or incognito browser window with ad blockers disabled:

```text
https://ai-sticker-maker.com/?ga_test=1
```

3. In GA4, open Realtime and confirm active users or page views appear within a few minutes.
4. If Realtime remains empty after five minutes, check browser privacy extensions, network blockers, and whether the deployed HTML still uses the expected Measurement ID.
5. Treat GA4 standard reports as delayed. Realtime is the immediate launch check; standard acquisition and engagement reports can take longer to populate.

Recommended follow-up events:

| Event | Purpose |
| --- | --- |
| `generate_start` | Track users who begin sticker generation |
| `generate_success` | Track successful generation outcomes |
| `begin_checkout` | Track users who open Stripe Checkout |
| `purchase` | Track completed purchases |
| `credit_added` | Track successful account crediting |

## Completeness Checklist

Use this checklist before marking a payment-flow change complete:

| Dimension | Required Check |
| --- | --- |
| Interface parameters | Checkout plan, user, success/cancel URLs, Stripe Price IDs, webhook payload/signature, refund identifiers, deployment commands |
| Request/response structures | Stripe Checkout Session, Stripe webhook event, Stripe refund response, payment attempts, payment events, webhook events |
| Exception scenarios | Missing config, invalid signature, stale signature, unpaid checkout, amount/currency/user/plan/session mismatch, duplicate event, partial refund, low-balance refund |
| Error codes | Internal failure reasons map to stored evidence and retry behavior |
| Business logic | Purchase creates attempt, webhook credits exactly once, refund deducts or creates review state, account/admin pages show the record |
| Boundary scenarios | Duplicate webhooks, repeated refunds, concurrent refund events, temporary price rollback, missing payment record |
| Spec/code consistency | OpenSpec requirements match `Sticker.Payments`, controllers, schemas, migrations, pages, and tests |
| Compatibility | Existing Stripe flow, Creem fallback, account/admin display, Docker Compose operation, and public pricing remain working |

If any check fails, record the missing item, cause, and one-step fix plan before rollout.
