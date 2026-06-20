const launchSources = [
  ["reddit.com", "reddit"],
  ["producthunt.com", "producthunt"],
  ["v2ex.com", "v2ex"],
  ["google.", "organic"],
];

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

  return {
    ...safeAttribution(environment.location, environment.document?.referrer || ""),
    event_context: detail.context || undefined,
    auth_state: detail.authState || undefined,
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
