# Gallery-First Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the centered, text-heavy homepage Hero with the approved gallery-first split layout while preserving the existing LiveView generator behavior.

**Architecture:** Recompose the existing `HomeLive` template around the already assigned `@showcase_items` data, then add scoped responsive CSS for the intro, sticker collage, and attached workbench. No backend, route, form, upload, credit, or API code changes are required.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx, CSS, ExUnit, Floki

---

## File Structure

- `test/emoji_web/controllers/page_controller_test.exs`: asserts the new Hero hierarchy and protects existing generator behavior.
- `lib/sticker_web/live/home_live.html.heex`: renders the split Hero, curated sticker collage, CTA links, generator, and supporting trust row.
- `assets/css/app.css`: provides gallery-first desktop, tablet, and mobile layout and visual styling.

### Task 1: Protect The New Hero Structure

**Files:**
- Modify: `test/emoji_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Write the failing structure assertions**

Extend the homepage generator test with:

```elixir
assert [_] = Floki.find(document, ".saas-hero-intro")
assert [_] = Floki.find(document, ".saas-hero-copy")
assert [_] = Floki.find(document, ".saas-hero-gallery")
assert 4 = Floki.find(document, ".saas-hero-sticker") |> length()
assert 4 = Floki.find(document, ".saas-hero-sticker img") |> length()
assert [_] = Floki.find(document, "a[href=\"#generator\"].saas-hero-primary")
assert [_] = Floki.find(document, "a[href=\"#latest\"].saas-hero-secondary")
```

Also assert that the Hero copy contains `3 free generations` and that the existing generator selector remains unique.

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```powershell
mix test test/emoji_web/controllers/page_controller_test.exs
```

Expected: the new `.saas-hero-intro` assertion fails because the approved layout has not been rendered yet.

- [ ] **Step 3: Commit the failing test with the implementation when green**

The repository should not be left at a red test commit; stage this test together with Tasks 2 and 3 after verification.

### Task 2: Recompose The HomeLive Hero

**Files:**
- Modify: `lib/sticker_web/live/home_live.html.heex`

- [ ] **Step 1: Add the gallery-first intro before the generator**

Replace the centered eyebrow, H1, lead, and pre-generator trust row with this hierarchy:

```heex
<div class="saas-hero-intro">
  <div class="saas-hero-copy">
    <span class="saas-eyebrow">3 free generations - no sign-up required</span>
    <h1>AI Sticker Maker for Custom Stickers</h1>
    <p class="saas-lead">
      Turn a prompt or portrait into a clean, expressive sticker. Try it free and download
      sticker-ready PNG or WebP designs.
    </p>
    <div class="saas-hero-actions">
      <a href="#generator" class="saas-button saas-button-primary saas-hero-primary"
         data-analytics-event="hero_cta_click" data-analytics-context="gallery_first_hero">
        Create a sticker
      </a>
      <a href="#latest" class="saas-button saas-hero-secondary"
         data-analytics-event="hero_examples_click" data-analytics-context="gallery_first_hero">
        View examples
      </a>
    </div>
    <ul class="saas-hero-proof" aria-label="AI Sticker Maker benefits">
      <li>3 free guest generations</li>
      <li>PNG and WebP downloads</li>
      <li>Failed generations refund credits</li>
    </ul>
  </div>
  <div class="saas-hero-gallery" aria-label="Featured AI sticker examples">
    <div :for={{item, index} <- Enum.with_index(Enum.take(@showcase_items, 4))}
         class={"saas-hero-sticker saas-hero-sticker-#{index + 1}"}>
      <img src={item.image} alt={item.alt} />
      <span><%= item.tag %></span>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Keep the generator contract unchanged**

Keep `id="generator"`, both conditional forms, `id="prediction-form"`, `phx-change="validate"`, `phx-submit="save"`, upload rendering, prompt names, submit values, guest remaining-credit text, and all existing analytics attributes exactly as they are.

- [ ] **Step 3: Move supporting trust copy below the workbench shell**

Render the existing trust messages after `.saas-workbench-shell` in this order:

```heex
<div class="saas-workbench-trust" aria-label="AI Sticker Maker trust signals">
  <span class="saas-status-chip">Generated examples</span>
  <span class="saas-status-chip">Account-linked history and downloads</span>
  <span class="saas-status-chip">Support and billing help</span>
</div>
```

