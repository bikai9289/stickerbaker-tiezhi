const launchSources = [
  ["reddit.com", "reddit"],
  ["producthunt.com", "producthunt"],
  ["v2ex.com", "v2ex"],
  ["google.", "organic"],
];

export const launchFunnelEvents = {
  generator_view: {
    keyEvent: true,
    trigger: "Home generator area is mounted",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  text_generation_attempt: {
    keyEvent: true,
    trigger: "Visitor submits the text-to-sticker form",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  face_upload_attempt: {
    keyEvent: true,
    trigger: "Visitor chooses the face upload entry point",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  registration_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a registration CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  registration_confirm_attempt: {
    keyEvent: false,
    trigger: "Visitor submits the registration form",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context"],
  },
  registration_confirmed: {
    keyEvent: true,
    trigger: "Visitor returns after confirming email",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  login_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a login CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  pricing_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a pricing CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  buy_credit_cta_click: {
    keyEvent: false,
    trigger: "Visitor clicks a buy-credit CTA",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "plan"],
  },
  checkout_start: {
    keyEvent: true,
    trigger: "Visitor submits a checkout form",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "plan"],
  },
  purchase_complete: {
    keyEvent: true,
    trigger: "Visitor returns from checkout with a success state",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context", "auth_state"],
  },
  search_submit: {
    keyEvent: false,
    trigger: "Visitor submits sticker search",
    requiredParams: ["page_path", "source"],
    optionalParams: ["utm_source", "utm_medium", "utm_campaign", "referrer_host", "event_context"],
  },
};

const allowedDetailKeys = new Set(["authState", "context", "plan"]);

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
  if (!eventName) return null;

  const safeDetail = Object.fromEntries(
    Object.entries(detail).filter(([key, value]) => allowedDetailKeys.has(key) && value),
  );

  return {
    ...safeAttribution(environment.location, environment.document?.referrer || ""),
    event_context: safeDetail.context,
    auth_state: safeDetail.authState,
    plan: safeDetail.plan,
  };
}

export function safeTrack(eventName, detail = {}, environment = window) {
  const payload = launchEventPayload(eventName, detail, environment);
  if (!payload) return;

  try {
    if (typeof environment.gtag === "function") {
      environment.gtag("event", eventName, payload);
    }
  } catch (_error) {
    // Analytics must never block product actions.
  }
}

export function trackReturnState(environment = window) {
  const params = new URLSearchParams(environment.location.search || "");
  const storage = environment.sessionStorage;

  const trackOnce = (key, eventName, detail) => {
    if (storage?.getItem(key)) return;
    storage?.setItem(key, "tracked");
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
}
