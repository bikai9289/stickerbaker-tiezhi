# Guest Generation Abuse Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve three friction-light guest generations while making guest identity server-owned, enforcing a durable six-task rolling network quota, and challenging the second/third or risky first guest request with Cloudflare Turnstile.

**Architecture:** A browser-pipeline plug owns a dedicated signed HttpOnly guest cookie and copies the verified identity plus privacy-safe request context into the LiveView session. A PostgreSQL request ledger, protected by an advisory transaction lock, atomically reserves guest model-task capacity before the existing credit/prediction transaction. A small generation gate evaluates risk, verifies Turnstile through an injectable verifier, and returns stable internal outcomes to `HomeLive`; authenticated users bypass this guest-only path.

**Tech Stack:** Elixir/Phoenix LiveView, Plug signed cookies, Ecto/PostgreSQL, Finch, Cloudflare Turnstile explicit rendering, vanilla JavaScript hooks, HEEx/CSS, ExUnit/LiveViewTest, Docker test database, GitHub Actions, production Chrome verification.

---

## File Map

- Create `lib/sticker_web/guest_identity.ex`: issue/verify/migrate the server-owned guest cookie and populate the session.
- Modify `lib/sticker_web/router.ex`: run the identity plug in the browser pipeline and remove the writable session API.
- Modify `lib/sticker_web/controllers/session_controller.ex`: retain only pending-prompt behavior.
- Modify `lib/sticker_web/controllers/user_session_controller.ex`: transfer predictions from the preserved guest ID during login.
- Modify `lib/sticker_web/controllers/user_registration_controller.ex`: capture `guest_user_id`, with signed-session fallback during rollout.
- Modify `assets/js/app.js`: remove client guest-ID creation and add explicit Turnstile rendering/reset behavior.
- Modify `lib/sticker_web/live/home_live.ex`: ignore stale identity events and enforce the guest generation gate for text and portrait requests.
- Modify `lib/sticker_web/live/home_live.html.heex`: remove identity data attributes and render challenge state near Generate.
- Modify `lib/sticker_web/live/history_live.ex`: make stale `assign-user-id` events no-ops.
- Modify `lib/sticker_web/live/history_live.html.heex`: remove the identity hook and data attribute.
- Modify `lib/sticker_web/live/admin_live.ex`: make stale `assign-user-id` events no-ops.
- Modify `lib/sticker_web/live/admin_live.html.heex`: remove the identity hook and data attribute.
- Modify `lib/sticker_web/abuse_protection.ex`: canonicalize the trusted proxy's right-most forwarded IP.
- Create `priv/repo/migrations/20260726010000_create_guest_generation_attempts.exs`: additive ledger table, constraints, and indexes.
- Create `lib/sticker/guest_abuse/attempt.ex`: ledger schema and constrained changeset.
- Create `lib/sticker/guest_abuse.ex`: HMAC hashing, risk queries, atomic quota reservation, and idempotency.
- Create `lib/sticker/turnstile.ex`: configuration access and server-side Siteverify client.
- Create `lib/sticker/turnstile/verifier.ex`: verifier behaviour for deterministic tests.
- Create `lib/sticker/guest_generation_gate.ex`: guest-only challenge and reservation orchestration.
- Modify `config/config.exs`: default disabled Turnstile and verifier configuration.
- Modify `config/runtime.exs`: validate all-or-none production Turnstile keys and configure the IP HMAC secret.
- Modify `config/test.exs`: deterministic disabled defaults and test verifier injection.
- Modify `assets/css/app.css`: compact challenge, disabled, expiry, and network-limit states.
- Create `test/sticker_web/guest_identity_test.exs`: cookie signing, tamper, migration, login/logout, and session behavior.
- Create `test/sticker_web/abuse_protection_test.exs`: valid/invalid forwarding-header coverage.
- Create `test/sticker/guest_abuse_test.exs`: quota, concurrency, boundary, privacy, and idempotency coverage.
- Create `test/sticker/turnstile_test.exs`: Siteverify request/response and configuration coverage.
- Create `test/sticker/guest_generation_gate_test.exs`: complete policy matrix and authenticated bypass.
- Modify `test/emoji_web/live/home_live_test.exs`: text, batch, portrait, challenge, and error UI coverage.
- Modify `test/emoji_web/live/history_live_test.exs`: stale identity event compatibility.
- Modify `test/emoji_web/controllers/page_controller_test.exs`: signup remaining-credit and login/logout guest identity compatibility.
- Create `assets/js/turnstile_hook_test.mjs`: widget render/reset/token lifecycle tests without a browser network call.

## Public Contracts

Use these stable internal types throughout the implementation so the policy is not reinterpreted in each LiveView branch:

```elixir
@type guest_mode :: :text | :portrait

@type gate_error ::
        :guest_identity_missing
        | :guest_credits_exhausted
        | :guest_ip_limited
        | :turnstile_required
        | :turnstile_invalid
        | :turnstile_expired
        | :turnstile_unavailable
        | :attempt_duplicate

@type authorization :: %{
        request_id: Ecto.UUID.t(),
        task_count: 1..5,
        challenge_required?: boolean(),
        challenge_reason: nil | :repeat_guest | :ip_velocity | :identity_velocity
      }
```

