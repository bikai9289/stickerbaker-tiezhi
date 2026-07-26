import assert from "node:assert/strict";
import { createTurnstileHook } from "./turnstile_hook.mjs";

globalThis.window = { setTimeout, clearTimeout };

const calls = [];
const pushed = [];
const handlers = new Map();
let callbacks;

const turnstile = {
  render(container, options) {
    calls.push(["render", container, options.sitekey, options.action]);
    callbacks = options;
    return "widget-1";
  },
  reset(widgetId) {
    calls.push(["reset", widgetId]);
  },
  remove(widgetId) {
    calls.push(["remove", widgetId]);
  },
};

const container = {};
const context = {
  el: {
    dataset: { siteKey: "site-key", action: "sticker_generation" },
    querySelector(selector) {
      assert.equal(selector, "[data-turnstile-container]");
      return container;
    },
  },
  pushEvent(event, payload) {
    pushed.push([event, payload]);
  },
  handleEvent(event, callback) {
    handlers.set(event, callback);
  },
};

const hook = createTurnstileHook(() => turnstile);
hook.mounted.call(context);
hook.mounted.call(context);

assert.deepEqual(calls, [["render", container, "site-key", "sticker_generation"]]);

callbacks.callback("fresh-token");
assert.deepEqual(pushed.at(-1), ["turnstile-token", { token: "fresh-token" }]);

callbacks["expired-callback"]();
assert.deepEqual(pushed.at(-1), ["turnstile-token", { token: "" }]);

handlers.get("turnstile-reset")();
assert.deepEqual(calls.at(-1), ["reset", "widget-1"]);

hook.destroyed.call(context);
assert.deepEqual(calls.at(-1), ["remove", "widget-1"]);

console.log("turnstile hook tests passed");
