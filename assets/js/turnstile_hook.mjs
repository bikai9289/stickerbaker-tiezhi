export function createTurnstileHook(getTurnstile = () => window.turnstile) {
  return {
    mounted() {
      if (this.turnstileWidgetId) return;

      const render = () => {
        const turnstile = getTurnstile();

        if (!turnstile?.render) {
          this.turnstileReadyTimer = window.setTimeout(render, 100);
          return;
        }

        this.turnstileApi = turnstile;
        this.turnstileWidgetId = turnstile.render(
          this.el.querySelector("[data-turnstile-container]"),
          {
            sitekey: this.el.dataset.siteKey,
            action: this.el.dataset.action,
            callback: (token) => this.pushEvent("turnstile-token", { token }),
            "expired-callback": () => this.pushEvent("turnstile-token", { token: "" }),
            "error-callback": () => this.pushEvent("turnstile-token", { token: "" }),
          },
        );

        this.handleEvent("turnstile-reset", () => {
          this.turnstileApi?.reset(this.turnstileWidgetId);
        });
      };

      render();
    },

    destroyed() {
      window.clearTimeout(this.turnstileReadyTimer);

      if (this.turnstileWidgetId) {
        this.turnstileApi?.remove(this.turnstileWidgetId);
        this.turnstileWidgetId = null;
      }
    },
  };
}
