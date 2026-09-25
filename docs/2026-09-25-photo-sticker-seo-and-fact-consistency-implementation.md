# Photo Sticker SEO and Fact Consistency Implementation

Date: 2026-09-25

## Scope

This implementation applies the approved customer-facing plan for the photo and face sticker
landing pages, guest-generation messaging, internal navigation, and Christmas page consolidation.

## Completed Changes

- Updated the homepage title to `AI Sticker Maker - Make Custom Stickers from Text or Photo`.
- Updated `/photo-to-sticker` title, H1, description, visible workflow, FAQ, styles, use cases,
  8 MB upload limit, PNG/WebP guidance, and platform notes.
- Removed misleading sign-in requirements from photo and face sticker copy and structured data.
- Clarified that guests receive up to 3 generations, each generation uses 1 credit, and failed
  generations return the credit.
- Documented guest-identity history/download behavior and account transfer behavior consistently
  across the homepage, FAQ, structured data, AI generator page, and Terms of Service.
- Changed desktop and mobile `Upload` navigation to `/photo-to-sticker`.
- Changed the Footer Face to Sticker link to `/face-to-sticker` and added Photo to Sticker,
  Reaction Sticker Maker, and Anime Avatar Sticker links.
- Added Photo to Sticker to homepage related links and removed the duplicate Christmas link.
- Made `/christmas-ai-sticker-maker` the canonical Christmas page.
- Changed `/ai-christmas-sticker-generator` to a 301 redirect to the canonical page.
- Removed the old Christmas URL from HTML/XML sitemaps and canonical-page related links.
- Added a generated-content and usage-rights section to Terms without claiming commercial rights.
- Updated controller tests for the new metadata, sitemap exclusion, related-link exclusion, and 301.

### Follow-up Content Pass

- Updated Face to Sticker title and description to match the Guest-friendly Photo page.
- Expanded Photo to Sticker structured and visible FAQs from 3 to 7 and simplified the history
  explanation for normal readers.
- Updated homepage, Face to Sticker, Photo to Sticker, AI Sticker Generator, Christmas, and Terms
  sitemap `lastmod` values to `2026-09-25`.
- Replaced the homepage section heading `Free AI Sticker Generator Online` with a broader
  text/photo creation heading so the homepage does not compete directly with the generator intent.
- Expanded Photo to Sticker, AI Sticker Generator, and Christmas pages with additional use cases,
  mobile guidance, platform/file notes, prompt examples, and visible FAQs.
- Did not add paid link placements or external backlink purchases. Those require separate risk and
  sourcing review and are outside the application deployment.

### Photo Page Replacement

- Replaced the Photo to Sticker HEEx body with the supplied full-page content structure, adapted to
  the repository's root layout and component syntax.
- Kept TDK, canonical, OG, Twitter, BreadcrumbList, HowTo, and FAQPage generation in the existing
  Phoenix SEO/structured-data pipeline instead of duplicating raw `<head>` and JSON-LD markup.
- Kept the current working portrait generator CTA because the proposed reusable LiveComponent does
  not yet exist; no non-runnable component call was introduced.
- Synchronized the controller's HowTo and seven FAQ entries with the visible Photo page copy.

### Online and Custom Sticker Pages

- Expanded `/sticker-maker-online` and `/custom-sticker-maker` to 7 FAQ entries and 10 prompt
  examples/templates each.
- Added digital-versus-printing intent guidance, workflow sections, platform specifications, and
  clearer guest-credit/download explanations.
- Synchronized both pages' visible FAQ, HowTo, title, description, and sitemap `lastmod` values.
- Restored concrete WhatsApp and Discord dimensions and file-size limits on Photo and Online pages.
- Changed the global Twitter card to `summary_large_image` to match the absolute OG image.
- Removed the duplicate short feature-card grids from the Online and Custom Sticker pages so each
  major H2 appears only once; the expanded sections remain the single source of visible content.

## Deferred Work

The reusable generator LiveComponent remains a separate development task. The current generator is
implemented inside `HomeLive`, and there is no existing `StickerWeb.GeneratorLive.Component`.
Embedding the proposed component without first extracting the upload, guest-credit, generation,
analytics, and state-management logic would be non-runnable and risk regressions. The existing
working generator entry remains available through the photo landing page CTA.

## Completeness Check

Overall status: **not fully verified in this workspace**. The implementation-level checks pass by
static inspection, but runtime and browser checks cannot be completed until the Elixir toolchain is
available.

| Dimension | Result | Evidence / follow-up |
| --- | --- | --- |
| Interface parameters | Pass | Existing routes and controller action parameters are preserved; the legacy Christmas route remains available for redirect. |
| Request/response structure | Pass | Page responses retain existing HTML/SEO structure; the legacy URL now intentionally returns HTTP 301 with the canonical `Location`. |
| Exception scenarios | Pass | Invalid or unsupported image behavior was not changed; redirect and guest copy changes do not alter generation validation. |
| Error codes and messages | Pass | No generation or payment error contract was changed. Existing validation, refund, and auth messages remain intact. |
| Business logic | Pass | Guest generation, local identity ownership, transfer-on-sign-in, downloads, history, retry, and favorites are unchanged; only public descriptions were corrected. |
| Boundary cases | Pass | Guest identity, signed-in account, 3-generation trial, 1-credit generation, failed-generation refund, 8 MB upload guidance, and old Christmas URL are covered by the copy and route changes. |
| Code/spec consistency | Pending runtime verification | Controller metadata, visible copy, structured data, sitemap, and tests were updated together. `openspec` and `mix` are unavailable in this environment, so CLI/test execution is pending in a configured Elixir environment. |
| Compatibility | Pending runtime verification | Existing routes and generator behavior are preserved; only the duplicate Christmas page intentionally changes to 301. Run the focused and full test suites before deployment. |

### Missing Items

- `openspec status/instructions` could not run because the `openspec` executable is unavailable.
- `mix format --check-formatted`, focused ExUnit tests, and the full test suite could not run because
  the `mix` executable is unavailable.
- Phoenix desktop/mobile rendering, HTTP status checks, and browser console checks could not run
  without a running development server.

### Cause

The workspace does not contain the Elixir/Mix runtime or the OpenSpec CLI on PATH. This is an
environment limitation; no application error was observed during static inspection.

### One-Command Remediation

After installing/configuring Elixir, Erlang, project dependencies, and the OpenSpec CLI, run:

```powershell
openspec status --change "customer-facing-copy-refresh" --json; mix deps.get; mix format --check-formatted; mix test test/emoji_web/controllers/page_controller_test.exs; mix test
```

Then start the Phoenix development server and perform the route/browser checks below. Any failure
must be fixed before deployment.

## Verification Commands

Run from the repository root in an Elixir/Mix environment:

```text
mix format --check-formatted
mix test test/emoji_web/controllers/page_controller_test.exs
mix test
```

Also verify manually at desktop and mobile sizes:

- `/photo-to-sticker`
- `/face-to-sticker`
- `/christmas-ai-sticker-maker`
- `/ai-christmas-sticker-generator` returns 301 to the canonical URL
- `/sitemap` and `/sitemap.xml` exclude the legacy Christmas URL
- `/terms-of-service` matches guest history and download behavior

## Environment Notes

- `openspec` CLI was not installed or available on PATH, so the repository's existing design and
  plan documents were used as the implementation context.
- `mix` was not installed or available on PATH, so formatting, compilation, tests, and browser
  verification could not be executed in this workspace.
