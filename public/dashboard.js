(function () {
  "use strict";

  const terminalStatuses = new Set(["passed", "failed", "cancelled", "internal_error"]);

  function ready(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback);
    } else {
      callback();
    }
  }

  function setupConfirmationModal() {
    const modal = document.querySelector("[data-confirm-modal]");
    if (!modal) return;

    const message = modal.querySelector("[data-confirm-message]");
    const accept = modal.querySelector("[data-confirm-accept]");
    const cancel = modal.querySelector("[data-confirm-cancel]");
    let pendingForm = null;

    document.querySelectorAll("form[data-confirm]").forEach((form) => {
      form.addEventListener("submit", (event) => {
        if (form.dataset.confirmed === "true") return;
        event.preventDefault();
        pendingForm = form;
        message.textContent = form.dataset.confirm || "Confirm this action?";
        modal.hidden = false;
        accept.focus();
      });
    });

    function close() {
      modal.hidden = true;
      pendingForm = null;
    }

    cancel.addEventListener("click", close);
    modal.addEventListener("click", (event) => {
      if (event.target === modal) close();
    });
    document.addEventListener("keydown", (event) => {
      if (!modal.hidden && event.key === "Escape") close();
    });
    accept.addEventListener("click", () => {
      if (!pendingForm) return;
      pendingForm.dataset.confirmed = "true";
      pendingForm.submit();
    });
  }

  function setupLaunchForm() {
    const form = document.querySelector("[data-launch-form]");
    if (!form) return;

    form.addEventListener("submit", () => {
      const button = form.querySelector("button[type='submit']");
      if (!button) return;
      button.disabled = true;
      button.querySelector("span").textContent = "Starting...";
    });
  }

  function setupRunPolling() {
    const detail = document.querySelector("[data-run-detail]");
    if (!detail) return;

    const runId = detail.dataset.runId;
    const pollStatus = document.querySelector("[data-poll-status]");
    let status = detail.dataset.runStatus;

    if (terminalStatuses.has(status)) return;

    const poll = () => {
      if (document.hidden) return;
      fetch(`/api/runs/${encodeURIComponent(runId)}`)
        .then((response) => {
          if (!response.ok) throw new Error("Run status request failed");
          return response.json();
        })
        .then((payload) => {
          const nextStatus = payload.status;
          if (pollStatus) pollStatus.textContent = `Status: ${nextStatus}`;
          if (nextStatus && nextStatus !== status) {
            status = nextStatus;
            if (terminalStatuses.has(nextStatus)) window.location.reload();
          }
        })
        .catch(() => {
          if (pollStatus) pollStatus.textContent = "Status refresh failed";
        });
    };

    window.setInterval(poll, 2000);
  }

  function setupLogViewer() {
    const viewer = document.querySelector("[data-log-viewer]");
    if (!viewer) return;

    const log = viewer.querySelector(".log");
    const content = viewer.querySelector("[data-log-content]");
    const copy = document.querySelector("[data-copy-log]");
    const wrap = document.querySelector("[data-toggle-wrap]");
    const status = document.querySelector("[data-log-status]");
    const returnBottom = document.querySelector("[data-return-bottom]");
    const runId = viewer.dataset.runId;
    let offset = Number(viewer.dataset.offset || 0);
    let autoScroll = true;

    function isNearBottom() {
      return log.scrollHeight - log.scrollTop - log.clientHeight < 48;
    }

    function scrollBottom() {
      log.scrollTop = log.scrollHeight;
      autoScroll = true;
      if (returnBottom) returnBottom.hidden = true;
    }

    log.addEventListener("scroll", () => {
      autoScroll = isNearBottom();
      if (returnBottom) returnBottom.hidden = autoScroll;
    });

    if (copy) {
      copy.addEventListener("click", () => {
        const text = content.textContent;
        const write = navigator.clipboard
          ? navigator.clipboard.writeText(text)
          : fallbackCopy(text);

        write.then(() => {
          const label = copy.querySelector("span");
          if (label) label.textContent = "Copied";
          window.setTimeout(() => {
            if (label) label.textContent = "Copy";
          }, 1200);
        });
      });
    }

    if (wrap) {
      wrap.addEventListener("click", () => {
        log.classList.toggle("wrap");
      });
    }

    if (returnBottom) {
      returnBottom.addEventListener("click", scrollBottom);
    }

    if (viewer.dataset.live !== "true") return;
    scrollBottom();

    const poll = () => {
      if (document.hidden) return;
      fetch(`/api/runs/${encodeURIComponent(runId)}/output?offset=${offset}`)
        .then((response) => {
          if (!response.ok) throw new Error("Log request failed");
          return response.json();
        })
        .then((payload) => {
          if (payload.text) {
            content.textContent += payload.text;
            offset = Number(payload.next_offset || offset);
            if (autoScroll) scrollBottom();
          }
          if (status) status.textContent = payload.complete ? "Waiting for output" : "Streaming";
        })
        .catch(() => {
          if (status) status.textContent = "Log refresh failed";
        });
    };

    window.setInterval(poll, 1500);
  }

  function fallbackCopy(text) {
    return new Promise((resolve, reject) => {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "fixed";
      textarea.style.left = "-9999px";
      document.body.appendChild(textarea);
      textarea.select();
      const copied = document.execCommand("copy");
      document.body.removeChild(textarea);
      copied ? resolve() : reject(new Error("Copy failed"));
    });
  }

  ready(() => {
    setupConfirmationModal();
    setupLaunchForm();
    setupRunPolling();
    setupLogViewer();
  });
})();
