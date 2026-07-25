# Generation Feedback and History Loading Design

Date: 2026-07-25
Status: Approved

## Summary

Improve the generation experience and the perceived and actual loading performance of `/account`
and `/stickers`. The implementation will combine durable, stage-based generation feedback with
progressive LiveView loading, bounded queries, database indexes, stable image skeletons, and lazy
image delivery.

## Goals

- Keep every pending generation visually stable and understandable.
- Let users cancel an active generation and receive the existing credit refund.
- Render the account and history page shells before slower data sections finish loading.
- Remove duplicate initial queries across disconnected and connected LiveView mounts.
- Reduce database round trips and make recent, favorite, and payment queries scale with account
  history.
- Prevent slow or failed images from collapsing cards or blocking the rest of a page.
- Preserve all existing generation, ownership, payment, download, and refund behavior.

## Non-Goals

- Generating dedicated thumbnail files or introducing a new image CDN.
- Replacing LiveView with a client-side application.
- Infinite scrolling on the full history page.
- Displaying a fabricated generation percentage or completion time.
- Redesigning pricing, checkout, account authentication, or the sticker detail page.

## Current Problems

### Generation cards

- A pending card can appear as a thin line instead of a stable square.
- The user cannot distinguish prompt checks, queueing, and image creation.
- There is no visible reassurance that navigation is safe while a durable task continues.
- Cancel and refund behavior exists in the history backend but is not available on the home
  generation card.

### Account page

- Initial mount performs prediction counts, recent predictions, all favorites, payment attempts,
  and payment events before rendering useful content.
- Prediction counts currently require four aggregate queries.
- Favorites and payment events are unbounded.
- Slow data or media in one section delays or visually destabilizes the whole page.

### History page

- The first page renders 24 original media files without image loading hints.
- Initial data can be queried during both disconnected and connected mounts.
- Loading, filtering, and pagination do not have stable card skeletons.
- There is no visible `shown / total` feedback.

### Data access

- Predictions have indexes for user plus status and user plus batch, but not the recent ordering
  used by the account and history pages.
- Favorites lack an index matching user, favorite state, and updated ordering.
- Payment ordering is not covered by a user plus inserted time index.

## Loading Architecture

### Shared rule

Disconnected LiveView rendering produces the complete page structure and deterministic skeletons,
but does not run the expensive history section queries. Connected mount starts independent section
loads. Each section owns its loading, loaded, empty, and failed state.

The implementation must use existing LiveView async facilities or supervised tasks whose result is
delivered back to the owning LiveView. It must not create unsupervised long-running processes.

### Account data flow

```text
Static/initial shell
        |
Connected LiveView
        |
        +-- account summary query
        +-- recent predictions query, limit 12
        +-- favorite predictions query, limit 12
        +-- payment attempts and payment events, limit 20 each
```

The four branches load independently. The account remains usable when one branch is slow or fails.
The current user credit balance can render immediately from the authenticated user assign. Generated
and favorite totals retain skeleton values until the summary query finishes.

### History data flow

```text
Static/initial shell with 24 skeleton cards
        |
Connected LiveView
        |
        +-- page 0 query, 24 entries plus total
        +-- batch summary query
```

Filtering replaces only the result grid with skeletons and preserves the toolbar values. `Load more`
requests the next explicit page and adds eight bottom skeletons while the configured next page is in
flight. The existing page size remains 24 unless implementation profiling proves that another value
is required; the loading skeleton count does not change the page size.

## Query Changes

- Replace four prediction count round trips with one aggregate query returning total, completed,
  failed, and favorites.
- Add a bounded favorite preview function for `/account`; full favorite access remains available
  through `/stickers` filtering.
- Limit payment events to the latest 20, matching the bounded payment attempt behavior.
- Keep account recent predictions limited to 12.
- Preserve history pagination and filters.

Add indexes matching the actual queries:

- `predictions(local_user_id, inserted_at DESC)` for recent and history ordering.
- `predictions(local_user_id, is_favorite, updated_at DESC)` for favorites.
- `payment_events(user_id, inserted_at DESC)` for recent payment records.
- `payment_attempts(user_id, inserted_at DESC)` for recent checkout attempts.

Migrations must be additive and compatible with existing production rows.

## Generation Card Interaction

Every generated item keeps a stable square frame and caption area from its first render. Pending
cards expose only real backend phases:

1. `Checking prompt` or `Checking portrait` for `starting`.
2. `Queued` for `moderation_succeeded`.
3. `Creating sticker` for `processing`.

The active phase uses an indeterminate progress bar. No numeric percentage is shown. The card also
states that generation normally takes a short time. After 45 seconds, client-side presentation adds:
`Still working. You can safely leave this page.` This timer changes presentation only and never
changes backend status.

