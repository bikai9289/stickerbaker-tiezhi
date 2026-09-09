const segmenter = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(undefined, {granularity: "grapheme"}) : null;

export const PromptCounter = {
  mounted() {
    this.updatePromptCount = () => {
      const input = this.el.querySelector("[data-prompt-counter]");
      const counter = input && document.getElementById(input.dataset.promptCounter);
      if (counter) counter.textContent = String(segmenter ? [...segmenter.segment(input.value)].length : Array.from(input.value).length);
    };
    this.el.addEventListener("input", this.updatePromptCount);
    this.updatePromptCount();
  },
  updated() { this.updatePromptCount(); },
  destroyed() { this.el.removeEventListener("input", this.updatePromptCount); },
};
