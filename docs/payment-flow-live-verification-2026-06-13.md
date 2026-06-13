# Payment Flow Live Verification - 2026-06-13

This record is sanitized. It intentionally excludes secret keys, webhook secrets, card data, server passwords, raw `.env` output, and full command dumps.

## Scope

- Site: `https://ai-sticker-maker.com`
- Provider: Stripe live mode
- User: `bikai9289@gmail.com`
- Plan tested: Starter
- Temporary test amount: USD `1.00`
- Production amount restored after test: Starter USD `4.99`
- Verification date: 2026-06-13

## Live Checkout Evidence

### Checkout Attempt

| Field | Value |
| --- | --- |
| `id` | `1` |
| `user_id` | `1` |
| `provider` | `stripe` |
| `plan` | `starter` |
| `credits` | `50` |
| `amount` | `100` |
| `currency` | `usd` |
| `status` | `credited` |
| `stripe_price_id` | `price_1ThqJXAG05S2YrchM3LTNSlv` |
| `stripe_session_id` | `cs_live_a1oQ5hiWDqWG4jzX9eqSQpb8Lqfqpl4hhs5CWocPmFRJpfvA6j9go60CdR` |
| `provider_order_id` | empty at attempt record |
| `inserted_at` | `2026-06-13 12:12:34` |
| `updated_at` | `2026-06-13 12:13:04` |

### Payment Event

| Field | Value |
| --- | --- |
| `id` | `12` |
| `user_id` | `1` |
| `provider` | `stripe` |
| `plan` | `starter` |
| `credits` | `50` |
| `amount` | `100` |
| `currency` | `usd` |
| `stripe_price_id` | `price_1ThqJXAG05S2YrchM3LTNSlv` |
| `stripe_session_id` | `cs_live_a1oQ5hiWDqWG4jzX9eqSQpb8Lqfqpl4hhs5CWocPmFRJpfvA6j9go60CdR` |
| `provider_order_id` | `pi_3ThqQrAG05S2Yrch14cSYwsQ` |
| `stripe_event_id` | `evt_1ThqQtAG05S2Yrch12eJQyB9` |
| Initial `refund_status` | `none` before refund |
| Final `refund_status` | `refunded` after refund |
| `inserted_at` | `2026-06-13 12:13:04` |

### Checkout Webhook Event

| Field | Value |
| --- | --- |
| `id` | `1` |
| `provider` | `stripe` |
| `stripe_event_id` | `evt_1ThqQtAG05S2Yrch12eJQyB9` |
| `event_type` | `checkout.session.completed` |
| `livemode` | `true` |
| `status` | `processed` |
| `error_reason` | empty |
| `inserted_at` | `2026-06-13 12:13:04` |
| `updated_at` | `2026-06-13 12:13:04` |

### Credit Increase

The checkout credited 50 Starter credits exactly once. The later observed account balance before refund rollback was `141` credits.

## Live Refund Evidence

### Stripe Refund

| Field | Value |
| --- | --- |
| Refund ID | `re_3ThqQrAG05S2Yrch1aTqFkY2` |
| Amount | `100` |
| Currency | `usd` |
| Status | `succeeded` |
| PaymentIntent | `pi_3ThqQrAG05S2Yrch14cSYwsQ` |

### Refund Webhook Event

| Field | Value |
| --- | --- |
| `id` | `2` |
| `provider` | `stripe` |
| `stripe_event_id` | `evt_3ThqQrAG05S2Yrch19rAzWhu` |
| `event_type` | `charge.refunded` |
| `livemode` | `true` |
| `status` | `processed` |
| `error_reason` | empty |
| `inserted_at` | `2026-06-13 12:14:48` |
| `updated_at` | `2026-06-13 12:14:48` |

### Payment Event After Refund

| Field | Value |
| --- | --- |
| `id` | `12` |
| `refund_status` | `refunded` |
| `refund_event_id` | `evt_3ThqQrAG05S2Yrch19rAzWhu` |
| `refunded_at` | `2026-06-13 12:14:48` |
| `updated_at` | `2026-06-13 12:14:48` |

### Credit Deduction

The account had enough balance to cover the full refund credit rollback. Credits were deducted by `50`.

Observed final account row:

| Field | Value |
| --- | --- |
| `id` | `1` |
| `email` | `bikai9289@gmail.com` |
| `credits` | `91` |

## Price Restoration Evidence

After the temporary USD `1.00` live test, production pricing was restored.

### Runtime Plans

```text
starter|$4.99|499|usd|50|price_1ThifrAG05S2YrchU71gG75f
creator|$9.99|999|usd|150|price_1ThigAAG05S2YrchETy2RNC2
```

### Stripe Live Price Objects

```text
price|price_1ThifrAG05S2YrchU71gG75f|active=True|livemode=True|amount=499|currency=usd|type=one_time
price|price_1ThigAAG05S2YrchETy2RNC2|active=True|livemode=True|amount=999|currency=usd|type=one_time
```

