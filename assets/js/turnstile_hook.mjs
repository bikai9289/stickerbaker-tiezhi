export function createTurnstileHook(getTurnstile = () => window.turnstile) {
  return {
    mounted() {
      if (this.securityMounted) return;
      this.securityMounted = true;
      this.securityDestroyed = false;
      const status = this.el.querySelector("[data-turnstile-status]");
      const retry = this.el.querySelector("[data-turnstile-retry]");
      const show = (message, canRetry = false) => {
        if (this.securityDestroyed) return;
        status.textContent = message;
        retry.hidden = !canRetry;
      };
      const fail = message => {
        if (this.securityDestroyed) return;
        this.pushEvent("turnstile-token", {token: ""});
        show(message, true);
      };
      const start = () => {
        window.clearTimeout(this.turnstileReadyTimer);
        let attempts = 0;
        show("Loading security check…");
        const render = () => {
          if (this.securityDestroyed) return;
          const api = getTurnstile();
          if (!api?.render) {
            if (++attempts >= 150) {
              fail("Security check could not load. Check your connection or browser blockers, then retry.");
              return;
            }
            this.turnstileReadyTimer = window.setTimeout(render, 100);
            return;
          }
          this.turnstileApi = api;
          try {
            this.turnstileWidgetId = api.render(this.el.querySelector("[data-turnstile-container]"), {
              sitekey: this.el.dataset.siteKey,
              action: this.el.dataset.action,
              callback: token => {
                if (this.securityDestroyed) return;
                this.pushEvent("turnstile-token", {token});
                show("Security check complete.");
              },
              "expired-callback": () => fail("Security check expired. Please retry."),
              "error-callback": () => { fail("Security check failed. Please retry or check your browser connection."); return true; },
              "timeout-callback": () => fail("Security check timed out. Please retry."),
            });
          } catch (_) {
            fail("Security check could not start. Please retry.");
          }
        };
        render();
      };
      this.securityRetry = event => {
        event?.preventDefault();
        this.pushEvent("turnstile-token", {token: ""});
        if (this.turnstileWidgetId != null) {
          show("Complete the security check to continue.");
          try { this.turnstileApi.reset(this.turnstileWidgetId); }
          catch (_) { fail("Security check could not restart. Refresh the page to try again."); }
        } else {
          if (!getTurnstile()?.render) {
            const old = document.querySelector("script[data-turnstile-script]");
            if (old) {
              const script = document.createElement("script");
              script.src = old.src;
              script.defer = true;
              script.dataset.turnstileScript = "";
              old.replaceWith(script);
            }
          }
          start();
        }
      };
      retry.addEventListener("click", this.securityRetry);
      this.handleEvent("turnstile-reset", () => {
        if (!this.securityDestroyed) this.securityRetry();
      });
      start();
    },
    destroyed() {
      this.securityDestroyed = true;
      window.clearTimeout(this.turnstileReadyTimer);
      this.el.querySelector("[data-turnstile-retry]").removeEventListener("click", this.securityRetry);
      if (this.turnstileWidgetId != null) {
        this.turnstileApi?.remove(this.turnstileWidgetId);
        this.turnstileWidgetId = null;
      }
    },
  };
}
