/* These are native window actions in Spotify's existing navigation toolbar. */
(() => {
  "use strict";
  const bridge = MACSHELL_BRIDGE;
  const invoke = async (action) => {
    const response = await fetch(`${bridge.endpoint}/${bridge.token}/${action}`, {
      method: "POST", mode: "cors", credentials: "omit", referrerPolicy: "no-referrer",
      cache: "no-store", signal: AbortSignal.timeout(action === "minimize" ? 12000 : 5000)
    });
    if (!response.ok) throw new Error("Window action unavailable");
    return response.json();
  };
  let ready = false;
  let connecting = false;
  let retries = 0;
  let retryTimer;
  let scheduled = false;
  let systemMove = false;
  let press = null;
  const interactive = 'button,a,input,select,textarea,[role="button"],[role="search"],[role="textbox"],[role="slider"],[role="menuitem"],[contenteditable="true"]';
  function connect() {
    if (ready || connecting || retryTimer || retries >= 20) return;
    connecting = true;
    invoke("ready").then((result) => {
      ready = true;
      retries = 0;
      systemMove = result.systemMove === true;
      document.documentElement.classList.toggle("macshell-system-move", systemMove);
    }).catch(() => {
      if (++retries < 20) retryTimer = setTimeout(() => { retryTimer = null; connect(); }, 500);
    }).finally(() => { connecting = false; });
  }
  function actionFailed(button) {
    button.title = `${button.getAttribute("aria-label")} — unavailable; reopen Spotify to reconnect`;
    ready = false;
    retries = 0;
    connect();
  }
  document.addEventListener("pointermove", (event) => {
    if (!press || press.pointerId !== event.pointerId) return;
    if (!(event.buttons & 1)) { press = null; return; }
    if (Math.hypot(event.clientX - press.x, event.clientY - press.y) < 4) return;
    press = null;
    // The native helper rechecks the active PID and physical left button, so
    // a delayed request cannot start a move after the user has released it.
    invoke("move").catch(() => {});
  }, true);
  document.addEventListener("pointerup", () => { press = null; }, true);
  document.addEventListener("pointercancel", () => { press = null; }, true);
  function mount() {
    scheduled = false;
    const toolbar = document.querySelector('#global-nav-bar, [data-testid="global-nav-bar"]');
    if (!toolbar) return;
    const navigation = Array.from(toolbar.children).find(
      child => child.id !== "macshell-window-controls" && child.tagName === "DIV"
    );
    if (navigation) navigation.setAttribute("data-macshell-navigation", "");
    connect();
    if (toolbar.querySelector("#macshell-window-controls")) return;
    toolbar.addEventListener("pointerdown", (event) => {
      if (!systemMove || event.button !== 0 || event.target.closest(interactive)) return;
      press = {pointerId: event.pointerId, x: event.clientX, y: event.clientY};
      event.preventDefault();
    });
    toolbar.addEventListener("dblclick", (event) => {
      if (!systemMove || event.button !== 0 || event.target.closest(interactive)) return;
      event.preventDefault();
      invoke("maximize").catch(() => {});
    });
    const controls = document.createElement("div");
    controls.id = "macshell-window-controls";
    controls.setAttribute("role", "group");
    controls.setAttribute("aria-label", "Window controls");
    for (const [action, label] of [["close", "Close window"], ["minimize", "Minimize window"], ["maximize", "Maximize or restore window"]]) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `macshell-window-button macshell-${action}`;
      button.setAttribute("aria-label", label);
      button.title = label;
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        invoke(action).then(() => { button.title = label; }).catch(() => actionFailed(button));
      });
      controls.appendChild(button);
    }
    // Absolutely positioned in the toolbar, so the controls do not become an
    // extra flex item that pushes Spotify's search and account controls apart.
    toolbar.prepend(controls);
  }
  const observer = new MutationObserver(() => {
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(mount);
    }
  });
  observer.observe(document.documentElement, {childList: true, subtree: true});
  window.addEventListener("focus", () => {
    document.documentElement.classList.remove("macshell-inactive");
    if (!ready) { retries = 0; connect(); }
  });
  window.addEventListener("blur", () => {
    press = null;
    document.documentElement.classList.add("macshell-inactive");
  });
  mount();
})();
