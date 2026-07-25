import assert from "node:assert/strict";
import {
  launchEventPayload,
  launchFunnelEvents,
  safeAttribution,
  safeTrack,
  trackReturnState,
} from "./launch_analytics.mjs";

const reddit = safeAttribution(
  { pathname: "/", search: "?utm_source=reddit&utm_medium=social&utm_campaign=launch" },
  "https://www.google.com/search?q=ai+sticker+maker",
);

assert.equal(reddit.source, "reddit");
assert.equal(reddit.utm_medium, "social");
assert.equal(reddit.utm_campaign, "launch");

const v2ex = safeAttribution(
  { pathname: "/sticker-maker-online", search: "" },
  "https://www.v2ex.com/t/123",
);

assert.equal(v2ex.source, "v2ex");
assert.equal(v2ex.referrer_host, "www.v2ex.com");

const unknown = safeAttribution({ pathname: "/search", search: "" }, "");
assert.equal(unknown.source, "unknown");

const payload = launchEventPayload(
  "text_generation_attempt",
  { context: "hero_generator", authState: "anonymous", prompt: "private prompt" },
  { location: { pathname: "/", search: "" }, document: { referrer: "" } },
);

assert.deepEqual(Object.keys(payload).sort(), [
  "auth_state",
  "event_context",
  "page_path",
  "referrer_host",
  "source",
  "utm_campaign",
  "utm_medium",
  "utm_source",
]);
assert.equal(payload.prompt, undefined);

const promptPayload = launchEventPayload(
  "prompt_entered",
  {
    context: "hero_generator",
    prompt: "private prompt",
    promptLengthBucket: "41-120",
    promptLineCount: 2,
    unsafeUserId: "user-123",
  },
  { location: { pathname: "/", search: "" }, document: { referrer: "" } },
);

assert.equal(promptPayload.prompt, undefined);
assert.equal(promptPayload.unsafeUserId, undefined);
assert.equal(promptPayload.prompt_length_bucket, "41-120");
assert.equal(promptPayload.prompt_line_count, 2);

const downloadPayload = launchEventPayload(
  "download_click",
  { context: "history_bulk", downloadType: "batch_zip", format: "webp" },
  { location: { pathname: "/stickers", search: "" }, document: { referrer: "" } },
);

assert.equal(downloadPayload.download_type, "batch_zip");
assert.equal(downloadPayload.format, "webp");

const guestPayload = launchEventPayload(
  "guest_generation_started",
  {
    context: "hero_generator",
    authState: "guest",
    generationMode: "text",
    promptCount: 2,
    remainingTrialCredits: 1,
    prompt: "private prompt",
  },
  { location: { pathname: "/", search: "" }, document: { referrer: "" } },
);

assert.equal(guestPayload.auth_state, "guest");
assert.equal(guestPayload.generation_mode, "text");
assert.equal(guestPayload.prompt_count, 2);
assert.equal(guestPayload.remaining_trial_credits, 1);
assert.equal(guestPayload.prompt, undefined);

assert.equal(launchEventPayload("unknown_event", {}, {
  location: { pathname: "/", search: "" },
  document: { referrer: "" },
}), null);

assert.deepEqual(
  safeTrack(
    "unknown_event",
    {},
    {
      location: { pathname: "/", search: "" },
      document: { referrer: "" },
    },
  ),
  { ok: false, reason: "unknown_event" },
);

assert.deepEqual(
  safeTrack(
    "pricing_view",
    { context: "pricing_page" },
    {
      location: { pathname: "/pricing", search: "" },
      document: { referrer: "" },
    },
  ),
  { ok: false, reason: "gtag_unavailable" },
);

assert.doesNotThrow(() =>
  safeTrack(
    "pricing_cta_click",
    { context: "pricing" },
    {
      location: { pathname: "/pricing", search: "" },
      document: { referrer: "" },
      gtag() {
        throw new Error("blocked");
      },
    },
  ),
);

const tracked = [];
const storage = new Map();
const returnEnvironment = {
  location: { pathname: "/", search: "?prompt=hello" },
  document: { referrer: "" },
  sessionStorage: {
    getItem(key) {
      return storage.get(key);
    },
    setItem(key, value) {
      storage.set(key, value);
    },
  },
  gtag(_command, eventName, eventPayload) {
    tracked.push([eventName, eventPayload]);
  },
};

trackReturnState(returnEnvironment);
trackReturnState(returnEnvironment);

assert.equal(tracked.length, 1);
assert.equal(tracked[0][0], "prompt_restored");
assert.equal(tracked[0][1].restored_prompt, true);

const brokenStorageEnvironment = {
  location: { pathname: "/", search: "?checkout=success" },
  document: { referrer: "" },
  sessionStorage: {
    getItem() {
      throw new Error("blocked");
    },
    setItem() {
      throw new Error("blocked");
    },
  },
  gtag() {},
};

assert.doesNotThrow(() => trackReturnState(brokenStorageEnvironment));

const blockedStorageGetterEnvironment = {
  location: { pathname: "/", search: "?registration=confirmed" },
  document: { referrer: "" },
  get sessionStorage() {
    throw new Error("blocked");
  },
  gtag() {},
};

assert.doesNotThrow(() => trackReturnState(blockedStorageGetterEnvironment));

const requiredFunnelEvents = [
  "generator_view",
  "prompt_entered",
  "text_generation_attempt",
  "auth_required",
  "prompt_restored",
  "face_upload_attempt",
  "guest_generation_started",
  "guest_trial_exhausted",
  "guest_to_signup_click",
  "guest_to_login_click",
  "registration_cta_click",
  "registration_confirm_attempt",
  "registration_confirmed",
  "login_cta_click",
  "login_confirm_attempt",
  "generation_started",
  "generation_completed",
  "download_click",
  "pricing_view",
  "pricing_cta_click",
  "buy_credit_cta_click",
  "checkout_start",
  "purchase_complete",
  "search_submit",
];

for (const eventName of requiredFunnelEvents) {
  assert.ok(launchFunnelEvents[eventName], `${eventName} is defined`);
  assert.ok(launchFunnelEvents[eventName].requiredParams.includes("page_path"));
  assert.ok(launchFunnelEvents[eventName].requiredParams.includes("source"));
}
