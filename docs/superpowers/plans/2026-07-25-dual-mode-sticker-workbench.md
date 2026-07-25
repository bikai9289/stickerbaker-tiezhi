# Dual-Mode Sticker Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clear text/portrait generator workbench with explicit credit costs, confirmed portrait uploads, accurate generation states, and atomic text batch creation.

**Architecture:** Keep the feature in `HomeLive`, adding server-owned mode and batch assigns plus small parsing/validation helpers. Replace auto-triggered upload generation with form-confirmed consumption, wrap text credit spending and prediction creation in a repository transaction, and reuse the existing prediction stream and PubSub events for status rendering.

**Tech Stack:** Elixir, Phoenix LiveView 0.20, HEEx, Ecto, CSS, ExUnit, Floki, Docker

---

## File Structure

- `lib/sticker_web/live/home_live.ex`: owns mode, batch, prompt validation, upload confirmation, credit transactions, and PubSub handling.
- `lib/sticker_web/live/home_live.html.heex`: renders one real dual-mode form and mode-specific controls.
- `lib/sticker_web/components/components.ex`: renders accurate text/portrait generation states without nested interactive controls.
- `assets/css/app.css`: styles the segmented control, mode panels, upload preview, generation tracker, and responsive layout.
- `test/emoji_web/controllers/page_controller_test.exs`: protects the rendered workbench contract.
- `test/emoji_web/live/home_live_test.exs`: exercises LiveView state and input behavior.
- `test/emoji/predictions_test.exs`: protects atomic credit/prediction behavior where the context boundary supports it.

### Task 1: Lock The Workbench Contract

**Files:**
- Modify: `test/emoji_web/controllers/page_controller_test.exs`
- Create: `test/emoji_web/live/home_live_test.exs`

- [ ] **Step 1: Write failing rendered-structure tests**

Assert that the homepage has one form, two mode buttons with `aria-pressed`, no `Reference face` anchor, a secondary `Search ideas` link, one prompt textarea, one file input, and exact credit-cost copy.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
docker build --target builder -t stickerbaker-test-base .
docker network create stickerbaker-test-net
docker run -d --name stickerbaker-test-db --network stickerbaker-test-net -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=sticker_test postgres:15-alpine
docker run --rm --network stickerbaker-test-net -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=stickerbaker-test-db -e DB_USERNAME=postgres -e DB_PASSWORD=postgres stickerbaker-test-base sh -lc "mix deps.get && mix deps.compile && mix test test/emoji_web/controllers/page_controller_test.exs test/emoji_web/live/home_live_test.exs"
```

Expected: assertions for mode buttons, one form, and server-owned mode fail against the existing combined workbench.

- [ ] **Step 3: Add LiveView behavior tests**

Use `live/2` and `render_click/3` to assert that `switch-generator-mode` changes `aria-pressed` and visible panels while preserving prompt state. Add tests for `toggle-batch-mode` and `moderation_failed` rendering.

### Task 2: Add Safe Prompt Parsing And Atomic Creation

**Files:**
- Modify: `lib/sticker_web/live/home_live.ex`
- Test: `test/emoji_web/live/home_live_test.exs`

- [ ] **Step 1: Write failing prompt validation tests**

Cover: multiline text remains one prompt by default; batch mode creates one prompt per non-empty line; six batch lines return `Up to 5 prompts`; and any prompt longer than 1,000 characters returns `Keep each prompt under 1,000 characters` before credit spending.

- [ ] **Step 2: Run tests and verify RED**

Expected: the existing `batch_prompts/1` always splits lines, silently truncates at five, and has no length validation.

- [ ] **Step 3: Implement parsing and validation**

Add `@max_prompt_length 1_000`, `parse_prompts/2`, and validation errors for empty, too long, and too many prompts. Single mode trims the complete prompt without splitting newlines; batch mode splits and rejects more than five non-empty lines.

- [ ] **Step 4: Make text creation atomic**

Wrap `GenerationCredits.spend/3` and all prediction inserts in `Sticker.Repo.transaction/1`. Roll back with `:create_failed` on any insert error so neither credits nor partial predictions persist. Keep the existing rate and active limits before transaction entry.

- [ ] **Step 5: Run focused tests and verify GREEN**

Expected: all prompt, guest-credit, and prediction creation tests pass with no partial state.

### Task 3: Require Portrait Confirmation

**Files:**
- Modify: `lib/sticker_web/live/home_live.ex`
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Test: `test/emoji_web/live/home_live_test.exs`

- [ ] **Step 1: Write failing upload-state tests**

Assert that portrait mode renders the upload helper and disabled submit state before selection, selecting a file does not create a prediction or spend a credit, `cancel-upload` removes the selected entry, and submit without a file shows `Choose a portrait before generating`.

- [ ] **Step 2: Run tests and verify RED**

Expected: the current upload is configured with `auto_upload: true` and generation runs from the upload progress callback.

- [ ] **Step 3: Implement explicit portrait submission**

Disable auto-triggered generation, keep browser upload support, render the preview with file name and real progress, add `cancel-upload`, and route `save` by the server-owned mode. Consume and generate from the selected entry only after portrait form submission.

- [ ] **Step 4: Preserve safety and credit ordering**

Keep validation and `Sticker.ImageSafety.review/1` before `GenerationCredits.spend/3`. Keep source upload, prediction creation, provider kickoff, guest analytics, and refund handling compatible with the current flow.

- [ ] **Step 5: Run upload tests and verify GREEN**

Expected: selecting/removing a file is free; only an explicit valid submit starts one portrait prediction.

### Task 4: Rebuild The Workbench UI

**Files:**
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `assets/css/app.css`
- Test: `test/emoji_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Replace anchor tabs with a segmented control**

