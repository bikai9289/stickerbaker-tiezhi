# Generation Feedback and History Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generation progress understandable and cancellable while making `/account` and `/stickers` render progressively with bounded, indexed queries and stable image placeholders.

**Architecture:** Keep Phoenix LiveView as the orchestration layer. Disconnected mounts render deterministic shells; connected mounts use supervised `start_async/3` tasks and request references so independent sections can load or fail without blocking each other. Shared sticker cards expose real backend phases, client-only slow-state and preview hooks, and parent-owned cancel events.

**Tech Stack:** Elixir 1.14, Phoenix LiveView, Ecto/PostgreSQL, HEEx, existing vanilla JavaScript hooks, CSS, ExUnit, Phoenix.LiveViewTest, Chrome production verification.

---

## File Map

- Create `priv/repo/migrations/20260725150000_optimize_history_queries.exs`: additive composite indexes.
- Modify `lib/sticker/predictions.ex`: one-query counts, bounded favorites, and existing paginated history queries.
- Modify `lib/sticker/payments.ex`: bound payment event history.
- Create `lib/sticker/load_telemetry.ex`: privacy-safe section timing spans.
- Create `test/sticker/load_telemetry_test.exs`: success and failure telemetry coverage.
- Modify `test/emoji/predictions_test.exs`: query behavior and ordering coverage.
- Modify `test/emoji/payments_test.exs`: payment history limit coverage.
- Modify `lib/sticker_web/live/account_live.ex`: independent supervised section loading and retry states.
- Modify `lib/sticker_web/live/account_live.html.heex`: section skeletons, local failures, and retry actions.
- Create `test/emoji_web/live/account_live_test.exs`: progressive account behavior.
- Modify `lib/sticker_web/live/history_live.ex`: connected-only page loading, stale-result protection, and bottom pagination state.
- Modify `lib/sticker_web/live/history_live.html.heex`: stable skeletons, shown/total text, and local loading states.
- Create `test/emoji_web/live/history_live_test.exs`: progressive history, filtering, and pagination behavior.
- Modify `lib/sticker_web/components/components.ex`: stage card, download, cancel confirmation, and image loading attributes.
- Modify `lib/sticker_web/live/home_live.ex`: cancel and refund event for current-session cards.
- Modify `lib/sticker_web/live/account_live.ex`: cancel and refund event for recent cards.
- Modify `lib/sticker_web/live/home_live.html.heex`: pass cancel event and eager-image position.
- Modify `lib/sticker_web/live/account_live.html.heex`: pass cancel event and eager-image position.
- Modify `lib/sticker_web/live/history_live.html.heex`: pass eager-image position while retaining history actions.
- Modify `assets/js/app.js`: slow-generation and preview retry hooks plus privacy-safe timing events.
- Modify `assets/css/app.css`: stable skeletons, phase progress, confirmation, error, and reduced-motion styles.
- Modify `test/emoji_web/components/components_test.exs`: all generation card states.
- Modify `test/emoji_web/live/home_live_test.exs`: cancellation and refund behavior.

## Task 1: Optimize and Bound Account Queries

**Files:**
- Create: `priv/repo/migrations/20260725150000_optimize_history_queries.exs`
- Create: `lib/sticker/load_telemetry.ex`
- Modify: `lib/sticker/predictions.ex`
- Modify: `lib/sticker/payments.ex`
- Test: `test/sticker/load_telemetry_test.exs`
- Test: `test/emoji/predictions_test.exs`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing prediction query tests**

Add tests that create mixed statuses and favorites, then assert one public count result and bounded ordering:

```elixir
test "user_prediction_counts/1 returns all counters from one result" do
  user_id = "count-user"
  prediction_fixture(%{local_user_id: user_id, status: :succeeded, is_favorite: true})
  prediction_fixture(%{local_user_id: user_id, status: :failed, is_favorite: false})

  assert %{total: 2, completed: 1, failed: 1, favorites: 1} =
           Predictions.user_prediction_counts(user_id)
end

test "list_user_favorite_predictions/2 is newest-first and bounded" do
  user_id = "favorite-user"
  older = prediction_fixture(%{local_user_id: user_id, is_favorite: true})
  newer = prediction_fixture(%{local_user_id: user_id, is_favorite: true})

  assert [result] = Predictions.list_user_favorite_predictions(user_id, 1)
  assert result.id == newer.id
  refute result.id == older.id
end
```

- [ ] **Step 2: Write the failing payment limit test**

