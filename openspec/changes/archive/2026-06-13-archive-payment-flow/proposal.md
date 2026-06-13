## Why

Stripe credit purchases have now been implemented, deployed, and verified with a live purchase and full refund. The project needs an auditable payment-flow archive so future deployments, refunds, price changes, and incident checks can be repeated from a documented contract instead of relying on chat history or ad hoc operator memory.

## What Changes

- Add a payment-flow archive capability that records the verified production Stripe checkout and refund flow.
- Define the operational evidence that must be captured for payment readiness: Stripe prices, webhook endpoint, database records, user credit changes, and refund status.
- Archive the completed launch checks for Google Search Console ownership, sitemap submission, priority URL indexing requests, and GA4 Realtime analytics verification.
- Define a reusable completeness check covering interface parameters, request/response structures, exception paths, error codes, business closure, boundary cases, spec/code consistency, and backward compatibility.
- Document the expected production rollout and rollback checkpoints for future price, webhook, and payment-flow changes.
- No breaking API changes are intended; this change is documentation/specification for operational readiness and future implementation follow-through.

## Capabilities

### New Capabilities
- `payment-flow-archive`: Captures the production payment verification contract, evidence requirements, refund behavior, and completeness checks for Stripe credit purchases.

### Modified Capabilities

## Impact

- Affected systems: Stripe Checkout, Stripe webhooks, Phoenix payment controllers, `Sticker.Payments`, payment attempt/event/webhook tables, `/pricing`, `/account`, `/admin/payments`, and Docker Compose production deployment.
- Affected operations: live purchase verification, live refund verification, Starter/Creator price ID changes, webhook endpoint checks, migration checks, payment incident triage, Search Console launch checks, and GA4 launch checks.
- Affected documentation: OpenSpec payment-flow archive artifacts and any follow-up README/admin runbook updates created during implementation.
