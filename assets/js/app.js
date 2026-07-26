// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import FileSaver from "../vendor/file-saver";
import Hammer from "../vendor/hammer.js";
import { safeTrack, trackReturnState } from "./launch_analytics.mjs";
import { createTurnstileHook } from "./turnstile_hook.mjs";

let Hooks = {};
Hooks.Turnstile = createTurnstileHook();

Hooks.LaunchAnalytics = {
  mounted() {
    safeTrack("generator_view", {
      context: "home",
      authState: this.el.dataset.authState || "anonymous",
    });

    this.handleEvent("launch-track", (payload = {}) => {
      if (!payload.event) return;

      const { event, ...detail } = payload;
      safeTrack(event, detail);
    });
  },
};

Hooks.GenerationStatus = {
  mounted() {
    this.slowTimer = window.setTimeout(() => {
      this.el.dataset.slow = "true";
      this.el.querySelector("[data-slow-message]")?.removeAttribute("hidden");

      safeTrack("generation_slow_state", {
        context: this.el.dataset.generationContext || "generation_card",
        state: "slow",
      });
    }, 45_000);
  },
  destroyed() {
    window.clearTimeout(this.slowTimer);
  },
};

Hooks.PreviewImage = {
  mounted() {
    this.bindPreview();
  },
  updated() {
    this.bindPreview();
  },
  destroyed() {
    this.unbindPreview();
  },
  bindPreview() {
    const image = this.el.querySelector("img");
    if (image === this.image) {
      this.originalSrc = image?.currentSrc || image?.src || this.originalSrc;
      return;
    }

    this.unbindPreview();
    this.image = image;
    if (!this.image) return;

    const card = this.el.closest("[data-generation-state]");
    this.retryButton = card?.querySelector("[data-preview-retry]");
    this.errorLabel = this.el.querySelector("[data-preview-error]");
    this.originalSrc = this.image.currentSrc || this.image.src;

    this.onPreviewLoad = () => this.setPreviewState("loaded");
    this.onPreviewError = () => this.setPreviewState("error");
    this.onPreviewRetry = () => {
      if (!this.image || !this.originalSrc) return;

      this.setPreviewState("loading", false);
      const retryUrl = new URL(this.originalSrc, window.location.href);
      retryUrl.searchParams.set("preview_retry", Date.now().toString());
      this.image.src = retryUrl.toString();
    };

    this.image.addEventListener("load", this.onPreviewLoad);
    this.image.addEventListener("error", this.onPreviewError);
    this.retryButton?.addEventListener("click", this.onPreviewRetry);

    if (this.image.complete) {
      if (this.image.naturalWidth > 0) {
        this.setPreviewState("loaded");
      } else {
        this.setPreviewState("error");
      }
    }
  },
  unbindPreview() {
    this.image?.removeEventListener("load", this.onPreviewLoad);
    this.image?.removeEventListener("error", this.onPreviewError);
    this.retryButton?.removeEventListener("click", this.onPreviewRetry);
    this.image = null;
    this.retryButton = null;
    this.errorLabel = null;
  },
  setPreviewState(state, track = true) {
    this.el.dataset.previewState = state;
    this.errorLabel?.toggleAttribute("hidden", state !== "error");
    this.retryButton?.toggleAttribute("hidden", state !== "error");

    if (track) {
      safeTrack("preview_image_state", {
        context: this.el.dataset.previewContext || "generation_card",
        state,
      });
    }
  },
};

function authStateForElement(target) {
  const scopedAuth = target.closest("[data-auth-state]");
  if (scopedAuth?.dataset?.authState) {
    return scopedAuth.dataset.authState;
  }

  return undefined;
}

function analyticsDetail(target, extras = {}) {
  return {
    authState: target.dataset.analyticsAuthState || authStateForElement(target),
    context: target.dataset.analyticsContext,
    downloadType: target.dataset.analyticsDownloadType,
    flow: target.dataset.analyticsFlow,
    format: target.dataset.analyticsFormat,
    plan: target.dataset.analyticsPlan,
    ...extras,
  };
}

function trackAnalyticsTarget(target, extras = {}) {
  if (!target?.dataset?.analyticsEvent) return;

  safeTrack(target.dataset.analyticsEvent, analyticsDetail(target, extras));
}