Create more than two payment events for one user and assert:

```elixir
assert [newest, second] = Payments.list_user_payment_events(user.id, 2)
assert newest.inserted_at >= second.inserted_at
```

- [ ] **Step 3: Run focused tests and verify failure**

Run:

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-test-bucket MIX_ENV=test \
  mix test test/emoji/predictions_test.exs test/emoji/payments_test.exs
```

Expected: failures for the missing arity-two favorite and payment functions.

- [ ] **Step 4: Implement bounded queries and one aggregate count**

Use one aggregate select in `Predictions.user_prediction_counts/1`:

```elixir
def user_prediction_counts(user_id) do
  from(p in Prediction,
    where: p.local_user_id == ^user_id,
    select: %{
      total: count(p.id),
      completed: filter(count(p.id), p.status == :succeeded),
      failed: filter(count(p.id), p.status == :failed),
      favorites: filter(count(p.id), p.is_favorite == true)
    }
  )
  |> Repo.one!()
end

def list_user_favorite_predictions(user_id, limit \\ 12) do
  from(p in Prediction,
    where:
      p.local_user_id == ^user_id and p.is_favorite == true and
        not is_nil(p.sticker_output),
    order_by: [desc: p.updated_at],
    limit: ^max(limit, 1)
  )
  |> Repo.all()
end
```

Bound payment events similarly:

```elixir
def list_user_payment_events(user_id, limit \\ 20) do
  from(e in PaymentEvent,
    where: e.user_id == ^user_id,
    order_by: [desc: e.inserted_at],
    limit: ^max(limit, 1)
  )
  |> Repo.all()
end
```

- [ ] **Step 5: Add additive composite indexes**

Create the migration:

```elixir
defmodule Sticker.Repo.Migrations.OptimizeHistoryQueries do
  use Ecto.Migration

  def change do
    create index(:predictions, [:local_user_id, :inserted_at])
    create index(:predictions, [:local_user_id, :is_favorite, :updated_at])
    create index(:payment_events, [:user_id, :inserted_at])
    create index(:payment_attempts, [:user_id, :inserted_at])
  end
end
```

- [ ] **Step 6: Add privacy-safe section telemetry**

Create `Sticker.LoadTelemetry`:

```elixir
defmodule Sticker.LoadTelemetry do
  @event [:sticker, :ui_load]

  def measure(section, metadata \\ %{}, fun)
      when is_atom(section) and is_map(metadata) and is_function(fun, 0) do
    :telemetry.span(@event, Map.put(metadata, :section, section), fn ->
      result = fun.()
      {result, %{status: :ok, item_count: item_count(result)}}
    end)
  end

  defp item_count(result) when is_list(result), do: length(result)
  defp item_count(%{entries: entries}) when is_list(entries), do: length(entries)
  defp item_count(_result), do: nil
end
```

Attach a test handler to `[:sticker, :ui_load, :stop]` and
`[:sticker, :ui_load, :exception]`. Assert success includes `section`, `duration`, and `item_count`,
while a raised function emits an exception event and re-raises. Metadata must never contain prompt,
email, image URL, or payment identifiers.

- [ ] **Step 7: Run focused tests and migration checks**

Run the focused tests from Step 3 and:

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres MIX_ENV=test mix ecto.migrate
```

Expected: all focused tests pass and migration completes without modifying existing rows.

- [ ] **Step 8: Commit query work**

```bash
git add priv/repo/migrations/20260725150000_optimize_history_queries.exs \
  lib/sticker/predictions.ex lib/sticker/payments.ex lib/sticker/load_telemetry.ex \
  test/emoji/predictions_test.exs test/emoji/payments_test.exs \
  test/sticker/load_telemetry_test.exs
git commit -m "Optimize account and history queries"
```

## Task 2: Progressively Load Account Sections

**Files:**
- Modify: `lib/sticker_web/live/account_live.ex`
- Modify: `lib/sticker_web/live/account_live.html.heex`
- Create: `test/emoji_web/live/account_live_test.exs`

- [ ] **Step 1: Write failing progressive account tests**

Authenticate a fixture user and assert the disconnected render contains stable section markers and
the connected view resolves them:

```elixir
test "account renders section skeletons then loads each section", %{conn: conn} do
  user = user_fixture()
  conn = init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})

  html = get(conn, ~p"/account") |> html_response(200)
  assert html =~ ~s(id="account-recent-loading")
  assert html =~ ~s(id="account-favorites-loading")
  assert html =~ ~s(id="account-payments-loading")

  {:ok, view, _html} = live(conn, ~p"/account")
  assert render_async(view) =~ ~s(id="account-recent")
end
```

