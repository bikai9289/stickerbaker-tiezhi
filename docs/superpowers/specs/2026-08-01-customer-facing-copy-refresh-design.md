# Customer-Facing Copy Refresh Design

## Goal

Replace internal, contradictory, and vague website copy with customer-facing language that accurately explains free usage, credits, pricing, generation failures, downloads, and support.

## Scope

- Update homepage hero support copy, feature summaries, pricing summary, FAQ, and trust labels.
- Update the global footer description.
- Update the pricing page introduction, plan descriptions, purchase explanation, and supporting policy links.
- Preserve prices, credit quantities, routes, analytics attributes, and application behavior.

## Copy Rules

- State only behavior verified by the application and existing policy pages.
- A guest can generate up to three stickers without creating an account.
- Each text or portrait generation costs one credit.
- A failed generation automatically returns its credit.
- Starter and Creator are one-time credit purchases, not subscriptions.
- Do not claim commercial-use rights, guaranteed transparency, permanent storage, or specific output resolution.
- Do not expose implementation, SEO, roadmap, or deployment language.
- Keep the existing professional, direct English voice and action-oriented calls to action.

## Test Strategy

- Add controller-level copy contract assertions for the homepage and pricing page.
- Assert required customer-facing rules and the absence of known internal phrases.
- Run focused controller tests, the full test suite, and browser checks at desktop and mobile sizes.
- After deployment, repeat the browser and HTTP checks against the production domain.

## Deployment

Commit the tested change, push `main`, allow the existing GitHub Actions server deployment workflow to update the Tencent Cloud host, then verify the public site.