The generation form carries only these new client inputs:

```text
request_id       UUID generated by the server and rotated after every terminal submission
turnstile_token  optional opaque token; required only when the server says a challenge is required
```

Clients must never submit or override `guest_user_id`, `ip_hash`, `task_count`, `risk_reason`, `turnstile_required`, or `turnstile_verified`.

## Task 1: Make Guest Identity Server-Owned

**Files:**
- Create: `lib/sticker_web/guest_identity.ex`
- Modify: `lib/sticker_web/router.ex`
- Test: `test/sticker_web/guest_identity_test.exs`

- [ ] **Step 1: Write failing identity plug tests**

Cover all identity boundaries before adding the plug:

```elixir
test "first browser request receives a signed HttpOnly guest cookie", %{conn: conn} do
  conn = get(conn, ~p"/")
  assert [cookie] = get_resp_header(conn, "set-cookie")
  assert cookie =~ "_sticker_guest="
  assert cookie =~ "HttpOnly"
  assert cookie =~ "SameSite=Lax"
  refute cookie =~ "guest_user_id="
end

test "verified guest cookie remains stable across requests"
test "tampered, empty, expired, and malformed cookie values are replaced"
test "legacy signed-session guest identity seeds the new cookie once"
test "authenticated account public_id remains local_user_id while guest_user_id is preserved"
test "query and request-body IDs cannot select guest identity"
```

Use `recycle/1`, the response cookie, and `Plug.Test.init_test_session/2` to prove the second request receives the same `guest_user_id`. Assert the generated value matches `~r/^gst_[A-Za-z0-9_-]{32,}$/` and never use a client-provided value.

- [ ] **Step 2: Run the focused tests and verify failure**

Run in the existing Docker test environment:

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null && mix test test/sticker_web/guest_identity_test.exs"
```

Expected: compilation or assertion failure because `StickerWeb.GuestIdentity` and the cookie do not exist.

- [ ] **Step 3: Implement the identity plug**

Create a plug with one public `call/2` entry point and private validators:

```elixir
defmodule StickerWeb.GuestIdentity do
  import Plug.Conn

  @cookie "_sticker_guest"
  @salt "guest identity v1"
  @max_age 365 * 24 * 60 * 60
  @format ~r/^gst_[A-Za-z0-9_-]{32,}$/

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])
    guest_id = verified_cookie(conn) || legacy_session_guest(conn) || new_guest_id()

    conn
    |> maybe_put_cookie(guest_id)
    |> put_session(:guest_user_id, guest_id)
    |> put_session(:local_user_id, generation_identity(conn, guest_id))
  end
end
```

Implementation requirements:

- Generate 32 random bytes with `:crypto.strong_rand_bytes/1`, URL-safe Base64 without padding, prefixed `gst_`.
- Set `sign: true`, `signing_salt: @salt`, `http_only: true`, `same_site: "Lax"`, `max_age: @max_age`, `secure: Application.get_env(:sticker, :env) == :prod`.
- Accept a legacy `local_user_id` only when there is no authenticated user and it matches the existing guest-safe identifier rules. Never migrate an account `public_id`.
- If `conn.assigns.current_user` exists, keep `local_user_id` equal to its `public_id`; always preserve `guest_user_id` separately.
- Only set a response cookie when it was missing or invalid to avoid header churn.

Add `plug StickerWeb.GuestIdentity` immediately after `plug :fetch_current_user` in the browser pipeline so authentication state is available and the populated session reaches controllers and LiveViews.

- [ ] **Step 4: Run identity tests and full controller smoke tests**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker_web/guest_identity_test.exs test/emoji_web/controllers/page_controller_test.exs"
```

Expected: identity tests pass; existing controller tests may still expose assumptions about client-assigned IDs, which Task 2 updates deliberately.

- [ ] **Step 5: Commit the server identity foundation**

```powershell
git add lib/sticker_web/guest_identity.ex lib/sticker_web/router.ex test/sticker_web/guest_identity_test.exs
git commit -m "Secure guest identity with signed cookie"
```

## Task 2: Remove Every Client-Controlled Identity Path

**Files:**
- Modify: `assets/js/app.js`
- Modify: `lib/sticker_web/router.ex`
- Modify: `lib/sticker_web/controllers/session_controller.ex`
- Modify: `lib/sticker_web/live/home_live.ex`
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `lib/sticker_web/live/history_live.ex`
- Modify: `lib/sticker_web/live/history_live.html.heex`
- Modify: `lib/sticker_web/live/admin_live.ex`
- Modify: `lib/sticker_web/live/admin_live.html.heex`
- Modify: `test/emoji_web/live/home_live_test.exs`
- Modify: `test/emoji_web/live/history_live_test.exs`
- Modify: `test/emoji_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write failing tamper and stale-client tests**

Add tests proving:

```elixir
test "POST /api/session cannot set local_user_id", %{conn: conn} do
  conn = post(conn, "/api/session", %{local_user_id: "attacker-selected-id"})
  assert response(conn, 404)
