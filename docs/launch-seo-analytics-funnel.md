# Launch SEO and Analytics Funnel

This document records the public acquisition measurement and Search Console verification contract for `improve-seo-analytics-funnel`.

## GA4 Funnel Events

All events are browser-side GA4 events emitted with privacy-safe parameters only. Do not send prompt text, uploaded image content, image file names, email addresses, payment provider identifiers, raw user identifiers, IP addresses, cookies, CSRF tokens, or generated private sticker URLs.

| Event | Trigger | GA4 key event | Required params | Optional params |
| --- | --- | --- | --- | --- |
| `generator_view` | Home generator area mounts | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `text_generation_attempt` | Text-to-sticker form submit | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `face_upload_attempt` | Face upload entry point click | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `registration_cta_click` | Registration CTA click | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `registration_confirm_attempt` | Registration form submit | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context` |
| `registration_confirmed` | Email-confirmation return state | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `login_cta_click` | Login CTA click | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `pricing_cta_click` | Pricing CTA click | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `buy_credit_cta_click` | Buy-credit CTA click | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `plan` |
| `checkout_start` | Checkout form submit | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `plan` |
| `purchase_complete` | Checkout success return state | Yes | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context`, `auth_state` |
| `search_submit` | Sticker search submit | No | `page_path`, `source` | `utm_source`, `utm_medium`, `utm_campaign`, `referrer_host`, `event_context` |

## Internal Traffic Filtering

Configure GA4 internal traffic definitions only for narrow, known IP addresses or ranges. Do not guess broad ISP, city, country, or cloud-provider ranges.

| Source | IP or range | Purpose | Status |
| --- | --- | --- | --- |
| Operator/tester network | To be filled in GA4 | Exclude manual QA from decision reports | Pending authenticated GA4 setup |
| Tencent Cloud server egress | To be confirmed before adding | Exclude server-side checks only if they appear in GA4 | Pending verification |

Decision reports must either apply the internal traffic exclusion or explicitly state that internal traffic is not excluded.

## GSC Verification Checklist

Record the result after deployment for each URL below. Use Google Search Console sitemap status and URL Inspection where available.

| URL | Expected status | Expected canonical | GSC index status | Google-selected canonical | Next action |
| --- | --- | --- | --- | --- | --- |
| `https://ai-sticker-maker.com/` | 200 | `https://ai-sticker-maker.com/` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/sitemap.xml` | 200 | N/A | Pending GSC check | N/A | Pending |
| `https://ai-sticker-maker.com/search` | 200 | `https://ai-sticker-maker.com/search` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/face-to-sticker` | 200 | `https://ai-sticker-maker.com/face-to-sticker` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/custom-sticker-maker` | 200 | `https://ai-sticker-maker.com/custom-sticker-maker` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/sticker-maker-online` | 200 | `https://ai-sticker-maker.com/sticker-maker-online` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/ai-avatar-sticker` | 200 | `https://ai-sticker-maker.com/ai-avatar-sticker` | Pending GSC check | Pending GSC check | Pending |
| `https://ai-sticker-maker.com/kawaii-sticker-maker` | 200 | `https://ai-sticker-maker.com/kawaii-sticker-maker` | Pending GSC check | Pending GSC check | Pending |

## Current Baseline

- GSC screenshot dated June 2026 showed 72 impressions, 1 click, 1.4% CTR, average position 41.3, and visible queries for `ai sticker maker`, `ai sticker generator`, `ai sticker generator online free`, `ai stickers`, `free ai stickers`, `avatar stickers`, `face to sticker ai`, `sticker maker ai`, `ai sticker creator`, and `ai sticker`.
- GA4 screenshot showed 112 active users, 642 events, 111 new users, 0 key events, and organic search as a small traffic source.
- Existing repository baseline already includes `robots.txt`, `sitemap.xml`, page-specific metadata, and JSON-LD on the priority long-tail pages.
- Available local product signals now include browser events for generator view, text generation attempt, face upload attempt, registration CTA click, registration form submit, email-confirmation return, pricing CTA click, buy-credit CTA click, checkout form submit, checkout success return, and search submit.
- Purchase completion is measured from the existing `/account?checkout=success` return state. Provider-confirmed webhook fulfillment remains the source of account credit truth and is not changed by this measurement layer.
- Registration completion is measured from the existing email-confirmation flow by redirecting confirmed users to `/?registration=confirmed` after login.

## Completeness Notes

- GA4 key-event marking and internal traffic filters require authenticated GA4 property access.
- GSC sitemap submission and URL inspection require authenticated Search Console access.
- Repository verification can prove event names, safe payloads, metadata, sitemap membership, visible content, and structured-data parity, but cannot prove authenticated console state by itself.