### Public Pricing Page

```text
1 $4.99
1 $9.99
1 Buy 150 Credits
1 Buy 50 Credits
```

## Stripe Balance Observation

After the full refund, Stripe showed:

```text
balance_available|usd|0
balance_available|hkd|0
balance_pending|usd|-34
balance_pending|hkd|0
```

This is an external settlement and fee state, not an application crediting failure. The app processed the refund webhook and rolled back credits immediately. Customer bank or card settlement can take several business days depending on the payment method and issuer.

## SEO And Indexing Verification

Live checks on 2026-06-13:

- `https://ai-sticker-maker.com/` returned HTTP `200`.
- `https://ai-sticker-maker.com/pricing` returned HTTP `200`.
- `https://ai-sticker-maker.com/sitemap.xml` returned HTTP `200` with `application/xml`.
- `https://ai-sticker-maker.com/robots.txt` returned HTTP `200`.
- `robots.txt` declares `Sitemap: https://ai-sticker-maker.com/sitemap.xml`.
- Public pages had canonical/meta description signals and no observed `noindex`.
- Search results for `site:ai-sticker-maker.com` showed the site had already been discovered.

The XML sitemap was later strengthened to include `/sitemap`, `lastmod`, and `priority` fields while keeping private pages out.

### Google Search Console Evidence

Google Search Console ownership verification completed for the domain property `ai-sticker-maker.com` on 2026-06-13.

Verification methods used:

- DNS TXT record: `google-site-verification=S3gOkTI8T5JG5sKQ68CgBLnunzV-q0OrnvN39nkvnFY`
- HTML meta tag in the production root layout with the same verification token

The DNS TXT record was observed through public DNS resolution alongside the existing Zoho mail records. Google Search Console then reported that ownership was verified.

The production sitemap was submitted in Search Console:

```text
https://ai-sticker-maker.com/sitemap.xml
```

Search Console reported the sitemap submission as successful and discovered 16 URLs.

Priority URLs were manually inspected and requested for indexing:

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

The `/search` page remains in the sitemap for discovery. It should be monitored because search-style pages can become thin or repetitive if they do not expose enough unique content.

## GA4 Verification

GA4 production Measurement ID:

```text
G-5RKZJSQZ59
```

The production homepage was verified to include the new Measurement ID and not the previous ID.

Observed live checks:

- `https://ai-sticker-maker.com/` returned HTTP `200`.
- The production HTML loaded `https://www.googletagmanager.com/gtag/js?id=G-5RKZJSQZ59`.
- A browser-level check observed a GA4 `page_view` request to `https://www.google-analytics.com/g/collect` with `tid=G-5RKZJSQZ59`.
- GA4 Realtime showed active users after opening `https://ai-sticker-maker.com/?ga_test=1`.

GA4 is therefore connected for page-view analytics. Business-funnel events are not yet fully instrumented and should be handled as a follow-up analytics change.

## Completeness Review

| Dimension | Status | Notes |
| --- | --- | --- |
| Interface parameters | Pass | Checkout plan/user/success/cancel, Stripe price IDs, webhook signature, refund IDs, deployment checks, GSC sitemap URL, priority indexing URLs, and GA4 Measurement ID are documented. |
| Request/response structures | Pass | Checkout Session, webhook event, refund response, database row evidence, sitemap response, DNS TXT verification, and GA4 page-view request evidence are documented. |
| Exception scenarios | Pass | Existing tests cover missing config, invalid signatures, unpaid checkout, mismatches, duplicates, partial refunds, and low-balance refunds. Operational checks cover delayed indexing, thin `/search` content, GA4 report delay, and browser blocker scenarios. |
| Error codes | Pass with note | Internal reasons are explicit and stored in webhook failure evidence; user-facing checkout error remains intentionally generic. |
| Business logic | Pass | Purchase, crediting, idempotency, refund, rollback/review state, account/admin visibility, sitemap submission, URL inspection, and GA4 Realtime validation form a launch verification loop. |
| Boundary scenarios | Pass | Tests cover duplicate checkout, stale signature, concurrent refund, repeated refund, partial-to-full refund, and missing payment record behavior. Operations notes cover delayed Google indexing and delayed GA4 standard reporting. |
| Spec/code consistency | Pass | OpenSpec requirements match `Sticker.Payments`, controllers, schemas, migrations, pages, tests, sitemap output, Search Console submission, and GA4 tag reviewed during this archive. |
| Compatibility | Pass | Stripe live flow remains restored to production prices; Creem fallback remains present; account/admin display remains compatible; Search Console and GA4 additions do not alter payment behavior. |

No completeness failures are open for the archive documentation. Search Console submission and GA4 Realtime verification have been completed. The remaining external operational action is to monitor Search Console indexing and GA4 acquisition reports over the next several days.