end

test "stale assign-user-id event cannot change home identity" do
  {:ok, view, _html} = live(conn, ~p"/")
  before_id = :sys.get_state(view.pid).socket.assigns.local_user_id
  render_hook(view, "assign-user-id", %{"userId" => "attacker-selected-id"})
  assert :sys.get_state(view.pid).socket.assigns.local_user_id == before_id
end
```

Mirror the no-op assertion for `HistoryLive` and the pure `AdminLive.handle_event/3` test. Update homepage guest tests to obtain the server-issued identity from the LiveView session rather than pushing an assignment hook.

- [ ] **Step 2: Run the focused tests and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/emoji_web/live/home_live_test.exs test/emoji_web/live/history_live_test.exs test/emoji_web/controllers/page_controller_test.exs"
```

Expected: `/api/session` still accepts the write and stale hook events still replace identity.

- [ ] **Step 3: Delete the writable route and client ID creation**

- Remove `post "/session", SessionController, :set` and delete `SessionController.set/2`; retain `pending_prompt/2` unchanged.
- Remove `genId`, `localStorage.userId`, `Hooks.AssignUserId`, its `fetch('/api/session...')`, and calls from `LaunchAnalytics`.
- Remove `phx-hook="AssignUserId"` and `data-session-user-id` from home, history, and admin templates.
- Keep a temporary catch-all handler in each affected LiveView:

```elixir
def handle_event("assign-user-id", _params, socket), do: {:noreply, socket}
```

Do not subscribe, query predictions, create guest credits, or mutate any assign in that handler.

- [ ] **Step 4: Run the tests and inspect the built asset for forbidden strings**

```powershell
rg -n "localStorage\.userId|/api/session|pushEvent\(\"assign-user-id\"" assets lib
```

Expected: no active client or route matches; only compatibility event names and tests may remain.

Run the focused tests from Step 2. Expected: all pass.

- [ ] **Step 5: Commit identity hardening**

```powershell
git add assets/js/app.js lib/sticker_web/router.ex lib/sticker_web/controllers/session_controller.ex lib/sticker_web/live/home_live.ex lib/sticker_web/live/home_live.html.heex lib/sticker_web/live/history_live.ex lib/sticker_web/live/history_live.html.heex lib/sticker_web/live/admin_live.ex lib/sticker_web/live/admin_live.html.heex test/emoji_web/live/home_live_test.exs test/emoji_web/live/history_live_test.exs test/emoji_web/controllers/page_controller_test.exs
git commit -m "Remove client controlled guest identity"
```

## Task 3: Add the Durable Guest Attempt Ledger

**Files:**
- Create: `priv/repo/migrations/20260726010000_create_guest_generation_attempts.exs`
- Create: `lib/sticker/guest_abuse/attempt.ex`
- Create: `lib/sticker/guest_abuse.ex`
- Create: `test/sticker/guest_abuse_test.exs`

- [ ] **Step 1: Write failing schema, quota, and idempotency tests**

Test the complete data contract:

```elixir
test "reserves six rolling tasks and rejects the seventh" do
  for index <- 1..6 do
    assert {:ok, _attempt} = reserve(request_id: uuid(index), task_count: 1)
  end

  assert {:error, :guest_ip_limited} = reserve(request_id: uuid(7), task_count: 1)
  assert Repo.aggregate(Attempt, :count) == 6
end

test "batch reservation consumes task_count atomically"
test "duplicate request_id returns attempt_duplicate without another row"
test "concurrent reservations cannot exceed six tasks"
test "rows just inside and outside 24 hours are counted correctly"
test "risk stats count tasks and distinct identities in ten minutes"
test "invalid mode, zero, negative, and greater-than-five task_count are rejected"
test "raw IP is not a schema field and never appears in a stored row"
```

For concurrency, use `Ecto.Adapters.SQL.Sandbox.allow/3`, start at least eight tasks against one `ip_hash`, release them together, and assert the successful `task_count` sum is exactly six.

- [ ] **Step 2: Run the ledger test and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker/guest_abuse_test.exs"
```

Expected: missing migration/module failures.

- [ ] **Step 3: Create the additive migration and constrained schema**

Migration shape:

```elixir
create table(:guest_generation_attempts) do
  add :request_id, :uuid, null: false
  add :guest_user_id, :string, null: false
  add :ip_hash, :string, size: 64, null: false
  add :mode, :string, null: false
  add :task_count, :integer, null: false
  add :turnstile_required, :boolean, null: false, default: false
  add :turnstile_verified, :boolean, null: false, default: false
  add :risk_reason, :string
  timestamps(updated_at: false, type: :utc_datetime_usec)
end

create unique_index(:guest_generation_attempts, [:request_id])
create index(:guest_generation_attempts, [:ip_hash, :inserted_at])
create index(:guest_generation_attempts, [:guest_user_id, :inserted_at])

create constraint(:guest_generation_attempts, :guest_attempt_task_count,
  check: "task_count BETWEEN 1 AND 5")
create constraint(:guest_generation_attempts, :guest_attempt_mode,
  check: "mode IN ('text', 'portrait')")