Add a retry test that sends a failed async result, clicks the section retry button, and verifies only
that section returns to loading.

- [ ] **Step 2: Run the new test and verify failure**

Run:

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-test-bucket MIX_ENV=test \
  mix test test/emoji_web/live/account_live_test.exs
```

Expected: missing loading markers and async behavior.

- [ ] **Step 3: Initialize deterministic account states**

In both mounts assign empty streams and explicit states:

```elixir
|> assign(:summary_state, :loading)
|> assign(:recent_state, :loading)
|> assign(:favorites_state, :loading)
|> assign(:payments_state, :loading)
|> assign(:counts, %{total: nil, completed: nil, failed: nil, favorites: nil})
|> assign(:payment_attempts, [])
|> assign(:payments, [])
|> stream(:recent_predictions, [])
|> stream(:favorite_predictions, [])
```

Only when `connected?(socket)` call `start_account_loads/2`, which starts four named tasks:

```elixir
socket
|> start_async(:account_summary, fn ->
  Sticker.LoadTelemetry.measure(:account_summary, %{}, fn ->
    Predictions.user_prediction_counts(user_id)
  end)
end)
|> start_async(:account_recent, fn ->
  Sticker.LoadTelemetry.measure(:account_recent, %{limit: 12}, fn ->
    Predictions.list_user_recent_predictions(user_id, 12)
  end)
end)
|> start_async(:account_favorites, fn ->
  Sticker.LoadTelemetry.measure(:account_favorites, %{limit: 12}, fn ->
    Predictions.list_user_favorite_predictions(user_id, 12)
  end)
end)
|> start_async(:account_payments, fn ->
  Sticker.LoadTelemetry.measure(:account_payments, %{limit: 20}, fn ->
    {Payments.list_user_payment_attempts(user.id), Payments.list_user_payment_events(user.id, 20)}
  end)
end)
```

- [ ] **Step 4: Handle independent success and failure results**

Add `handle_async/3` clauses that set only the matching state and stream. For example:

```elixir
def handle_async(:account_recent, {:ok, predictions}, socket) do
  {:noreply,
   socket
   |> assign(:recent_state, :loaded)
   |> stream(:recent_predictions, predictions, reset: true)}
end

def handle_async(name, {:exit, _reason}, socket)
    when name in [:account_summary, :account_recent, :account_favorites, :account_payments] do
  {:noreply, assign(socket, state_key(name), :failed)}
end
```

Implement `retry-section` with a strict allowlist and restart only that named task.

- [ ] **Step 5: Render section-local skeleton, error, empty, and loaded states**

Add stable IDs such as `account-recent-loading`, `account-recent-error`, and `account-recent`. Use
shared skeleton classes, keep section headings visible, and render a `Retry` button only in the failed
branch. Link the favorite preview to `/stickers?status=favorites`.

- [ ] **Step 6: Run account tests**

Run the command from Step 2. Expected: all account tests pass without executing section queries in
the disconnected render.

- [ ] **Step 7: Commit account loading**

```bash
git add lib/sticker_web/live/account_live.ex lib/sticker_web/live/account_live.html.heex \
  test/emoji_web/live/account_live_test.exs
git commit -m "Load account sections progressively"
```

## Task 3: Progressively Load and Paginate History

**Files:**
- Modify: `lib/sticker_web/live/history_live.ex`
- Modify: `lib/sticker_web/live/history_live.html.heex`
- Create: `test/emoji_web/live/history_live_test.exs`

- [ ] **Step 1: Write failing history loading tests**

Cover disconnected skeletons, connected results, filter replacement, stale request references, and
load-more text:

```elixir
test "history loads only after LiveView connects and reports shown count", %{conn: conn} do
  user = user_fixture()
  for index <- 1..25,
      do: prediction_fixture(%{local_user_id: user.public_id, prompt: "item #{index}"})

  conn = init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
  assert get(conn, ~p"/stickers") |> html_response(200) =~ ~s(id="history-initial-loading")

  {:ok, view, _html} = live(conn, ~p"/stickers")
  html = render_async(view)
  assert html =~ "Showing 24 of 25"
  assert has_element?(view, "button", "Load more")
