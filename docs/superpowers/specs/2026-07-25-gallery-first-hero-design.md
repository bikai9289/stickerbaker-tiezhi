# Gallery-First Hero Redesign

## Goal

Redesign the homepage Hero so visitors immediately see the quality and range of generated stickers while keeping the existing generator available in the first viewport. The redesign must improve visual hierarchy without changing generation, guest trial, authentication, credit, or upload behavior.

## Chosen Direction

Use the approved gallery-first split layout:

- Left: concise product positioning, the existing SEO-focused H1, two clear navigation actions, and three short trust statements.
- Right: a lively collage built from the existing curated showcase images.
- Below the split: the existing text/reference generator workbench, visually attached to the Hero but still an independent interactive surface.

The page keeps the current orange brand accent, white canvas, soft blue and warm-neutral support colors, and square sticker imagery. It avoids decorative gradients, oversized empty space, and a long row of competing status chips above the generator.

## Information Hierarchy

The first viewport should communicate, in order:

1. This is an AI sticker maker.
2. The product can make polished portrait, character, and animal stickers.
3. A visitor can try three generations without signing in.
4. The visitor can start from text or a reference face.
5. Downloads and failed-generation credit handling are supported.

## Hero Components

### Intro Copy

- Eyebrow: `3 free generations - no sign-up required`.
- H1 remains `AI Sticker Maker for Custom Stickers` to preserve page intent and existing SEO targeting.
- Supporting copy is shortened to two sentences at most.
- Primary action: `Create a sticker`, linking to `#generator`.
- Secondary action: `View examples`, linking to `#latest`.
- Trust statements: `3 free guest generations`, `PNG and WebP downloads`, and `Failed generations refund credits`.

### Sticker Collage

- Reuse the first four entries from `@showcase_items`; do not add new image dependencies or remote assets.
- Render images with their existing descriptive alt text.
- Use offset square compositions with stable aspect ratios, restrained rotation, white sticker-like borders, and varied soft background colors.
- Keep the composition visually open rather than placing all images inside a decorative card.
- On small screens, switch to a compact two-column grid and remove rotation that risks clipping.

### Generator Workbench

- Preserve `#generator`, both authenticated and guest forms, form IDs, LiveView events, upload component, prompt field, credit state, and analytics attributes.
- Keep the current mode tabs and square-output note.
- Move supporting trust chips below the workbench and reduce their visual prominence.
- Keep one visible Generate action per rendered authentication state.

## Responsive Behavior

- Desktop (`> 920px`): two-column intro with copy on the left and collage on the right; generator spans the full Hero width below.
- Tablet (`621px-920px`): stacked intro; collage remains a stable two-by-two composition; generator uses its existing single-column input layout.
- Mobile (`<= 620px`): compact typography, full-width actions, two-column collage, horizontal-scroll mode tabs, and a full-width Generate button.
- No viewport should have overlapping text, clipped stickers, or layout movement when focus and hover states appear.

## Accessibility

- Preserve one H1 on the page.
- Keep existing image alt text from showcase data.
- Use normal anchor elements for the two Hero actions.
- Maintain visible focus states and adequate contrast for copy, links, and buttons.
- Treat purely decorative collage labels and shadows as non-semantic styling.

## Analytics And Behavior Compatibility

- Add Hero CTA analytics attributes without changing existing generator event names.
- Preserve prompt restoration, guest trial remaining state, exhausted-trial registration link, authenticated credit display, and upload authentication gate.
- Do not change routes, server APIs, request parameters, response structures, error messages, credit rules, or database state.

## Testing

- Update homepage structure assertions for the gallery-first layout and verify the collage renders curated images.
- Preserve assertions for one generator, one active Generate action, upload authentication behavior, trust copy, analytics hooks, and guest trial states.
- Run the focused controller and LiveView tests, asset analytics tests, formatting checks, and a production build where the environment supports them.
- Verify screenshots at desktop and mobile widths, checking first-viewport hierarchy, image loading, focus layout, and absence of overlap.

## Out Of Scope

- Changes to generation providers or prompt processing.
- New guest trial or credit rules.
- New showcase images or image generation.
- Navigation, pricing, account, or lower-page redesigns.
- SEO title, canonical URL, structured data, or sitemap changes.