create constraint(:guest_generation_attempts, :guest_attempt_ip_hash,
  check: "char_length(ip_hash) = 64")
```

The changeset must validate the guest format, UUID, hash format, mode inclusion, task count range, boolean fields, and bounded `risk_reason`, and map every database constraint back to a changeset error.

- [ ] **Step 4: Implement hashing, risk stats, and atomic reservation**

Expose a narrow context:

```elixir
def ip_hash(canonical_ip) when is_binary(canonical_ip)
def risk_snapshot(ip_hash, now \\ DateTime.utc_now())
def reserve_attempt(attrs, now \\ DateTime.utc_now())
```

Requirements:

- `ip_hash/1` uses `:crypto.mac(:hmac, :sha256, key, canonical_ip) |> Base.encode16(case: :lower)`.
- Read `:guest_ip_hash_secret` from application config; derive a stable fallback using `SECRET_KEY_BASE` only when the dedicated key is absent.
- `risk_snapshot/2` returns `%{task_count: integer, distinct_guest_count: integer}` for the prior ten minutes.
- `reserve_attempt/2` calls `Repo.transaction/1`, obtains `pg_advisory_xact_lock` from a deterministic signed 64-bit prefix of the hash, sums task counts newer than 24 hours, and inserts only if `used + requested <= 6`.
- Query the unique `request_id` first and map the unique constraint race to `{:error, :attempt_duplicate}`.
- Never delete or decrement rows on generation/refund/cancel failure.

- [ ] **Step 5: Run migration and ledger tests**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix ecto.migrate && mix test test/sticker/guest_abuse_test.exs"
```

Expected: all ledger tests pass, including concurrency and exact time-boundary cases.

- [ ] **Step 6: Commit the ledger**

```powershell
git add priv/repo/migrations/20260726010000_create_guest_generation_attempts.exs lib/sticker/guest_abuse/attempt.ex lib/sticker/guest_abuse.ex test/sticker/guest_abuse_test.exs
git commit -m "Add durable guest generation quota ledger"
```

## Task 4: Canonicalize and Protect Client Network Identity

**Files:**
- Modify: `lib/sticker_web/abuse_protection.ex`
- Create: `test/sticker_web/abuse_protection_test.exs`

- [ ] **Step 1: Write failing IP parsing tests**

Cover IPv4 and IPv6 plus hostile headers:

```elixir
test "uses right-most valid X-Forwarded-For entry from trusted nginx"
test "ignores spoofed left-most entries"
test "falls back to remote_ip for empty, malformed, hostname, or control-character values"
test "canonicalizes valid IPv6 without preserving arbitrary input text"
test "registration rate limiting still receives the canonical address"
```

An example assertion must prove `X-Forwarded-For: 203.0.113.9, 198.51.100.7` resolves to `198.51.100.7`, not the first value.

- [ ] **Step 2: Run the focused test and verify the current first-entry behavior fails**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker_web/abuse_protection_test.exs"
```

- [ ] **Step 3: Replace ad hoc string splitting with parsed IP literals**

Parse candidates with `:inet.parse_address(String.to_charlist(candidate))`, select the last valid non-empty forwarded entry, and canonicalize through `:inet.ntoa/1`. Fall back to canonicalized `conn.remote_ip`. Do not trust `CF-Connecting-IP` because production DNS currently reaches the Tencent origin directly.

- [ ] **Step 4: Run tests and commit**

```powershell
git add lib/sticker_web/abuse_protection.ex test/sticker_web/abuse_protection_test.exs
git commit -m "Harden forwarded client IP parsing"
```

## Task 5: Add Config-Safe Turnstile Verification

**Files:**
- Create: `lib/sticker/turnstile/verifier.ex`
- Create: `lib/sticker/turnstile.ex`
- Modify: `config/config.exs`
- Modify: `config/runtime.exs`
- Modify: `config/test.exs`
- Create: `test/sticker/turnstile_test.exs`

- [ ] **Step 1: Write failing configuration and verifier tests**

Cover the complete response contract:

```elixir
test "both absent keys disable Turnstile"
test "both present keys enable Turnstile and expose only the site key"
test "empty or partial configuration is rejected"
test "successful response accepts expected hostname and action"
test "missing token maps to turnstile_required"
test "timeout-or-duplicate maps to turnstile_expired"
test "invalid-input-response and malformed JSON map to turnstile_invalid"
test "wrong hostname or action maps to turnstile_invalid"
test "network timeout and 5xx map to turnstile_unavailable"
test "request includes secret, response, canonical remoteip, and request idempotency_key"
```

Use a local test adapter or injected verifier; tests must never contact Cloudflare.

- [ ] **Step 2: Run the focused tests and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker/turnstile_test.exs"
```

- [ ] **Step 3: Implement verifier behaviour and Siteverify client**

Behaviour:

```elixir
@callback verify(token :: String.t(), remote_ip :: String.t(), request_id :: Ecto.UUID.t()) ::
            :ok
            | {:error, :turnstile_required | :turnstile_invalid | :turnstile_expired | :turnstile_unavailable}
```