end
```

- [ ] **Step 2: Run the history test and verify failure**

Run:

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-test-bucket MIX_ENV=test \
  mix test test/emoji_web/live/history_live_test.exs
```

Expected: initial render currently contains records and has no loading marker.

- [ ] **Step 3: Replace synchronous mount data with connected tasks**

Assign an empty page and `:loading` states in mount. On connection start:

```elixir
ref = System.unique_integer([:positive, :monotonic])

socket
|> assign(:history_request_ref, ref)
|> assign(:history_state, :loading)
|> start_async({:history_page, ref}, fn ->
  Sticker.LoadTelemetry.measure(:history_page, %{page: 0, per_page: @per_page}, fn ->
    Predictions.paginate_user_predictions(user_id, filters, 0, @per_page)
  end)
end)
|> start_async(:history_batches, fn ->
  Sticker.LoadTelemetry.measure(:history_batches, %{}, fn ->
    Predictions.list_user_batches(user_id)
  end)
end)
```

Make the existing user-assignment event idempotent so the authenticated `AssignUserId` hook cannot
start the same initial query twice:

```elixir
def handle_event("assign-user-id", %{"userId" => user_id},
      %{assigns: %{local_user_id: user_id}} = socket) do
  {:noreply, socket}
end
```

- [ ] **Step 4: Ignore stale filter results**

Apply a result only when its reference matches:

```elixir
def handle_async({:history_page, ref}, {:ok, page},
      %{assigns: %{history_request_ref: ref}} = socket) do
  {:noreply,
   socket
   |> assign(:history_state, :loaded)
   |> assign_page(page)
   |> stream(:predictions, page.entries, reset: true)}
end

def handle_async({:history_page, _stale_ref}, _result, socket), do: {:noreply, socket}
```

Each filter creates a new reference. Each load-more request uses a separate
`{:history_more, ref, next_page}` name, keeps existing cards, and exposes a bottom-loading state.

- [ ] **Step 5: Render stable history states**

Render 24 initial skeleton cards, eight bottom skeleton cards during load more, local retry for first
page failure, `Showing N of total`, and `All stickers loaded`. Preserve toolbar values and current
cards during pagination.

- [ ] **Step 6: Run history tests**

Run the command from Step 2. Expected: all history tests pass, including stale response protection.

- [ ] **Step 7: Commit history loading**

```bash
git add lib/sticker_web/live/history_live.ex lib/sticker_web/live/history_live.html.heex \
  test/emoji_web/live/history_live_test.exs
git commit -m "Load sticker history progressively"
```

## Task 4: Build the Stage-Based Generation Card

**Files:**
- Modify: `lib/sticker_web/components/components.ex`
- Modify: `test/emoji_web/components/components_test.exs`

- [ ] **Step 1: Write failing component state tests**

Render `starting`, `moderation_succeeded`, `processing`, `succeeded`, `failed`, and `canceled`
predictions. Assert stable frame markup, the correct active phase, no numeric percentage, refund text,
and no nested button inside a link.

```elixir
assert html =~ ~s(data-generation-state="processing")
assert html =~ "Creating sticker"
assert html =~ "Cancel &amp; refund"
refute html =~ "%"
```

- [ ] **Step 2: Run component tests and verify failure**

Run:

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-test-bucket MIX_ENV=test \
  mix test test/emoji_web/components/components_test.exs
```

- [ ] **Step 3: Add component attributes and status helpers**

Add:

```elixir
attr :cancel_event, :string, default: nil
attr :eager, :boolean, default: false

defp active_generation?(prediction),
  do: prediction.status in [:starting, :moderation_succeeded, :processing]

defp generation_phase(%{status: :starting}), do: 1
defp generation_phase(%{status: :moderation_succeeded}), do: 2
defp generation_phase(%{status: :processing}), do: 3
```

Refactor the card so the navigation link wraps only preview and caption. Render actions as sibling
elements to avoid nested interactive controls.

- [ ] **Step 4: Render real phases and inline cancellation confirmation**

Use a three-item ordered phase list and `<details>` confirmation:

```heex
<details :if={active_generation?(@prediction) and @cancel_event} class="saas-cancel-confirm">
  <summary>Cancel &amp; refund</summary>
  <p>Cancel this generation and return 1 credit?</p>
  <button
    type="button"
    phx-click={@cancel_event}
    phx-value-id={@prediction.id}
    phx-disable-with="Canceling..."
  >
    Cancel generation
  </button>
