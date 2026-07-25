const launchSources = [
  ["reddit.com", "reddit"],
  ["producthunt.com", "producthunt"],
  ["v2ex.com", "v2ex"],
  ["google.", "organic"],
];

const baseOptionalParams = [
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "referrer_host",
  "event_context",
];

export const launchFunnelEvents = {
  generator_view: {
    keyEvent: true,
    trigger: "Home generator area is mounted",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  prompt_entered: {
    keyEvent: false,
    trigger: "Visitor enters a non-empty generator prompt",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "prompt_length_bucket", "prompt_line_count"],
  },
  text_generation_attempt: {
    keyEvent: true,
    trigger: "Visitor submits the text-to-sticker form",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  auth_required: {
    keyEvent: true,
    trigger: "Anonymous visitor submits a generator action that requires an account",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "flow"],
  },
  prompt_restored: {
    keyEvent: false,
    trigger: "Visitor returns to the generator with a restored prompt",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "restored_prompt"],
  },
  face_upload_attempt: {
    keyEvent: true,
    trigger: "Visitor chooses the face upload entry point",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  registration_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a registration CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  registration_confirm_attempt: {
    keyEvent: false,
    trigger: "Visitor submits the registration form",
    requiredParams: ["page_path", "source"],
    optionalParams: baseOptionalParams,
  },
  registration_confirmed: {
    keyEvent: true,
    trigger: "Visitor returns after confirming email",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  login_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a login CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  login_confirm_attempt: {
    keyEvent: false,
    trigger: "Visitor submits the login form",
    requiredParams: ["page_path", "source"],
    optionalParams: baseOptionalParams,
  },
  guest_generation_started: {
    keyEvent: true,
    trigger: "Anonymous visitor starts a free guest generation",
    requiredParams: ["page_path", "source"],
    optionalParams: [
      ...baseOptionalParams,
      "auth_state",
      "generation_mode",
      "prompt_count",
      "remaining_trial_credits",
    ],
  },
  guest_trial_exhausted: {
    keyEvent: false,
    trigger: "Anonymous visitor reaches zero remaining guest trial generations",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "remaining_trial_credits"],
  },
  guest_to_signup_click: {
    keyEvent: false,
    trigger: "Anonymous visitor clicks a signup CTA from the guest trial flow",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  guest_to_login_click: {
    keyEvent: false,
    trigger: "Anonymous visitor clicks a login CTA from the guest trial flow",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  generation_started: {
    keyEvent: true,
    trigger: "Frontend observes generation work starting",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "flow"],
  },
  generation_completed: {
    keyEvent: true,
    trigger: "Frontend observes a completed sticker result",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state", "flow"],
  },
  download_click: {
    keyEvent: true,
    trigger: "Visitor clicks a sticker download control",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "download_type", "format"],
  },
  pricing_view: {
    keyEvent: false,
    trigger: "Pricing page is viewed",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  pricing_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a pricing CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  buy_credit_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a buy-credit CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "plan"],
  },
  checkout_start: {
    keyEvent: true,
    trigger: "Visitor submits a checkout form",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "plan"],
  },
  purchase_complete: {
    keyEvent: true,
    trigger: "Visitor returns from checkout with a success state",
    requiredParams: ["page_path", "source"],
    optionalParams: [...baseOptionalParams, "auth_state"],
  },
  search_submit: {
    keyEvent: false,
    trigger: "Visitor submits sticker search",
    requiredParams: ["page_path", "source"],
    optionalParams: baseOptionalParams,
  },
};

const allowedDetailKeys = new Set([
  "authState",
  "context",
  "downloadType",
  "flow",
  "format",
  "generationMode",
  "plan",
  "promptLengthBucket",
  "promptLineCount",
  "promptCount",
  "remainingTrialCredits",
  "restoredPrompt",
]);

const detailPayloadKeys = {
  authState: "auth_state",
  context: "event_context",
  downloadType: "download_type",
  flow: "flow",
  format: "format",
  generationMode: "generation_mode",
  plan: "plan",
  promptLengthBucket: "prompt_length_bucket",
  promptLineCount: "prompt_line_count",
  promptCount: "prompt_count",
  remainingTrialCredits: "remaining_trial_credits",
  restoredPrompt: "restored_prompt",
};

function present(value) {
  return value !== undefined && value !== null && value !== "";
}

function safeLocation(environment) {
  return environment?.location || { pathname: "/", search: "" };
}

function safeReferrer(environment) {
  return environment?.document?.referrer || "";
}

export function safeAttribution(location, referrer = "") {
  const params = new URLSearchParams(location.search || "");
  const referrerHost = (() => {
    try {
      return referrer ? new URL(referrer).hostname.toLowerCase() : "";
    } catch (_error) {
      return "";
    }
  })();
  const matched = launchSources.find(([host]) => referrerHost.includes(host));

  return {
    page_path: location.pathname || "/",
    utm_source: params.get("utm_source") || undefined,
    utm_medium: params.get("utm_medium") || undefined,
    utm_campaign: params.get("utm_campaign") || undefined,
    source:
      params.get("utm_source") ||
      (matched && matched[1]) ||
      (referrerHost ? "referral" : "unknown"),
    referrer_host: referrerHost || undefined,
  };
}

export function launchEventPayload(eventName, detail = {}, environment = window) {
  if (!eventName || !launchFunnelEvents[eventName]) return null;

  const safeDetail = Object.entries(detail || {}).reduce((payload, [key, value]) => {
    if (allowedDetailKeys.has(key) && present(value)) {
      payload[detailPayloadKeys[key]] = value;
    }

    return payload;
  }, {});

  return {
    ...safeAttribution(safeLocation(environment), safeReferrer(environment)),
    ...safeDetail,
  };
}

export function safeTrack(eventName, detail = {}, environment = window) {
  const payload = launchEventPayload(eventName, detail, environment);
  if (!payload) return { ok: false, reason: "unknown_event" };

  try {
    if (typeof environment.gtag === "function") {
      environment.gtag("event", eventName, payload);
      return { ok: true };
    }

    return { ok: false, reason: "gtag_unavailable" };
  } catch (_error) {
    // Analytics must never block product actions.
    return { ok: false, reason: "gtag_error" };
  }
}

export function trackReturnState(environment = window) {
  const params = new URLSearchParams(safeLocation(environment).search || "");
  let storage;

  try {
    storage = environment?.sessionStorage;
  } catch (_error) {
    storage = undefined;
  }

  const trackOnce = (key, eventName, detail) => {
    try {
      if (storage?.getItem(key)) return;
      storage?.setItem(key, "tracked");
    } catch (_error) {
      // Storage failures must never block analytics or product actions.
    }

    safeTrack(eventName, detail, environment);
  };

  if (params.get("checkout") === "success") {
    trackOnce(
      "launch_return_state:checkout_success",
      "purchase_complete",
      { context: "checkout_return", authState: "known" },
    );
  }

  if (params.get("registration") === "confirmed") {
    trackOnce(
      "launch_return_state:registration_confirmed",
      "registration_confirmed",
      { context: "email_confirmation", authState: "known" },
    );
  }

  if (params.get("prompt")) {
    trackOnce(
      `launch_return_state:prompt_restored:${params.get("prompt").length}`,
      "prompt_restored",
      { context: "prompt_return", authState: "known", restoredPrompt: true },
    );
  }
}