Production implementation posts a form body through the existing Finch process to:

```text
https://challenges.cloudflare.com/turnstile/v0/siteverify
```

It validates `success`, known error codes, hostname `ai-sticker-maker.com` (allow `www.ai-sticker-maker.com` only if production serves it), and action `sticker_generation` when present. Never log the secret or full token.

- [ ] **Step 4: Add all-or-none runtime configuration**

In `config/config.exs`, default to disabled and set the verifier module. In `config/runtime.exs`, normalize empty strings to missing and enforce:

```elixir
case {turnstile_site_key, turnstile_secret_key} do
  {nil, nil} -> config :sticker, :turnstile, enabled: false
  {site_key, secret_key} -> config :sticker, :turnstile, enabled: true, site_key: site_key, secret_key: secret_key
  _ -> raise "TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY must be configured together"
end
```

Configure `:guest_ip_hash_secret` from `GUEST_IP_HASH_SECRET` without printing it. Tests override verifier/config through `Application.put_env/3` and restore configuration in `on_exit/1`.

- [ ] **Step 5: Run tests and a partial-config startup check**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=prod -e TURNSTILE_SITE_KEY=test-site-only -e DATABASE_URL=ecto://postgres:postgres@host.docker.internal/sticker_test -e SECRET_KEY_BASE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix loadconfig"
```

Expected: non-zero exit with the explicit paired-key configuration error and no secret value in output. Then rerun with both keys absent; expected configuration succeeds.

- [ ] **Step 6: Commit Turnstile server support**

```powershell
git add lib/sticker/turnstile.ex lib/sticker/turnstile/verifier.ex config/config.exs config/runtime.exs config/test.exs test/sticker/turnstile_test.exs
git commit -m "Add Turnstile server verification"
```

## Task 6: Implement One Guest Generation Policy Gate

**Files:**
- Create: `lib/sticker/guest_generation_gate.ex`
- Create: `test/sticker/guest_generation_gate_test.exs`

- [ ] **Step 1: Write the failing policy matrix**

Test every branch, including ordering:

| Scenario | Expected result | Ledger row |
| --- | --- | --- |
| Authenticated user | `{:ok, :authenticated}` | No |
| Guest has no credits | `:guest_credits_exhausted` | No |
| First request, low risk, Turnstile disabled | Authorized | Yes |
| First request, low risk, Turnstile enabled | Authorized without token | Yes |
| Guest has already started one task | `:turnstile_required` until verified | No before verify |
| Same IP has 3 tasks in 10 minutes | Risk challenge on first guest request | No before verify |
| Same IP has 2 guest IDs in 10 minutes | Risk challenge on first guest request | No before verify |
| Bad/expired/unavailable token | Dedicated error | No |
| New total exceeds six/24h | `:guest_ip_limited` | No |
| Duplicate request ID | `:attempt_duplicate` | No additional row |
| Batch of 3 at network usage 4 | `:guest_ip_limited` | No partial row |

Also assert parameter guards reject nil/malformed IDs, non-UUID request IDs, invalid modes, task counts outside `1..5`, and absent/canonical IP context before querying or inserting.

- [ ] **Step 2: Run tests and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker/guest_generation_gate_test.exs"
```

- [ ] **Step 3: Implement the orchestration in policy order**

Expose one function:

```elixir
def authorize(%{
      current_user: current_user,
      guest_user_id: guest_user_id,
      canonical_ip: canonical_ip,
      request_id: request_id,
      mode: mode,
      task_count: task_count,
      turnstile_token: token
    })
```

Order is part of the contract:

1. Authenticated user returns immediately without hash, risk, Turnstile, or ledger work.
2. Validate server-owned identity/request/mode/task count.
3. Confirm guest credits can cover `task_count`.
4. Hash the canonical IP and get 10-minute risk stats.
5. Require a challenge only when Turnstile is enabled and either the guest already spent at least one credit, IP task count is at least three, or distinct guest count is at least two.
6. Verify the token when required.
7. Atomically reserve the attempt.

Return metadata including challenge reason so the UI/telemetry can distinguish policy outcomes without exposing IP data. Do not spend credits or create predictions in this module.

- [ ] **Step 4: Run the complete gate and ledger test set**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker/guest_abuse_test.exs test/sticker/turnstile_test.exs test/sticker/guest_generation_gate_test.exs"
```

- [ ] **Step 5: Commit the policy gate**

```powershell
git add lib/sticker/guest_generation_gate.ex test/sticker/guest_generation_gate_test.exs
git commit -m "Enforce guest generation abuse policy"
```

## Task 7: Enforce the Gate in Text, Batch, and Portrait Generation

**Files:**
- Modify: `lib/sticker_web/guest_identity.ex`
- Modify: `lib/sticker_web/live/home_live.ex`
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `assets/js/app.js`
- Modify: `assets/css/app.css`
- Create: `assets/js/turnstile_hook_test.mjs`
- Modify: `test/emoji_web/live/home_live_test.exs`

- [ ] **Step 1: Write failing end-to-end LiveView tests**

Add deterministic test-verifier coverage for:

```elixir
test "first low-risk guest text request starts without a challenge"
test "second guest request renders the challenge and does not spend before verification"
test "valid token starts second request and is not reusable"
test "expired token resets challenge and keeps the credit"
test "network quota error keeps credit and shows sign-in action"
test "batch reserves the parsed prompt count before spending credits"
test "oversized and invalid batch fails before ledger reservation"
test "portrait validation, upload, and safety failures occur before reservation"
test "valid portrait reserves one task before creating its prediction"
test "prediction creation failure refunds credit but retains attempt row"
test "authenticated text, batch, and portrait requests create no guest attempt"
test "duplicate request reloads recent results and rotates request_id"
```

Assert exact stable user messages from the design, not Cloudflare/provider error codes.

- [ ] **Step 2: Run LiveView tests and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/emoji_web/live/home_live_test.exs"
```

