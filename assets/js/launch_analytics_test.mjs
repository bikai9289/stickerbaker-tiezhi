import assert from "node:assert/strict";
import { launchEventPayload, safeAttribution, safeTrack } from "./launch_analytics.mjs";

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