</details>
```

Add success download, failed refund, canceled refund, and unavailable preview states.

- [ ] **Step 5: Run component tests**

Expected: all component states pass and HTML has valid interactive structure.

- [ ] **Step 6: Commit component work**

```bash
git add lib/sticker_web/components/components.ex test/emoji_web/components/components_test.exs
git commit -m "Improve generation status cards"
```

## Task 5: Wire Cancel and Refund into Home and Account

**Files:**
- Modify: `lib/sticker_web/live/home_live.ex`
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `lib/sticker_web/live/account_live.ex`
- Modify: `lib/sticker_web/live/account_live.html.heex`
- Modify: `test/emoji_web/live/home_live_test.exs`
- Modify: `test/emoji_web/live/account_live_test.exs`

- [ ] **Step 1: Write failing cancellation tests**

Create an active account prediction with a spent credit. Click `cancel-generation` twice and assert
one refund, a canceled status, and an in-place card:

```elixir
view |> element("button[phx-click='cancel-generation'][phx-value-id='#{prediction.id}']") |> render_click()
assert Predictions.get_prediction!(prediction.id).status == :canceled
assert Accounts.get_user(user.id).credits == credits_before + 1
```

Also cover a completion race returning `:not_cancelable` without another refund.

- [ ] **Step 2: Run HomeLive and AccountLive tests and verify failure**

Run both test files. Expected: missing `cancel-generation` event.

- [ ] **Step 3: Add a shared cancellation result pattern to both LiveViews**

In each parent:

```elixir
def handle_event("cancel-generation", %{"id" => id}, socket) do
  user_id = socket.assigns.current_user.public_id

  case Predictions.cancel_user_prediction(id, user_id) do
    {:ok, prediction} ->
      current_user = Sticker.Accounts.get_user(socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(:current_user, current_user)
       |> stream_insert(:recent_predictions, prediction)
       |> put_flash(:info, "Generation canceled. 1 credit was returned.")}

    {:error, :not_cancelable} ->
      {:noreply, put_flash(socket, :error, "This generation has already finished or stopped.")}
  end
end
```

For HomeLive, insert into `:my_predictions`; for AccountLive, insert into `:recent_predictions` and
refresh only the already-loaded summary.

- [ ] **Step 4: Pass `cancel_event="cancel-generation"` on home and account cards**

History keeps its existing explicit cancel action and passes no component cancel event.

- [ ] **Step 5: Run cancellation tests**

Expected: cancel, duplicate, unauthorized, and completion-race cases preserve one-refund behavior.

- [ ] **Step 6: Commit cancel wiring**

```bash
git add lib/sticker_web/live/home_live.ex lib/sticker_web/live/home_live.html.heex \
  lib/sticker_web/live/account_live.ex lib/sticker_web/live/account_live.html.heex \
  test/emoji_web/live/home_live_test.exs test/emoji_web/live/account_live_test.exs
git commit -m "Add cancel and refund to generation cards"
```

## Task 6: Add Stable Skeleton, Slow-State, and Preview Hooks

**Files:**
- Modify: `assets/js/app.js`
- Modify: `assets/css/app.css`
- Modify: `lib/sticker_web/components/components.ex`
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `lib/sticker_web/live/account_live.html.heex`
- Modify: `lib/sticker_web/live/history_live.html.heex`
- Test: `test/emoji_web/components/components_test.exs`

- [ ] **Step 1: Add failing markup tests for image hints and hooks**

Assert eager cards include `loading="eager" fetchpriority="high"`, later cards include
`loading="lazy" decoding="async"`, pending cards include `phx-hook="GenerationStatus"`, and preview
wrappers include `phx-hook="PreviewImage"`.

- [ ] **Step 2: Run component tests and verify failure**

Use the Task 4 focused command.

- [ ] **Step 3: Implement `GenerationStatus` hook**

```javascript
Hooks.GenerationStatus = {
  mounted() {
    this.slowTimer = window.setTimeout(() => {
      this.el.dataset.slow = "true";
      this.el.querySelector("[data-slow-message]")?.removeAttribute("hidden");
    }, 45000);
  },
  destroyed() {
    window.clearTimeout(this.slowTimer);
  },
};
```

- [ ] **Step 4: Implement `PreviewImage` hook**

Listen for image `load` and `error`, toggle `data-preview-state`, and on retry append or replace a
`preview_retry` query value. Track only `context` and `state`; do not include prompt, user, or URL.
Add `data-analytics-event="generation_cancel_attempt"` to the confirmed cancel control and push a
privacy-safe `generation_cancel_result` event containing only `outcome` after the server result.

- [ ] **Step 5: Add deterministic eager positions**

Wrap each rendered stream in `Enum.with_index/1` and pass `eager={index < 4}`. Render:

```heex
<img
  src={@prediction.sticker_output}
  loading={if @eager, do: "eager", else: "lazy"}
  fetchpriority={if @eager, do: "high", else: "auto"}
  decoding="async"
  width="1024"
  height="1024"