- [ ] **Step 3: Put canonical request context in the LiveView session**

The browser plug computes `canonical_ip = AbuseProtection.client_ip(conn)` and stores only the current request's canonical string in the signed session for LiveView use; it must not store raw IP in the database or analytics. Mount assigns:

```elixir
guest_user_id: session["guest_user_id"],
canonical_ip: session["guest_client_ip"],
request_id: Ecto.UUID.generate(),
turnstile_token: nil,
turnstile_required?: false,
turnstile_site_key: Sticker.Turnstile.site_key()
```

Keep `local_user_id` as the prediction owner identity already used by the rest of the UI.

- [ ] **Step 4: Authorize only after validation and before credit spending**

For text:

```elixir
with {:ok, prompts} <- PromptInput.parse(prompt, batch?: socket.assigns.batch_mode),
     :ok <- authorize_generation(socket, :text, length(prompts), params),
     {:ok, credit_result, predictions} <- start_text_predictions(...) do
  ...
end
```

For portrait, keep file type/size, upload consumption, image safety, and prompt validation before calling `authorize_generation(socket, :portrait, 1, params)`. Call it immediately before `create_face_prediction/5`, so rejected or unsafe uploads do not consume the network ledger. If storage must occur before safety validation, delete any temporary object through the existing cleanup path on rejection.

Rotate `request_id` after success and every terminal failure. On `:turnstile_required`, retain the same intended request ID while waiting for a token; after any submitted token is accepted or rejected, rotate and reset the widget. On `:attempt_duplicate`, reload the server-owned guest's recent predictions, rotate, and never call the provider.

- [ ] **Step 5: Render a compact explicit Turnstile state**

Place it directly above the Generate action, not in a modal:

```heex
<div
  :if={@turnstile_required? and @turnstile_site_key}
  id="guest-turnstile"
  phx-hook="Turnstile"
  phx-update="ignore"
  data-site-key={@turnstile_site_key}
  data-action="sticker_generation"
>
  <div data-turnstile-container></div>
</div>
<p :if={@turnstile_required?} class="saas-security-help">
  Complete the security check to continue.
</p>
```

The hook uses Cloudflare explicit rendering, pushes only `turnstile-token`, reacts to `turnstile-reset`, and handles expired/error callbacks by clearing the token. Disable Generate only while a required token is absent. Keep the first low-risk request unchanged.

Load the official Turnstile API script only when a site key exists, with `render=explicit`, asynchronously/deferred. Do not add an npm dependency.

- [ ] **Step 6: Test the JavaScript token lifecycle**

Extract the hook factory or export it in a way the existing standalone Node tests can import. In `turnstile_hook_test.mjs`, stub `window.turnstile` and assert exactly one widget renders, callback pushes a token, expiry clears it, a reset event calls `turnstile.reset`, and destroy removes the widget.

```powershell
node assets/js/turnstile_hook_test.mjs
```

Expected: all assertions pass without contacting Cloudflare.

- [ ] **Step 7: Run UI and generation regression tests**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/emoji_web/live/home_live_test.exs test/emoji/predictions_test.exs test/emoji/guest_trials_test.exs"
```

- [ ] **Step 8: Commit generation integration**

```powershell
git add lib/sticker_web/guest_identity.ex lib/sticker_web/live/home_live.ex lib/sticker_web/live/home_live.html.heex assets/js/app.js assets/js/turnstile_hook_test.mjs assets/css/app.css test/emoji_web/live/home_live_test.exs
git commit -m "Protect guest sticker generation flows"
```

## Task 8: Preserve Login, Logout, Signup, History, and Refund Compatibility

**Files:**
- Modify: `lib/sticker_web/controllers/user_session_controller.ex`
- Modify: `lib/sticker_web/controllers/user_registration_controller.ex`
- Modify: `test/sticker_web/guest_identity_test.exs`
- Modify: `test/emoji_web/controllers/page_controller_test.exs`
- Modify: `test/emoji_web/live/history_live_test.exs`
- Modify: `test/emoji/predictions_test.exs`

- [ ] **Step 1: Write failing lifecycle compatibility tests**

Cover the full conversion path:

```elixir
test "guest cookie survives session renewal on login"
test "login transfers predictions from guest_user_id to account public_id"
test "logout restores guest_user_id as local_user_id without a new allowance"
test "registration records guest_user_id rather than account local_user_id"
test "confirmation grants only the originating guest allowance remaining"
test "failed and canceled predictions refund credit once but retain attempt row"
test "history and download ownership remain account-based after transfer"
```

Use a guest who spent two of three credits, register/confirm, and assert the account receives exactly one free credit, never three.

- [ ] **Step 2: Run the focused compatibility suite and verify failure**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test test/sticker_web/guest_identity_test.exs test/emoji_web/controllers/page_controller_test.exs test/emoji_web/live/history_live_test.exs test/emoji/predictions_test.exs"
```