### Cancel and refund

- Active cards expose `Cancel & refund`.
- The first click opens an inline confirmation with `Keep generating` and `Cancel generation`.
- Confirmation disables repeat submission while the request is in flight.
- The existing server cancellation operation remains authoritative and idempotent.
- On success, the card remains in place and changes to `Canceled` with `Credit returned`.
- If the task completed before cancellation, the server response wins and the completed card is
  shown without an extra refund.

### Terminal states

- Success crossfades the image into the same frame and exposes a clear download action.
- Failure displays a concise stage-appropriate reason and `Credit returned` when the refund flag is
  true.
- Missing legacy results remain stable and explain that no preview is available.

## Account Page Interaction

- Account summary cards render immediately with metric skeletons where data is not yet available.
- Recent stickers render 12 skeleton cards before data arrives.
- Favorites render up to 12 items and link to the complete favorites filter in `/stickers`.
- Payment records render a stable table skeleton and show the latest 20 attempts and events.
- Empty sections have an explicit empty state rather than disappearing.
- A failed section displays a local `Retry` action and does not replace the entire page with an
  error.

## History Page Interaction

- Keep the existing four-column desktop, two-column tablet, and one-column mobile grid.
- Show 24 initial skeletons with the same dimensions as final cards.
- Keep the explicit `Load more` button.
- Display `Showing N of total` while more rows exist and `All stickers loaded` at completion.
- Loading more adds skeletons only below current results.
- Search and filters preserve their values and replace only the grid contents.
- Existing batch selection, download, retry, cancel, favorite, variation, and delete actions remain
  available.

## Image Loading

- Give generated images explicit square layout constraints through the existing card frame.
- Eagerly load only the first four visible result images.
- Use native lazy loading and asynchronous decoding for subsequent images.
- Keep the existing immutable media cache headers.
- While an image is pending, show a neutral skeleton inside the final frame.
- On image error, show `Preview unavailable` with `Retry preview`; do not collapse or remove the
  item.
- Respect `prefers-reduced-motion` by disabling shimmer, spin, and crossfade motion while retaining
  visible status changes.

## Error Handling

- Async section failures are isolated to their section and are retryable.
- Stale async responses must not overwrite a newer filter, page, or generation state.
- Cancel requests handle already completed, already failed, already canceled, unauthorized, and
  missing predictions without double refunds.
- Empty datasets render useful empty states.
- Invalid pagination and filter input continues to be normalized server-side.
- Image failures do not change prediction status or download availability.

## Accessibility

- Pending state text uses `role="status"` and polite live announcements.
- Failure and cancel errors use an appropriate alert announcement.
- Progress indicators include text and do not rely on color alone.
- Cancel confirmation is keyboard accessible and returns focus predictably.
- Skeletons are hidden from assistive technology while their section exposes a loading label.
- All controls retain visible focus states and accessible names.

## Observability

Record enough telemetry to distinguish database, LiveView, and media issues:

- Account section query durations and failures.
- History first-page, filter, and load-more durations.
- Result count and page size, without recording prompt text.
- Image preview error count.
- Generation cancel attempts and outcomes.

Do not send private prompts, image URLs, payment identifiers, or user email in analytics events.

## Testing

### Data and query tests

- Aggregated prediction counts match the previous four-query behavior.
- Recent, favorite, payment, filter, and pagination limits and ordering are correct.
- Empty, extreme page, invalid filter, and duplicate request cases are covered.
- Migration indexes are present and existing rows remain readable.

### LiveView tests

- Disconnected render shows stable skeletons without expensive section results.
- Connected render loads each account section independently.
- One failed account section does not remove successful sections.
- History filter and load-more states cannot be overwritten by stale results.
- Cancel confirmation, completion race, idempotency, and refund outcomes are covered.
- Generation status changes update the existing card in place.

### Component and browser tests

- Starting, queued, processing, slow, succeeded, failed, canceled, and preview-error states render.
- Desktop, tablet, and mobile screenshots have no overlap or layout shift.
- Slow image and slow network simulations retain card dimensions and usable controls.
- Reduced-motion mode removes nonessential animation.

## Acceptance Criteria

- `/account` and `/stickers` display their structural shell and skeletons without waiting for all
  data queries.
- Account sections load independently and expose local retry states.
- Initial page queries run once per connected visit rather than once for both disconnected and
  connected mounts.
- History uses explicit pagination and reports shown versus total rows.
- Pending generation cards show their real phase, remain square, and can be canceled with the
  existing refund rules.
- Images outside the first visible row load lazily and cannot collapse their cards.
- Existing downloads, ownership, favorites, filtering, payments, guest trials, and credit behavior
  remain compatible.
- Automated tests pass and Playwright verification covers desktop and mobile layouts.