Render `Text to sticker` and `Portrait to sticker` as `type="button"` controls with `phx-click="switch-generator-mode"`, a mode value, and `aria-pressed`. Keep `Search ideas` as a visually secondary link.

- [ ] **Step 2: Render one form and one selected panel**

Remove authenticated/guest form duplication. Derive analytics context and credit copy conditionally inside the shared form. Text mode renders the prompt and batch checkbox; portrait mode renders the preview/drop area and optional instructions.

- [ ] **Step 3: Add explicit validation and cost copy**

Show prompt count, exact credit use, remaining guest/account credits, and visible disabled reasons. Remove the inert `AI Enhance` control.

- [ ] **Step 4: Style desktop and mobile states**

Add scoped white-surface workbench rules, orange selected segment, muted helper copy, stable upload preview dimensions, concise footer layout, and `<=620px` stacking. Preserve the existing Hero palette and 8 px maximum workbench radius.

- [ ] **Step 5: Run structure tests and verify GREEN**

Expected: the homepage has one understandable form, one selected mode, and no duplicate mode controls.

### Task 5: Improve Generation States And Error Recovery

**Files:**
- Modify: `lib/sticker_web/components/components.ex`
- Modify: `lib/sticker_web/live/home_live.ex`
- Modify: `assets/css/app.css`
- Test: `test/emoji_web/live/home_live_test.exs`

- [ ] **Step 1: Write failing status-copy tests**

Render starting, moderation-approved, processing, failed-text, and failed-portrait predictions. Assert mode-specific labels, `Credit returned`, and valid link/button structure.

- [ ] **Step 2: Run tests and verify RED**

Expected: failed text predictions currently advise using a clearer portrait and generated content nests a button inside a link.

- [ ] **Step 3: Implement truthful status rendering**

Map labels and hints to existing prediction statuses and model values, add a compact visual step indicator, keep the whole card as one link, and remove the nested button.

- [ ] **Step 4: Handle moderation failure messages**

Add `handle_info({:moderation_failed, message}, socket)` and preserve the most recent prediction stream update. Display the server-provided message as an error flash without terminating the view.

- [ ] **Step 5: Run status tests and verify GREEN**

Expected: both modes display accurate advice and all PubSub outcomes remain renderable.

### Task 6: Full Verification And Delivery

**Files:**
- Verify all modified files

- [ ] **Step 1: Run focused and full tests**

```powershell
docker run --rm --network stickerbaker-test-net -v "${PWD}:/workspace" -v stickerbaker-test-deps:/workspace/deps -v stickerbaker-test-build:/workspace/_build -w /workspace -e MIX_ENV=test -e DB_HOST=stickerbaker-test-db -e DB_USERNAME=postgres -e DB_PASSWORD=postgres -e BUCKET_NAME=sticker-test-bucket stickerbaker-test-base sh -lc "mix deps.get && mix deps.compile && mix test"
node assets/js/launch_analytics_test.mjs
git diff --check
```

Expected: `132+ tests, 0 failures`, analytics exit 0, and no whitespace errors.

- [ ] **Step 2: Build production assets and release**

```powershell
docker build --target builder -t stickerbaker-workbench-check .
```

Expected: Elixir compilation, asset minification, digest, and release build all exit 0.

- [ ] **Step 3: Verify rendered behavior**

Use the Browser integration at desktop and `390x844`. Verify text/portrait switching, selected states, button enablement, upload preview/removal using a local non-sensitive fixture, no console errors, no horizontal overflow, and no real provider submission.

- [ ] **Step 4: Perform fidelity review**

Compare the accepted dual-mode specification and before screenshot with the latest screenshot. Inspect copy, mode hierarchy, palette, control typography, upload anatomy, cost visibility, status anatomy, and responsive behavior. Record intentional deviations.

- [ ] **Step 5: Commit, push, deploy, and check production**

Commit application and test changes, push `main`, manually dispatch `.github/workflows/main.yml` if the push trigger remains inactive, wait for success, then verify HTTP 200 and the new workbench DOM on `https://ai-sticker-maker.com/`.
