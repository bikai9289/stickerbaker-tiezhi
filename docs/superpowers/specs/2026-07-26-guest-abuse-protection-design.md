# Guest Generation Abuse Protection Design

Date: 2026-07-26
Status: Approved for planning

## Summary

Keep three no-sign-up sticker generations while preventing a browser from choosing its own guest
identity, limiting guest model usage by network, recording every model-task reservation even when a
credit is later refunded, and requiring Cloudflare Turnstile from the second guest request or when
risk signals are present. Turnstile remains disabled when both production keys are absent so the
initial deployment does not interrupt the current funnel.

## Goals

- Preserve three guest credits and the current failed-generation refund behavior.
- Issue guest identities only on the server through a signed, HttpOnly cookie.
- Preserve the same guest identity across login, logout, session renewal, and application restarts.
- Limit guests on one network to six model tasks in a rolling 24-hour window.
- Require Turnstile for the second and third guest requests and for a risk-triggered first request.
- Count requested model tasks even if prediction creation or the upstream generation later fails.
- Prevent account confirmation from granting three new credits after guest credits were spent.
- Keep authenticated and paid users outside the guest IP quota.

## Non-Goals

- Perfectly identifying a person who changes browser, device, network, or IP address.
- Storing raw IP addresses or building a general-purpose device fingerprint.
- Applying the six-task guest IP quota to authenticated users.
- Replacing account, payment, generation provider, or credit-refund systems.
- Moving DNS or the application origin behind Cloudflare as part of this change.

## Confirmed Product Rules

- A new server-recognized guest receives exactly three credits.
- A guest credit is spent for each prompt/model task, including each prompt in a batch.
- A failed or canceled prediction may refund its guest credit under the existing rules.
- A request-ledger reservation is not removed when a credit is refunded.
- An IP hash may reserve at most six guest model tasks in the preceding 24 hours.
- Turnstile is required when the guest has already started one generation.
- Turnstile is also required on the first generation when the same IP hash has at least three model
  task requests or at least two distinct guest IDs in the previous 10 minutes.
- After guest credits are exhausted, generation is blocked until the visitor signs in and has
  account credits.
- Email confirmation grants only the remaining credits from the originating guest identity. The
  existing confirmation behavior already implements this rule and must remain compatible.

## Identity Architecture

Add a browser-pipeline plug responsible for a dedicated `_sticker_guest` cookie.

- The cookie value is a cryptographically random ID with a `gst_` prefix.
- Plug signs the cookie with the Phoenix endpoint secret, sets `http_only: true`, `same_site: Lax`,
  a one-year maximum age, and `secure: true` in production.
- Invalid, unsigned, empty, or malformed cookie values are ignored and replaced server-side.
- The guest cookie is independent from the authentication session cookie. Login and logout may
  renew or clear the auth session without deleting the guest cookie.
- Every browser request copies the verified guest ID into the signed LiveView session. For an
  authenticated user, `local_user_id` remains the account public ID while `guest_user_id` preserves
  the browser's guest identity.
- Registration captures `guest_user_id`, transfers the guest's predictions on login, and grants
  only the remaining guest credits at confirmation.

### Existing-browser migration

When `_sticker_guest` is absent, the plug may seed it from the existing signed session
`local_user_id` only when no account is authenticated and the value matches the current safe guest
ID format. It must never accept a raw ID supplied by JavaScript, query parameters, form parameters,
or request bodies.

Remove the client-generated `localStorage.userId` flow and the writable `POST /api/session`
endpoint. Retain temporary no-op handling for stale `assign-user-id` LiveView events so cached old
JavaScript cannot crash a newly deployed LiveView. The current asset fingerprinting will move active
browsers to the new client code naturally.

## Client IP and Privacy

The production domain currently resolves directly to the Tencent origin rather than a Cloudflare
proxy. The application therefore cannot rely on `CF-Connecting-IP` for this release.

- Parse and validate IP literals instead of accepting arbitrary header strings.
- For the existing single reverse-proxy topology, use the right-most valid
  `X-Forwarded-For` address; this is the address appended by the trusted origin proxy and avoids the
  current spoofable first-entry behavior.
- Fall back to `conn.remote_ip` when the forwarding header is absent or invalid.
- Derive `ip_hash = HMAC-SHA256(secret, canonical_ip)` and store only the lowercase hexadecimal
  digest.
- Use a dedicated `GUEST_IP_HASH_SECRET` when configured. During staged rollout, derive a stable
  key from `SECRET_KEY_BASE` if the dedicated value is absent. Never log either key or the raw IP.
- Document that the origin proxy must overwrite or append `X-Forwarded-For` and that direct access
  to the application container must remain unavailable.

## Request Ledger

Add `guest_generation_attempts` with these fields:

