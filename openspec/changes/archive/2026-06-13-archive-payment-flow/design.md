## Context

The project now has a deployed Stripe payment flow for credit purchases. A live Starter purchase was completed against `https://ai-sticker-maker.com`, credited 50 user credits, recorded the Stripe checkout attempt and payment event, then a live full refund was issued through Stripe and processed by the `charge.refunded` webhook, deducting those credits back from the account.

The implementation spans Stripe Dashboard configuration, Docker Compose production environment variables, Phoenix controllers, `Sticker.Payments`, Ecto payment tables, `/pricing`, `/account`, and `/admin/payments`. The operational knowledge currently exists across code, deployment state, and manual verification output. This change archives that flow into an OpenSpec capability and runbook-quality tasks so future price changes, payment incidents, and refunds can be checked consistently.

## Goals / Non-Goals

**Goals:**
- Define the production payment archive contract for Stripe credit purchases.
- Capture required verification evidence for checkout, webhook fulfillment, refund handling, and price configuration.
- Require the full project completeness check for payment changes: parameters, structures, errors, business closure, edge cases, code/spec consistency, and compatibility.
- Provide an implementation path for adding durable payment runbook documentation and evidence references.

**Non-Goals:**
- Add subscription billing, tax calculation, customer portal, or new payment providers.
- Change the current Starter and Creator production prices.
- Replace Stripe Checkout with in-app card collection.
- Remove the existing Creem fallback code.

## Decisions

1. Archive payment readiness as a dedicated capability named `payment-flow-archive`.
   - Rationale: Payment operations involve external provider state, application state, and database state. Keeping the contract separate from implementation details makes it easier to audit.
   - Alternative considered: Put this only in README. README is useful for operators but does not provide OpenSpec requirement/scenario structure or archive workflow.

2. Treat live purchase and live refund as required production readiness evidence.
   - Rationale: Unit tests and local smoke checks cannot prove Stripe live price IDs, webhook endpoint registration, card network behavior, or production database writes.
   - Alternative considered: Rely only on Stripe test mode. Test mode is valuable before launch but does not validate live-mode dashboard configuration.

3. Store evidence as operational records, not secrets.
   - Rationale: Evidence should include non-sensitive IDs and outcomes such as price IDs, event IDs, statuses, amount/currency, and credit deltas. It must not include secret keys, raw card data, passwords, or full environment dumps.
   - Alternative considered: Archive complete command output. This risks leaking secrets from `.env`, Docker Compose, logs, or screenshots.

4. Keep refunds aligned with the current product policy.
   - Rationale: Full refunds automatically remove purchased credits when the user has enough balance. Low-balance and partial refunds are review states. The archive should document that behavior rather than introduce new refund math.
   - Alternative considered: Auto-prorate partial refunds. That is outside the verified behavior and would need a separate payment policy change.

## Risks / Trade-offs

- Secret leakage through evidence capture -> Only store redacted command output and non-sensitive provider IDs.
- Drift between Stripe Dashboard and code plan amounts -> Verification must compare Stripe Price `unit_amount`, code `plan.amount`, and page display before marking payment readiness.
- Refund timing confusion -> Archive must distinguish application refund handling, which is immediate after webhook processing, from card/bank settlement, which can take several business days.
- Production state changes during verification -> Use one low-risk live purchase and immediate full refund for readiness checks, and record the affected user/payment IDs.
- Existing uncommitted payment implementation work -> Tasks must include a git status review and require separating archive/runbook changes from unrelated implementation churn.

## Migration Plan

1. Add the `payment-flow-archive` OpenSpec requirements.
2. Add or update documentation/runbook artifacts that describe live payment verification, refund verification, price rollback, deployment, and completeness checks.
3. Verify the existing production deployment still reports:
   - Starter plan: USD 4.99, amount 499, 50 credits.
   - Creator plan: USD 9.99, amount 999, 150 credits.
   - Stripe live webhook endpoint enabled for `checkout.session.completed` and `charge.refunded`.
4. Keep database migrations as already deployed; no schema migration is required for this archive change.
5. Rollback for documentation-only implementation is reverting the documentation/spec artifacts. If a future implementation task touches deployment state, rollback must restore the previous `.env`, rebuild the app container, and verify runtime plan values.

## Open Questions

- Where should the long-term operator runbook live: README, `docs/payment-flow-runbook.md`, or both?
- Should production verification evidence be committed as a sanitized markdown record, or kept outside the repo as an operations log?