function promptLengthBucket(value) {
  const length = value.trim().length;
  if (length <= 0) return "";
  if (length <= 40) return "1-40";
  if (length <= 120) return "41-120";
  if (length <= 300) return "121-300";
  return "301+";
}

const trackedPromptInputs = new WeakSet();

function trackPromptInput(target) {
  if (!target?.matches?.("[data-analytics-input='prompt']")) return;
  if (trackedPromptInputs.has(target)) return;

  const value = target.value || "";
  const bucket = promptLengthBucket(value);
  if (!bucket) return;

  trackedPromptInputs.add(target);

  safeTrack("prompt_entered", {
    authState: authStateForElement(target),
    context: target.dataset.analyticsContext || "generator_prompt",
    promptLengthBucket: bucket,
    promptLineCount: value.split(/\r?\n/).filter((line) => line.trim()).length,
  });
}

function trackPageMarkers() {
  document.querySelectorAll("[data-analytics-page-event]").forEach((target) => {
    if (target.dataset.analyticsPageTracked === "true") return;
    if (!target.dataset.analyticsPageEvent) return;
    target.dataset.analyticsPageTracked = "true";

    safeTrack(
      target.dataset.analyticsPageEvent,
      analyticsDetail(target),
    );
  });
}

function startPageMarkerObserver() {
  if (typeof MutationObserver !== "function") return;

  const observer = new MutationObserver(() => {
    trackPageMarkers();
  });

  observer.observe(document.documentElement, { childList: true, subtree: true });
}

document.addEventListener("click", (event) => {
  const target = event.target.closest("[data-analytics-event]");
  if (!target || target.tagName === "FORM") return;

  trackAnalyticsTarget(target);
});

document.addEventListener("submit", (event) => {
  const target = event.target.closest("[data-analytics-event]");
  if (!target) return;

  trackAnalyticsTarget(target);
});

document.addEventListener("input", (event) => {
  trackPromptInput(event.target);
});

document.addEventListener("change", (event) => {
  trackPromptInput(event.target);
});

window.addEventListener("phx:generation-cancel-result", (event) => {
  safeTrack("generation_cancel_result", {
    context: event.detail?.context,
    outcome: event.detail?.outcome,
  });
});

trackReturnState();
trackPageMarkers();
startPageMarkerObserver();

Hooks.DownloadImage = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const link = this.el.getAttribute("phx-value-image");
      const name = this.el.getAttribute("phx-value-name");

      fetch(link)
        .then((response) => response.blob())
        .then((blob) => {
          FileSaver.saveAs(blob, `${name}.png`);
        });
    });
  },
};

