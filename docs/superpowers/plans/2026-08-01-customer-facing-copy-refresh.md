# Customer-Facing Copy Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace internal and contradictory public website copy with accurate customer-facing explanations, then test and deploy it.

**Architecture:** Keep all existing Phoenix routes, templates, analytics hooks, prices, and business behavior unchanged. Add response-level copy contract assertions to the existing page controller test, then update the three public HEEx templates until those contracts pass.

**Tech Stack:** Elixir, Phoenix LiveView, HEEx, ExUnit, Floki, GitHub Actions, Docker Compose production deployment

---

### Task 1: Add Public Copy Contracts

**Files:**
- Modify: `test/emoji_web/controllers/page_controller_test.exs`

- [ ] Add a test that requests `/` and `/pricing`, asserts the verified free-credit and one-time-purchase rules, and rejects the internal phrases `Keep the tool in the first screen`, `once your site has enough saved results`, `search traffic`, `future credit-based plans`, and `public HTTPS webhooks`.
- [ ] Run `mix test test/emoji_web/controllers/page_controller_test.exs` and confirm the new test fails because the current templates still contain internal copy and omit the one-time-purchase explanation.

### Task 2: Refresh Customer-Facing Templates

**Files:**
- Modify: `lib/sticker_web/live/home_live.html.heex`
- Modify: `lib/sticker_web/components/layouts/app.html.heex`
- Modify: `lib/sticker_web/controllers/page_html/pricing.html.heex`

- [ ] Replace design, roadmap, SEO, and webhook language with benefits and actionable guidance.
- [ ] Make the free rule consistent: guests receive up to three generations without an account; every text or portrait generation uses one credit; failed generations automatically return the credit.
- [ ] Describe Starter and Creator as one-time credit purchases, preserve `$4.99 / 50` and `$9.99 / 150`, and direct uncertain refund questions to the existing policy pages.
- [ ] Replace vague trust labels with `No subscription`, `Failed generations return credits`, and `Payment and refund details` where appropriate.
- [ ] Run the focused controller test and confirm it passes.

### Task 3: Regression And Render Verification

**Files:**
- No production file changes expected.

- [ ] Run `mix format --check-formatted`.
- [ ] Run `mix test` and require zero failures.
- [ ] Start the Phoenix server using the existing development setup.
- [ ] Verify `/` and `/pricing` at 1440x900 and 390x844: page identity, meaningful content, no framework overlay, no relevant console errors, and pricing navigation.
- [ ] Search rendered content and source for all rejected internal phrases.

### Task 4: Commit, Push, And Deploy

**Files:**
- Commit only the copy refresh, test, design, and plan files.

- [ ] Commit the implementation with a focused message.
- [ ] Push `main` to `origin` to trigger `.github/workflows/deploy.yml`.
- [ ] Monitor the workflow through completion.
- [ ] Verify `https://ai-sticker-maker.com/` and `/pricing` contain the new copy, reject the old internal phrases, return HTTP 200, and render correctly on desktop and mobile.