- [ ] **Step 3: Update account lifecycle sources without clearing the guest cookie**

- In login, read `guest_user_id` before session renewal and transfer its predictions to `user.public_id`; do not infer it from client input.
- After `clear_session`/renew, repopulate `user_id`, account `local_user_id`, and preserved `guest_user_id` in the signed session. The dedicated response cookie remains untouched.
- On logout, clear auth session as today; the next browser-pipeline pass verifies the dedicated cookie and restores the same guest identity/allowance.
- In registration, set `signup_guest_user_id` from `get_session(conn, :guest_user_id)`, with `local_user_id` fallback only for one rollout compatibility window.
- Keep `GuestTrials.free_credits_for_signup/1`, refund idempotency, prediction ownership transfer, history, and download controller logic unchanged unless a failing compatibility test proves an adapter is required.

- [ ] **Step 4: Run compatibility and full auth tests**

Run the Step 2 command and all account/session controller tests discovered by `rg --files test | rg 'user|account|session|registration'`.

Expected: guest allowance is never regenerated by login/logout, and all existing account flows pass.

- [ ] **Step 5: Commit lifecycle compatibility**

```powershell
git add lib/sticker_web/controllers/user_session_controller.ex lib/sticker_web/controllers/user_registration_controller.ex test/sticker_web/guest_identity_test.exs test/emoji_web/controllers/page_controller_test.exs test/emoji_web/live/history_live_test.exs test/emoji/predictions_test.exs
git commit -m "Preserve guest allowance across account lifecycle"
```

## Task 9: Run the Mandatory Functional Integrity Audit

**Files:**
- Review all files changed in Tasks 1-8.
- Create only if a defect is found: focused regression tests in the corresponding test file.

- [ ] **Step 1: Audit interface parameter completeness**

Verify every public function and form boundary defines required/optional parameters, guards types, and rejects client-owned server fields. Confirm `request_id`, token, mode, and task count cannot be mismatched across text/portrait/batch flows.

- [ ] **Step 2: Audit request/response and error completeness**

Build a checklist against the `Public Contracts` and design error table. Every error atom must map once to a stable UI response and must specify whether credit and ledger state changed. No generic catch-all may turn an authorization failure into provider work.

- [ ] **Step 3: Audit abnormal and boundary scenarios**

Explicitly re-run or add tests for empty token, malformed UUID, zero/negative/6 task counts, exact 10-minute and 24-hour boundaries, concurrent duplicate requests, quota overflow, partial configuration, missing identity, malformed cookies, permission mismatch, expired/single-use token, verifier outage, storage failure, prediction insert failure, provider failure, cancel, and refund.

- [ ] **Step 4: Audit implementation/spec consistency and compatibility**

Compare code with `docs/superpowers/specs/2026-07-26-guest-abuse-protection-design.md` line by line. Confirm:

- three guest credits remain;
- six network tasks are rolling 24 hours and guest-only;
- risk is `>=3` tasks or `>=2` identities in ten minutes;
- second/third guest request is challenged only when both keys exist;
- authenticated users bypass guest quota and challenge;
- attempt rows survive refunds/failures;
- no raw IP or secret enters DB/log/analytics/source;
- old signed-session users migrate and stale JS cannot crash;
- downloads, history, account credits, daily/active limits, and webhooks remain compatible.

- [ ] **Step 5: Run the full automated suite and static checks**

```powershell
docker run --rm -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=host.docker.internal -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket hexpm/elixir:1.16.0-erlang-26.2.1-debian-bookworm-20231009-slim sh -lc "mix test"
node assets/js/turnstile_hook_test.mjs
git diff --check
rg -n "TURNSTILE_SECRET_KEY|GUEST_IP_HASH_SECRET|CF-Connecting-IP|localStorage\.userId|post \"/session\"" lib assets config test
```

Expected: all tests pass, Node assertions pass, `git diff --check` is clean, no literal secret exists, no active client identity path exists, and no code relies on `CF-Connecting-IP`.

- [ ] **Step 6: Produce and resolve the integrity report**

Before deployment, write the result in the execution handoff using these headings:

```text
Functional integrity report
Missing items
Root causes
One-command remediation
```

If any dimension fails, add the smallest failing test and fix it before proceeding. The remediation command must rerun the exact affected test set plus `mix test`. Do not deploy with any missing item.

- [ ] **Step 7: Commit audit fixes, if any**

Use a focused commit such as:

```powershell
git commit -am "Close guest abuse integrity gaps"
```

