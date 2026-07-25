# Dual-Mode Sticker Workbench Redesign

## Goal

Replace the homepage's visually combined upload and prompt controls with two real generator modes: text-to-sticker and portrait-to-sticker. Make every credit charge explicit, require confirmation before portrait generation, and show truthful generation states without changing the three-generation guest trial, account credits, provider integrations, or refund policy.

## Scope

This change covers the homepage generator, its LiveView events, prediction status cards, input validation, and focused regression tests. It does not add a general-purpose image-to-sticker model: the existing upload provider is face-specific, so the interface must accurately call this mode `Portrait to sticker`.

## Chosen Interaction Model

Use one workbench with a two-option segmented control:

- `Text to sticker` is selected by default.
- `Portrait to sticker` shows the upload workflow.
- `Search ideas` remains a secondary link outside the segmented control.
- Only the selected mode's primary controls are visible.
- Switching modes preserves the current prompt and any selected upload until the user removes it or submits it.

The workbench remains in the Hero and keeps the existing white surface, orange brand accent, compact radius, restrained shadow, and current typography. No new illustrations, gradients, decorative cards, or above-the-fold claims are introduced.

## Text-To-Sticker Mode

### Default behavior

- The prompt is a single idea even when it contains line breaks.
- The prompt is required and limited to 1,000 Unicode characters.
- One submission creates one prediction and spends one credit.
- The footer states `1 sticker - Uses 1 credit` before submission.
- The primary button label is `Generate sticker`.

### Explicit batch behavior

- `Batch mode` is an opt-in checkbox.
- When enabled, each non-empty line is one prompt.
- A batch contains at most five prompts.
- Each prompt is limited to 1,000 characters.
- Extra lines are rejected with a visible error instead of silently discarded.
- The footer displays the parsed sticker count and exact credit cost.
- Existing guest and account insufficient-credit messages remain available.

## Portrait-To-Sticker Mode

- Accepted formats remain JPG, JPEG, and PNG, one file, no more than 8 MB.
- The empty state says `Drop a clear portrait here` and exposes `Choose image`.
- Helper copy states the accepted formats, size limit, and one-clear-face expectation.
- Selecting a file shows a square preview, file name, upload progress, `Replace` action, and `Remove` action.
- Selecting or uploading a file never spends a credit or starts model generation by itself.
- The optional prompt is labeled `Optional instructions` and falls back to the existing default face-sticker prompt when empty.
- The primary button is disabled until a valid image is selected and reads `Generate portrait sticker`.
- Submission spends exactly one credit after file validation and safety review have succeeded.

## Generation Feedback

Status copy must map to real system states. Do not show fabricated percentage completion for model generation.

### Text predictions

- `starting`: `Checking your prompt`
- `moderation_succeeded`: `Prompt approved - Waiting for the image service`
- `processing`: `AI is creating your sticker`
- `succeeded`: render the generated image and link to details/download actions
- `failed`: `Generation did not complete`; show `Credit returned` when applicable

### Portrait predictions

- Browser upload: use the real LiveView upload percentage
- Pre-generation validation: `Checking your portrait`
- `starting`: `Preparing your portrait sticker`
- `processing`: `AI is transforming your portrait`
- `failed`: `Try another portrait or adjust the instructions`

The results heading remains directly below the workbench. Result cards use a compact step indicator, preserve the prompt, and provide a clear details/retry path. The existing completed, loading, and failed PubSub updates remain the source of truth.

## Business Logic And Error Handling

- Text credit spending and prediction creation must be atomic. A partial batch creation must not leave starting predictions or refund credits twice.
- Invalid, empty, overlong, and oversized batch input must be rejected before credits are spent.
- `moderation_failed` messages must be handled by HomeLive without disconnecting the view.
- Failed provider startup, moderation, generation, or storage continues to call the existing idempotent refund path.
- The UI must distinguish text failure advice from portrait failure advice.
- Upload validation errors must stay inside the workbench and must not navigate to `/` or erase the prompt.
- Authenticated credit display and guest remaining-credit display update using the existing `GenerationCredits` results.

## Request And Response Compatibility

- No public HTTP route, API parameter, webhook request, response body, error code, database schema, or provider payload changes.
- Existing `prediction-form`, analytics event names, guest identity assignment, registration links, and prediction PubSub message shapes remain compatible.
- New LiveView-only events are `switch-generator-mode`, `toggle-batch-mode`, and `cancel-upload`.
- The submit event remains `save` and accepts the existing `prompt` field plus a `mode` value controlled by the server-rendered form.

## Accessibility And Responsive Behavior

- The segmented control uses buttons with `aria-pressed`; it is not represented as navigation links.
- Labels remain programmatically associated with the prompt and upload controls.
- Disabled buttons expose a visible reason nearby.
- Upload remove/replace actions have explicit accessible names.
- Focus is not forced back to the text field while portrait mode is active.
- Desktop keeps the workbench in one compact surface.
- At 620 px and below, controls stack, action buttons become full width, and the workbench introduces no horizontal overflow.

## Allowed Visible Copy

- `Text to sticker`
- `Portrait to sticker`
- `Search ideas`
- `Describe your sticker`
- `Optional instructions`
- `Batch mode`
- `Drop a clear portrait here`
- `Choose image`
- `JPG or PNG - Max 8 MB - One clear face`
- `1 sticker - Uses 1 credit`
- `Generate sticker`
- `Generate portrait sticker`
- Generation status and error copy defined in this document

## Testing

- Controller/Floki tests protect one real segmented control, one selected mode, one form, copy, analytics hooks, and lack of duplicate controls.
- LiveView tests exercise mode switching, single-prompt newline handling, explicit batch parsing, overlong/oversized input, upload selection without generation, upload cancellation, and `moderation_failed` handling.
- Credit and prediction tests protect atomic batch creation and failed-generation refunds.
- Browser QA verifies desktop and mobile rendering, selected states, form enablement, no horizontal overflow, no console errors, and no production credit consumption.

## Out Of Scope

- A general object, product, animal, or logo image-to-sticker provider.
- Multiple candidates from one provider call.
- New database columns, payment rules, pricing, or guest trial limits.
- Full sticker editor controls such as border width, background color, or sticker packs.
- Changes to the Gallery-first Hero above the workbench.