/>
```

- [ ] **Step 6: Add CSS for fixed skeletons and reduced motion**

Add stable square card tracks, skeleton surfaces, phase list, indeterminate progress, cancellation
confirmation, preview error overlay, and:

```css
@media (prefers-reduced-motion: reduce) {
  .saas-card-spinner,
  .saas-progress-indeterminate,
  .saas-skeleton {
    animation: none;
  }
}
```

Use restrained neutral surfaces and the existing orange action color; do not introduce decorative
gradients or layout-shifting content.

- [ ] **Step 7: Run component and LiveView tests**

Expected: all focused frontend-state tests pass.

- [ ] **Step 8: Commit frontend loading work**

```bash
git add assets/js/app.js assets/css/app.css lib/sticker_web/components/components.ex \
  lib/sticker_web/live/home_live.html.heex lib/sticker_web/live/account_live.html.heex \
  lib/sticker_web/live/history_live.html.heex test/emoji_web/components/components_test.exs
git commit -m "Add stable loading and preview feedback"
```

## Task 7: Full Verification and Production Rollout

**Files:**
- Modify only files required by failures found during verification.

- [ ] **Step 1: Format and check whitespace**

```bash
mix format
git diff --check
```

Expected: no formatting or whitespace errors.

- [ ] **Step 2: Run strict compilation**

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-dev-bucket \
  mix compile --warnings-as-errors
```

Expected: compilation succeeds without warnings.

- [ ] **Step 3: Run the full test suite**

```bash
env DB_HOST=localhost DB_USERNAME=postgres DB_PASSWORD=postgres BUCKET_NAME=sticker-test-bucket MIX_ENV=test \
  mix test
```

Expected: all tests pass with no task or SQL sandbox errors after completion.

- [ ] **Step 4: Verify query plans and boundaries**

Run `EXPLAIN` for recent, favorite, and payment queries with representative rows. Confirm indexes are
available, limits are enforced, empty accounts return valid zero states, and page values beyond the
end return an empty page without errors.

- [ ] **Step 5: Verify desktop and mobile UI in Chrome**

Use authenticated `/`, `/account`, and `/stickers` pages at desktop and mobile widths. Simulate slow
media, verify nonblank square skeletons, no overlap, real generation stages, inline cancel, local
retry, `Showing N of total`, and load-more skeletons. Verify preview image pixels are nonblank after
load and console logs contain no application errors.

- [ ] **Step 6: Verify compatibility workflows**

Confirm text and portrait generation, navigate-away recovery, single download, batch download,
favorite toggle, filters, retry, variation, delete, payment table, and one-time cancel refund.

- [ ] **Step 7: Commit verification fixes**

```bash
git add assets/js/app.js assets/css/app.css lib/sticker/load_telemetry.ex \
  lib/sticker/predictions.ex lib/sticker/payments.ex \
  lib/sticker_web/components/components.ex lib/sticker_web/live/account_live.ex \
  lib/sticker_web/live/account_live.html.heex lib/sticker_web/live/history_live.ex \
  lib/sticker_web/live/history_live.html.heex lib/sticker_web/live/home_live.ex \
  lib/sticker_web/live/home_live.html.heex test/emoji/predictions_test.exs \
  test/emoji/payments_test.exs test/emoji_web/components/components_test.exs \
  test/emoji_web/live/account_live_test.exs test/emoji_web/live/history_live_test.exs \
  test/emoji_web/live/home_live_test.exs test/sticker/load_telemetry_test.exs \
  priv/repo/migrations/20260725150000_optimize_history_queries.exs
git diff --cached --quiet || git commit -m "Verify progressive history experience"
```

- [ ] **Step 8: Push, deploy, and verify health**

Push `main`, dispatch the existing `Server Deploy` workflow if the push credential does not trigger
it, wait for success, and verify both `https://ai-sticker-maker.com/` and the local server return HTTP
200. Recheck authenticated `/account` and `/stickers` after deployment.