Do not create an empty commit when the audit finds no defects.

## Task 10: Stage, Configure Cloudflare, Deploy, and Verify Production

**Files/Systems:**
- Cloudflare Dashboard: create one Turnstile Managed widget for `ai-sticker-maker.com`.
- Production server `43.173.94.85`: environment configuration and application restart.
- GitHub Actions: existing push-to-deploy workflow.
- Production browser: `https://ai-sticker-maker.com`.

- [ ] **Step 1: Read the browser-control and verification skills before external operations**

During execution, load `chrome:control-chrome` before using the signed-in Cloudflare tab and load `vercel:agent-browser-verify` (or the repository's established browser verification skill) before production browser checks. Never expose dashboard secrets in screenshots, logs, shell output, commits, or the final response.

- [ ] **Step 2: Deploy application and migration with Turnstile disabled**

Push the reviewed commits through the existing GitHub deployment path while both Turnstile variables remain absent. Monitor the workflow to completion, then verify:

```text
GET / returns 200
new _sticker_guest cookie is HttpOnly, signed, SameSite=Lax, Secure
first, second, and third guest generations remain possible before key activation
migration guest_generation_attempts exists and accepts reservations
```

This stage proves the additive migration and server identity changes do not block the funnel.

- [ ] **Step 3: Create the Cloudflare Managed widget in the signed-in account**

In Cloudflare Dashboard, navigate to Turnstile, create a Managed widget, allow only:

```text
ai-sticker-maker.com
www.ai-sticker-maker.com (only if this hostname currently serves the product)
```

Use action `sticker_generation` in the application widget render. Record the site key and secret only into ephemeral secure variables for immediate server configuration; never paste them into source or commentary.

- [ ] **Step 4: Configure production secrets atomically**

Generate a stable high-entropy `GUEST_IP_HASH_SECRET` locally without printing it, and set all three production variables through the server's existing environment mechanism:

```text
TURNSTILE_SITE_KEY
TURNSTILE_SECRET_KEY
GUEST_IP_HASH_SECRET
```

Back up only the environment file permissions/metadata if the deployment convention requires it. Apply both Turnstile keys in the same edit and restart once. Confirm the service starts; a partial-key state must fail fast by design.

- [ ] **Step 5: Verify the production policy matrix with controlled identities**

Use disposable test-browser contexts and a test account. Verify:

1. First low-risk guest generation starts without Turnstile.
2. Second guest generation renders Turnstile, stays disabled until completion, then starts exactly once.
3. Third guest generation also requires Turnstile.
4. Fourth guest generation is blocked by exhausted guest credits and offers sign-in.
5. Clearing browser storage but keeping cookies preserves the same allowance.
6. A new browser identity on the same network contributes to the same IP ledger and cannot exceed six total tasks.
7. A risk-triggered first request shows Turnstile after the IP reaches three tasks or two identities in ten minutes.
8. Expired/reset challenge does not spend a credit or reserve a row.
9. A failed generation refunds credit but the attempt count stays increased.
10. An authenticated user on the limited network can generate with account credits and creates no guest attempt.

Use database aggregate queries that return counts only; do not output raw IP hashes, cookie values, tokens, or secrets.

- [ ] **Step 6: Verify proxy and privacy assumptions**

Confirm nginx is the only public application ingress and app containers are not directly reachable. Verify nginx appends/overwrites `X-Forwarded-For` as assumed. Use a temporary privacy-safe diagnostic only if needed, remove it before completion, and confirm no raw IP appears in application logs or `guest_generation_attempts`.

- [ ] **Step 7: Monitor and rollback only the challenge activation if needed**

Observe error rate, guest generation starts, Turnstile verification failures, quota rejections, and account conversion for at least one controlled verification window. If Turnstile itself blocks valid users, remove both Turnstile environment variables together and restart; keep the server-owned cookie and IP ledger active. Do not roll back the additive migration or erase attempt rows.

- [ ] **Step 8: Record deployment evidence and final integrity status**

Record commit SHA, GitHub workflow result, migration status, HTTP checks, browser scenarios, and privacy checks without secrets. Finish with the mandatory functional integrity report from Task 9 and list any residual operational risk, especially shared-network false positives and origin proxy trust.

## Execution Exit Criteria

Implementation is complete only when all of the following are true:

- The browser cannot select, overwrite, or read the signed guest ID through JavaScript.
- Guest identity survives cache clearing, login, logout, and auth-session renewal unless cookies are explicitly cleared.
- A new browser/cookie cannot exceed the six-task rolling network budget.
- First low-risk generation remains one-click; second/third and risky first requests use server-verified Turnstile when configured.
- Text, batch, and portrait flows enforce the same gate before model work.
- Duplicate/invalid/expired requests cannot double spend or double start provider tasks.
- Failed/canceled/refunded work remains in the attempt ledger while credit refund behavior remains idempotent.
- Authenticated users bypass guest-only protections and retain all existing account limits.
- Full Elixir and JavaScript tests pass, production migration is applied, and real browser checks pass.
- The eight mandatory integrity dimensions have no unresolved missing items.
