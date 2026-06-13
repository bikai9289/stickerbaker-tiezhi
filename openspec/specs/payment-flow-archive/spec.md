# Payment Flow Archive Specification

## Purpose

This capability defines the auditable production payment archive for Stripe credit purchases, refunds, price verification, deployment checks, and completeness review.

## Requirements

### Requirement: Production payment archive records verified checkout flow

The system SHALL maintain an auditable archive for the production Stripe credit purchase flow, including the active price IDs, expected amount and currency, checkout attempt state, payment event state, webhook processing state, and user credit delta.

#### Scenario: Live checkout is archived as credited

- **WHEN** a signed-in user completes a live Stripe Checkout payment for a credit plan
- **THEN** the archive evidence MUST show a `payment_attempts` row with provider `stripe`, the expected plan, credits, amount, currency, active Stripe price ID, Checkout Session ID, and status `credited`
- **AND** the archive evidence MUST show a `payment_events` row with provider `stripe`, matching Checkout Session ID, Stripe payment intent, Stripe event ID, credits, amount, currency, and refund status `none`
- **AND** the archive evidence MUST show a `payment_webhook_events` row for `checkout.session.completed` with status `processed`
- **AND** the user credit balance MUST increase by the purchased credits exactly once

### Requirement: Production payment archive records verified refund flow

The system SHALL maintain an auditable archive for the production Stripe refund flow, including refund event status, payment refund status, and user credit rollback behavior.

#### Scenario: Full refund is archived as refunded

- **WHEN** a full Stripe refund is issued for a credited live Stripe payment
- **THEN** the archive evidence MUST show a `payment_webhook_events` row for `charge.refunded` with status `processed`
- **AND** the matching `payment_events` row MUST have refund status `refunded`, a refund event ID, and `refunded_at`
- **AND** the user credit balance MUST decrease by the original purchased credits when the account balance can cover the deduction

#### Scenario: Refund settlement timing is documented

- **WHEN** the application has processed a successful full refund webhook
- **THEN** the archive MUST distinguish immediate application credit rollback from card or bank settlement timing
- **AND** the archive MUST document that external refund visibility can take several business days depending on the payment method and issuing bank

### Requirement: Price configuration is cross-checked before payment readiness

The system SHALL require price configuration checks before declaring payment readiness or after changing a Stripe Price ID.

#### Scenario: Starter price configuration matches code and Stripe

- **WHEN** Starter payment readiness is checked
- **THEN** the runtime plan MUST report price `$4.99`, amount `499`, currency `usd`, and credits `50`
- **AND** the configured Stripe Price ID MUST be live, active, one-time, currency `usd`, and unit amount `499`
- **AND** the public `/pricing` page MUST display `$4.99` for Starter

#### Scenario: Creator price configuration matches code and Stripe

- **WHEN** Creator payment readiness is checked
- **THEN** the runtime plan MUST report price `$9.99`, amount `999`, currency `usd`, and credits `150`
- **AND** the configured Stripe Price ID MUST be live, active, one-time, currency `usd`, and unit amount `999`

### Requirement: Completeness check is required for payment-flow archive changes

Any implementation or archive update for the payment flow MUST include the complete payment integrity check before completion.

#### Scenario: Completeness report covers required dimensions

- **WHEN** a payment-flow archive implementation is completed
- **THEN** the completion report MUST cover interface parameter completeness, request and response structure completeness, exception scenario completeness, error-code completeness, business-logic completeness, boundary scenario completeness, spec/code consistency, and compatibility completeness
- **AND** any failed dimension MUST include a missing-item list, root cause, and one-step fix plan before the work is considered complete

### Requirement: Deployment runbook preserves rollback path

The payment-flow archive SHALL document deployment and rollback actions for production payment changes.

#### Scenario: Production deployment is verifiable

- **WHEN** payment-related documentation or configuration is deployed
- **THEN** the runbook MUST include commands to rebuild and restart the Docker Compose app container, run release migrations, verify runtime plan values, verify `/pricing`, inspect logs, and confirm Stripe webhook endpoint configuration

#### Scenario: Price rollback is verifiable

- **WHEN** a temporary Stripe price is restored to the production price
- **THEN** the runbook MUST require restoring the production Stripe Price ID in `.env`, rebuilding and restarting the app container, verifying runtime plan amount and page display, and checking the Stripe Price object amount and currency

### Requirement: Launch verification is archived with payment readiness

The payment-flow archive SHALL include the completed production launch checks that prove users and search engines can reach the post-payment deployment.

#### Scenario: Search Console verification and sitemap submission are archived

- **WHEN** the production site is launched after payment verification
- **THEN** the archive evidence MUST show Google Search Console ownership verification for `ai-sticker-maker.com`
- **AND** the archive evidence MUST show successful submission of `https://ai-sticker-maker.com/sitemap.xml`
- **AND** the archive evidence MUST list priority public URLs submitted through URL inspection for indexing

#### Scenario: GA4 Realtime verification is archived

- **WHEN** the production analytics tag is changed or newly configured
- **THEN** the archive evidence MUST show the GA4 Measurement ID used in production
- **AND** the archive evidence MUST show the production page loads the expected tag
- **AND** the archive evidence MUST show GA4 Realtime receiving traffic from the production site