| Field | Type | Rules |
| --- | --- | --- |
| `id` | bigint | Primary key |
| `request_id` | UUID | Required and unique for idempotency |
| `guest_user_id` | string | Required, validated guest ID |
| `ip_hash` | string | Required, 64-character HMAC digest |
| `mode` | string | `text` or `portrait` |
| `task_count` | integer | Required, greater than zero, maximum five |
| `turnstile_required` | boolean | Required |
| `turnstile_verified` | boolean | Required |
| `risk_reason` | string | Nullable bounded diagnostic code |
| `inserted_at` | UTC timestamp | Required |

Indexes:

- Unique `request_id`.
- `(ip_hash, inserted_at)` for the rolling quota and risk window.
- `(guest_user_id, inserted_at)` for distinct-identity and support diagnostics.

The ledger does not require `prediction_id`: one batch request can create multiple predictions, and
the ledger records the attempt before prediction creation.

### Atomic reservation

Before spending guest credits, start a database transaction and acquire a PostgreSQL transaction
advisory lock derived from `ip_hash`. Sum `task_count` for rows newer than 24 hours. If the new total
would exceed six, roll back with `:guest_ip_limited`; otherwise insert one ledger row. A repeated
`request_id` returns `:attempt_duplicate` without incrementing the quota, spending credits, creating
predictions, or starting provider work again.

LiveView generates the request UUID and places it in the form before submission. It rotates the UUID
after a request is accepted or conclusively rejected. On `:attempt_duplicate`, the page reloads the
guest's recent predictions. If the original request stopped before prediction creation, the user may
retry with the newly rotated UUID.

Input parsing, upload validation, image safety review, and prompt limits happen before reservation.
Turnstile verification happens before reservation. Once a valid request reaches reservation, its
task count remains in the ledger even if credit spending, prediction creation, storage, moderation,
provider startup, timeout, cancelation, or completion later fails.

## Turnstile Integration

Configuration uses:

- `TURNSTILE_SITE_KEY`: public widget key.
- `TURNSTILE_SECRET_KEY`: server-only verification key.

Both absent means Turnstile is disabled and existing guest behavior continues. Both present means
it is enabled. A partial configuration is a deployment configuration error and must stop application
startup rather than silently advertise protection that is not active.

When enabled, the LiveView renders Cloudflare's explicit widget only when a challenge is required.
The widget submits a fresh token with the generation request. Text and portrait modes share the
same challenge state. A single token authorizes one user action; a batch still reserves and spends
one task for each parsed prompt.

The server calls Cloudflare Siteverify with:

- Required `secret` from server configuration.
- Required `response` from the submitted token.
- Optional `remoteip` using the validated current IP.
- A unique `idempotency_key` based on the request ID.

Success requires `success: true`. In production, returned hostname must match
`ai-sticker-maker.com` and the configured widget action must be `sticker_generation` when those
fields are present. Tokens expire after five minutes and are single-use. After every accepted,
expired, duplicate, or rejected token, the browser resets the widget and requests a new token.

Tests inject a verifier implementation and do not call Cloudflare. Local development may use
Cloudflare's official test keys or leave Turnstile disabled.

