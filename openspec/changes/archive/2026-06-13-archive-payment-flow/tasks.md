## 1. Archive Structure

- [x] 1.1 Create a payment-flow runbook document for production operators.
- [x] 1.2 Add a sanitized live verification record for the completed Stripe purchase and refund.
- [x] 1.3 Ensure archived evidence excludes secrets, passwords, raw card data, and full environment dumps.

## 2. Checkout Evidence

- [x] 2.1 Document the verified live Starter checkout attempt fields: provider, plan, credits, amount, currency, price ID, session ID, and credited status.
- [x] 2.2 Document the verified live Stripe payment event fields: provider, payment intent, Stripe event ID, amount, currency, credits, and initial refund status.
- [x] 2.3 Document the verified `checkout.session.completed` webhook event and processed status.
- [x] 2.4 Document the observed user credit increase from the live purchase.

## 3. Refund Evidence

- [x] 3.1 Document the full refund API outcome, including refund ID, amount, currency, status, and payment intent.
- [x] 3.2 Document the verified `charge.refunded` webhook event and processed status.
- [x] 3.3 Document the payment event transition to `refunded`, including refund event ID and `refunded_at`.
- [x] 3.4 Document the observed user credit deduction after refund processing.
- [x] 3.5 Document customer-facing refund settlement timing separately from immediate application credit rollback.

## 4. Price And Deployment Runbook

- [x] 4.1 Document how to verify Starter runtime plan, Stripe Price object, and `/pricing` page all match USD 4.99 / amount 499 / 50 credits.
- [x] 4.2 Document how to verify Creator runtime plan and Stripe Price object match USD 9.99 / amount 999 / 150 credits.
- [x] 4.3 Document Docker Compose production deploy commands: rebuild app, restart app, run release migrations, inspect logs, and verify health.
- [x] 4.4 Document rollback steps for temporary price changes, including restoring `.env`, rebuilding the app container, and checking runtime/page/Stripe consistency.

## 5. Completeness Check

- [x] 5.1 Complete interface parameter integrity review for checkout, webhook, refund, price verification, and deployment commands.
- [x] 5.2 Complete request and response structure review for Stripe Checkout Session, webhook events, refund responses, and database evidence rows.
- [x] 5.3 Complete exception scenario review for missing config, invalid signatures, unpaid checkout, mismatched amount/currency/plan/user/session, duplicate events, partial refunds, and low-balance refunds.
- [x] 5.4 Complete error-code review mapping known payment failure reasons to handling behavior and operator-visible evidence.
- [x] 5.5 Complete business logic review confirming purchase, crediting, idempotency, refund, credit deduction, review states, and admin/account visibility form a closed loop.
- [x] 5.6 Complete boundary scenario review for duplicate webhooks, repeated refunds, temporary price rollback, stale signatures, and no matching payment records.
- [x] 5.7 Complete spec/code consistency review comparing OpenSpec requirements with `Sticker.Payments`, controllers, schemas, migrations, pages, and tests.
- [x] 5.8 Complete compatibility review confirming the archive does not break existing Stripe live flow, Creem fallback code, account display, admin display, or deployed Docker Compose operation.

## 6. Verification

- [x] 6.1 Run OpenSpec status and confirm the change remains apply-ready.
- [x] 6.2 Verify the runbook and evidence documents exist at their intended paths.
- [x] 6.3 Run available formatting or markdown checks for touched documentation.
- [x] 6.4 Report any completeness failures with missing list, cause, and one-step fix plan before marking the implementation complete.

## 7. Launch Verification

- [x] 7.1 Document Google Search Console domain ownership verification for `ai-sticker-maker.com`.
- [x] 7.2 Document successful sitemap submission for `https://ai-sticker-maker.com/sitemap.xml`.
- [x] 7.3 Document manual indexing requests for homepage, pricing, and priority SEO landing pages.
- [x] 7.4 Document GA4 Measurement ID `G-5RKZJSQZ59` deployment and Realtime verification.
- [x] 7.5 Document follow-up monitoring for Search Console indexing, `/search` quality, and GA4 business-funnel events.