The three primary proof points remain in `.saas-hero-proof`, avoiding duplicate copy while preserving all homepage trust assertions.

### Task 3: Style The Gallery-First Layout

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Replace centered Hero spacing with the split intro**

Add scoped rules that implement:

```css
.saas-hero {
  padding: 54px 0 64px;
}

.saas-hero-main {
  max-width: 1180px;
  text-align: left;
}

.saas-hero-intro {
  display: grid;
  grid-template-columns: minmax(0, 0.9fr) minmax(460px, 1.1fr);
  gap: 64px;
  align-items: center;
}

.saas-hero-copy {
  max-width: 540px;
}

.saas-hero h1 {
  margin: 18px 0 16px;
  max-width: 620px;
  font-size: clamp(48px, 5.4vw, 70px);
  line-height: 1.02;
  letter-spacing: 0;
}

.saas-lead {
  max-width: 560px;
  margin: 0;
  font-size: 18px;
  line-height: 1.65;
}
```

- [ ] **Step 2: Style actions, proof list, and real-image collage**

Use stable dimensions and restrained transforms:

```css
.saas-hero-actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 24px; }
.saas-hero-proof { display: flex; flex-wrap: wrap; gap: 10px 18px; margin: 20px 0 0; padding: 0; list-style: none; }
.saas-hero-proof li { position: relative; padding-left: 18px; color: var(--saas-muted); font-size: 13px; font-weight: 800; }
.saas-hero-proof li::before { content: ""; position: absolute; left: 0; top: 0.45em; width: 8px; height: 8px; border-radius: 50%; background: var(--saas-brand); }
.saas-hero-gallery { position: relative; min-height: 420px; }
.saas-hero-sticker { position: absolute; width: 210px; aspect-ratio: 1; overflow: hidden; border: 8px solid #fff; border-radius: 24px; box-shadow: 0 22px 55px rgba(24, 32, 51, 0.16); }
.saas-hero-sticker img { width: 100%; height: 100%; object-fit: cover; }
.saas-hero-sticker span { position: absolute; left: 12px; bottom: 12px; padding: 5px 8px; border-radius: 999px; background: rgba(255,255,255,0.9); color: var(--saas-ink); font-size: 11px; font-weight: 900; }
```

Position the four classes in an overlapping two-row composition while keeping all cards within the gallery bounds. Give each class one existing soft palette background and a rotation between `-5deg` and `5deg`.

- [ ] **Step 3: Attach and simplify the workbench**

Set `.saas-generator-workbench` to `margin-top: 34px`, keep the shell at full width, and render `.saas-workbench-trust` after it with lower-emphasis neutral chip styling.

- [ ] **Step 4: Add tablet and mobile containment rules**

At `max-width: 920px`, switch `.saas-hero-intro` to one column, cap copy width at `700px`, and turn `.saas-hero-gallery` into a two-column grid with static sticker positioning. At `max-width: 620px`, use full-width Hero actions, reduce the H1 to `42px`, reduce gallery and sticker border sizes, hide the fourth collage item if vertical space becomes excessive, and preserve the existing full-width generator button behavior.

### Task 4: Verify Behavior And Presentation

**Files:**
- Test: `test/emoji_web/controllers/page_controller_test.exs`
- Test: `test/emoji_web/live/home_auth_intent_test.exs`

- [ ] **Step 1: Run focused Elixir tests**

```powershell
mix test test/emoji_web/controllers/page_controller_test.exs test/emoji_web/live/home_auth_intent_test.exs
```

Expected: all tests pass. If local Mix is unavailable, run the equivalent command in the project Docker environment and report the limitation.

- [ ] **Step 2: Run analytics and whitespace checks**

```powershell
node assets/js/launch_analytics_test.mjs
git diff --check
```

Expected: analytics tests pass and `git diff --check` prints no errors.

- [ ] **Step 3: Verify desktop and mobile screenshots**

Start the local app, then inspect at `1440x1000` and `390x844`. Confirm all four desktop collage images load, mobile has no horizontal overflow, CTA text fits, the prompt does not overlap the upload control, and the first viewport shows both product proof and the generator entry.

- [ ] **Step 4: Commit the implementation**

```powershell
git add -- test/emoji_web/controllers/page_controller_test.exs lib/sticker_web/live/home_live.html.heex assets/css/app.css
git commit -m "Redesign homepage with gallery-first hero"
```