Reference:
[Cloudflare server-side validation](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/)
and
[explicit client-side rendering](https://developers.cloudflare.com/turnstile/get-started/client-side-rendering/).

## Generation Flow

```text
Validate prompt or portrait
        |
Determine task_count (1..5)
        |
Guest? -- no --> existing authenticated credit flow
  |
 yes
  |
Read verified guest ID + current IP hash
        |
Check guest credits and active/daily prediction limits
        |
Evaluate challenge policy
        |
Verify Turnstile when enabled and required
        |
Atomically reserve IP task_count
        |
Atomically spend guest credits and create prediction record(s)
        |
Start supervised provider task(s)
```

Credit spending and prediction creation remain in their current transaction so a database creation
failure refunds or rolls back guest credits. The separate attempt reservation intentionally remains.

## UI Behavior

- First low-risk guest request keeps the current one-click generation flow.
- Before the second and third request, show Turnstile directly above the generate action only when
  production keys are configured.
- Disable Generate while a required challenge has no valid token.
- Explain only the immediate state: `Complete the security check to continue.`
- On expired or duplicate token, reset in place and show `Security check expired. Please try again.`
- On IP limit, do not consume a guest credit. Show `This network has reached its free generation
  limit for the last 24 hours. Sign in to continue with account credits.` with a sign-in action.
- On exhausted guest credits, keep the existing account CTA and do not create a new guest identity.
- Do not display IP addresses, hashes, risk scores, provider details, or Cloudflare error codes.

## Error Contract

Internal outcomes use dedicated atoms and stable user messages:

| Outcome | Credit spent | Ledger reserved | User behavior |
| --- | --- | --- | --- |
| `:guest_identity_missing` | No | No | Refresh/retry; server reissues identity |
| `:guest_credits_exhausted` | No | No | Require sign-in |
| `:guest_ip_limited` | No | No | Require sign-in or wait 24 hours |
| `:turnstile_required` | No | No | Render/complete challenge |
| `:turnstile_invalid` | No | No | Reset challenge |
| `:turnstile_expired` | No | No | Reset challenge with expiry message |
| `:turnstile_unavailable` | No | No | Retry later when protection is enabled |
| `:attempt_duplicate` | No additional spend | No additional row | Reload recent results and rotate request ID |
| `:insufficient_credits` | No | No | Existing account-credit message |
| `:create_failed` | Refunded/rolled back | Yes | Existing refund message |

Invalid or empty parameters, oversized batches, unsafe images, upload failures, daily account
limits, and active-generation limits retain their existing behavior and occur before IP reservation
where possible.

## Compatibility and Security

- Existing signed-session guests retain their ID on the first request after deployment.
- Existing guest credit and prediction rows require no destructive migration.
- Authenticated generation bypasses guest IP and Turnstile policy but retains account credit,
  active-generation, and daily limits.
- Signup confirmation continues to use remaining guest credits rather than adding a second grant.
- Failed and canceled predictions continue to refund credits at most once.
- Cookie tampering produces a new server ID; it never grants access to another guest's history.
- Clearing all cookies or using a new browser can create a new ID, but the six-task IP ledger and
  risk challenge still apply.
- A network change can bypass the IP ledger; requiring accounts after three guest credits remains
  the durable conversion boundary.

## Cloudflare and Deployment

After application tests pass:

1. Create a Cloudflare Turnstile Managed widget for `ai-sticker-maker.com` using the already signed-in
   Cloudflare account.
2. Store the site key and secret only in production server environment configuration. Never commit
   them or print them in command output.
3. Configure `GUEST_IP_HASH_SECRET` with a stable random secret on the server.
4. Deploy the additive migration and application code with Turnstile still disabled until both keys
   are present in the restarted process.
5. Restart with both Turnstile keys and verify the first, second, risk-triggered, expired-token,
   exhausted-credit, and IP-limit paths.
6. Confirm the app receives the expected right-most `X-Forwarded-For` address without logging the
   raw value.

## Testing

### Identity and controller tests

- A first anonymous request receives a valid signed HttpOnly guest cookie.
- A valid cookie is stable across requests, login, logout, and session renewal.
- Tampered, empty, expired, and malformed cookies are replaced.
- Existing signed-session guest IDs migrate once.
- Raw client `userId`, query, and `/api/session` submissions cannot change identity.
- Authenticated `local_user_id` remains the account public ID while `guest_user_id` is preserved.

### Ledger tests

- Six task reservations in a rolling 24-hour window succeed and the seventh is rejected.
- Batch task counts consume multiple slots atomically.
- Concurrent reservations cannot exceed six.
- Duplicate request IDs do not double count.
- Failed, refunded, canceled, and timed-out generations retain their ledger entry.
- Entries exactly inside and outside the 10-minute and 24-hour boundaries behave correctly.
- Raw IP values never appear in stored rows.

### Turnstile tests

- Both missing keys disable the widget and verifier.
- Partial configuration fails startup validation.
- First low-risk request does not require a token.
- Second and third requests require one when enabled.
- Three tasks or two guest IDs in 10 minutes challenge a first request.
- Missing, invalid, expired, duplicate, wrong-hostname, wrong-action, and unavailable verifier
  responses map to the documented outcomes.
- A successful token is used once and the client resets after submission.

### Generation compatibility tests

- Guest text, portrait, and batch flows reserve the correct task count.
- Authenticated generation does not reserve guest IP quota.
- Guest credits still cap at three and refund at most once.
- Signup confirmation grants only remaining guest credits.
- Existing active/daily prediction limits, uploads, downloads, history ownership, and generation
  status updates remain intact.

## Acceptance Criteria

- Clients cannot select or overwrite a guest identity.
- Clearing only browser cache, logging out, or renewing the session does not grant new guest credits.
- A new browser on the same network cannot start more than the remaining six rolling network tasks.
- The first low-risk guest generation remains frictionless.
- Turnstile activates only when both production keys exist and protects required requests through
  server-side Siteverify.
- Every accepted guest model-task request is durably counted even when credits are refunded.
- Authenticated and paid users are not blocked by guest IP quota.
- No raw IP, Turnstile secret, or guest-cookie signing material is stored in application rows,
  analytics, logs, or source control.
- Migrations are additive and existing guest generation, signup, refund, download, and history
  behavior remains compatible.