Hooks.Tinder = {
  mounted() {
    var tinderContainer = document.querySelector(".tinder");
    var allCards = document.querySelectorAll(".tinder--card");
    var nope = document.getElementById("nope");
    var love = document.getElementById("love");
    var nopeButton = document.getElementById("nope");
    var loveButton = document.getElementById("love");
    const liveview = this;

    const addShakeAnimation = (button) => {
      console.log("adding shake animation to button", button);
      button.classList.add("animate-shake");
      // Remove the class after the animation duration (500ms)
      setTimeout(() => {
        button.classList.remove("animate-shake");
      }, 500);
    };

    document.addEventListener("keydown", function (event) {
      const nopeButton = document.getElementById("nope");
      const loveButton = document.getElementById("love");

      if (event.key === "ArrowLeft") {
        // Simulate a left swipe
        nopeButton.click();
      } else if (event.key === "ArrowRight") {
        // Simulate a right swipe
        loveButton.click();
      }
    });

    function initCards(card, index) {
      var newCards = document.querySelectorAll(".tinder--card:not(.removed)");

      newCards.forEach(function (card, index) {
        card.style.zIndex = allCards.length - index;
        card.style.transform =
          "scale(" + (20 - index) / 20 + ") translateY(-" + 30 * index + "px)";
        card.style.opacity = (10 - index) / 10;
      });

      tinderContainer.classList.add("loaded");
    }

    initCards();

    allCards.forEach(function (el) {
      var hammertime = new Hammer(el);

      hammertime.on("pan", function (event) {
        el.classList.add("moving");
      });

      hammertime.on("pan", function (event) {
        if (event.deltaX === 0) return;
        if (event.center.x === 0 && event.center.y === 0) return;

        tinderContainer.classList.toggle("tinder_love", event.deltaX > 0);
        tinderContainer.classList.toggle("tinder_nope", event.deltaX < 0);

        var xMulti = event.deltaX * 0.03;
        var yMulti = event.deltaY / 80;
        var rotate = xMulti * yMulti;

        event.target.style.transform =
          "translate(" +
          event.deltaX +
          "px, " +
          event.deltaY +
          "px) rotate(" +
          rotate +
          "deg)";
      });

      hammertime.on("panend", (event) => {
        el.classList.remove("moving");
        tinderContainer.classList.remove("tinder_love");
        tinderContainer.classList.remove("tinder_nope");

        var moveOutWidth = document.body.clientWidth;
        var keep =
          Math.abs(event.deltaX) < 80 || Math.abs(event.velocityX) < 0.5;

        event.target.classList.toggle("removed", !keep);

        if (keep) {
          event.target.style.transform = "";
        } else {
          var endX = Math.max(
            Math.abs(event.velocityX) * moveOutWidth,
            moveOutWidth
          );
          var toX = event.deltaX > 0 ? endX : -endX;
          var endY = Math.abs(event.velocityY) * moveOutWidth;
          var toY = event.deltaY > 0 ? endY : -endY;
          var xMulti = event.deltaX * 0.03;
          var yMulti = event.deltaY / 80;
          var rotate = xMulti * yMulti;

          event.target.style.transform =
            "translate(" +
            toX +
            "px, " +
            (toY + event.deltaY) +
            "px) rotate(" +
            rotate +
            "deg)";
          initCards();
        }
        var direction = event.deltaX > 0 ? "allow" : "disallow";

        var predictionData = event.target.getAttribute("data-prediction-id");
        console.log("Panned card prediction data:", predictionData);

        if (direction === "allow") {
          addShakeAnimation(loveButton);
        } else {
          addShakeAnimation(nopeButton);
        }

        liveview.pushEvent("swipe_prediction", {
          prediction: predictionData,
          action: direction,
        });
      });
    });

    function createButtonListener(love) {
      return function (event) {
        var cards = document.querySelectorAll(".tinder--card:not(.removed)");
        var moveOutWidth = document.body.clientWidth * 1.5;

        if (!cards.length) return false;

        var card = cards[0];

        // Retrieve the prediction data from the card
        var predictionData = card.getAttribute("data-prediction-id");
        console.log("Swiped prediction:", predictionData); // Log or handle the prediction data as needed

        card.classList.add("removed");
        if (love) {
          card.style.transform =
            "translate(" + moveOutWidth + "px, -100px) rotate(-30deg)";
          addShakeAnimation(loveButton);
        } else {
          card.style.transform =
            "translate(-" + moveOutWidth + "px, -100px) rotate(30deg)";
          console.log("swipe left!");
          addShakeAnimation(nopeButton);
        }

        initCards();

        // Push the event to the LiveView with the prediction data and the action
        liveview.pushEvent("swipe_prediction", {
          prediction: predictionData,
          action: love ? "allow" : "disallow",
        });

        event.preventDefault();
      };
    }

    var nopeListener = createButtonListener(false);
    var loveListener = createButtonListener(true);

    nope.addEventListener("click", nopeListener);
    love.addEventListener("click", loveListener);
  },
  destroyed() {
    if (this.hammer) {
      this.hammer.destroy();
      this.hammer = null;
    }
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

window.addEventListener("phx:copy", async (event) => {
  let button = event.detail.dispatcher;
  // Assuming you want to share the URL stored in a data attribute named 'data-url'
  let urlToShare = event.target.getAttribute("data-url");

  // Check if the Web Share API is available
  if (navigator.share) {
    try {
      await navigator.share({
        title: "Check out this AI sticker I made", // Optional: Title of the content to share
        url: urlToShare, // The URL you want to share
      });
      console.log("Content shared successfully");
    } catch (error) {
      console.error("Error sharing content:", error);
    }
  } else {
    // Fallback for browsers that do not support the Web Share API
    // For example, copy the URL to clipboard
    navigator.clipboard.writeText(urlToShare).then(() => {
      button.innerText = "Link copied to clipboard!";
      setTimeout(() => {
        button.innerText = "Share";
      }, 2000);
    });
  }
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());
// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;
