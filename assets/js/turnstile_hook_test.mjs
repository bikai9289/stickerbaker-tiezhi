import assert from "node:assert/strict";
import { createTurnstileHook } from "./turnstile_hook.mjs";
let timers = new Map(), timerId = 0;
globalThis.window = { setTimeout: (fn, ms) => { timers.set(++timerId, {fn, ms}); return timerId; }, clearTimeout: id => timers.delete(id) };
function fixture(api) {
  const pushed = [], calls = [], handlers = new Map(), listeners = new Map();
  const status = {textContent: ""}, retry = {hidden: true, addEventListener: (e, f) => listeners.set(e, f), removeEventListener: e => listeners.delete(e)};
  const container = {};
  let options;
  const widget = {render: (el, opts) => {calls.push("render"); options = opts; return 0;}, reset: () => calls.push("reset"), remove: () => calls.push("remove")};
  const hook = createTurnstileHook(() => api === false ? undefined : widget);
  const ctx = {el: {dataset: {siteKey: "public-key", action: "sticker_generation"}, querySelector: s => ({"[data-turnstile-container]": container, "[data-turnstile-status]": status, "[data-turnstile-retry]": retry})[s]}, pushEvent: (e,p) => pushed.push([e,p]), handleEvent: (e,f) => handlers.set(e,f)};
  Object.assign(ctx, hook);
  return {ctx, pushed, calls, handlers, listeners, status, retry, options: () => options};
}
const f = fixture(); f.ctx.mounted(); f.ctx.mounted();
assert.deepEqual(f.calls, ["render"], "mount must not duplicate a widget, even when id is zero");
f.options().callback("valid-token");
assert.deepEqual(f.pushed.at(-1), ["turnstile-token", {token: "valid-token"}]);
assert.match(f.status.textContent, /complete/i);
for (const name of ["expired-callback", "error-callback", "timeout-callback"]) {
  f.options()[name]("error-code");
  assert.equal(f.retry.hidden, false);
  assert.deepEqual(f.pushed.at(-1), ["turnstile-token", {token: ""}]);
  f.listeners.get("click")({preventDefault(){}});
  assert.equal(f.calls.at(-1), "reset");
}
f.handlers.get("turnstile-reset")();
assert.equal(f.calls.at(-1), "reset");
f.ctx.destroyed(); const count = f.pushed.length; f.options().callback("late-token");
assert.equal(f.pushed.length, count, "destroyed widget must not authorize a request");
assert.equal(f.listeners.size, 0);
assert.equal(timers.size, 0);
const missing = fixture(false); missing.ctx.mounted();
for (let i=0; i<160 && timers.size; i++) {
  const entries = [...timers]; timers.clear(); entries.forEach(([,t]) => t.fn());
}
assert.equal(missing.retry.hidden, false, "API timeout must expose retry");
assert.match(missing.status.textContent, /load/i);
assert.equal(timers.size, 0, "API timeout must stop polling");
missing.ctx.destroyed();
console.log("turnstile lifecycle, expiry, error, timeout and retry tests passed");
