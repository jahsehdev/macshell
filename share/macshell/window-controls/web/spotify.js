/* These are native window actions in Spotify's existing navigation toolbar. */
(() => {
  "use strict";
  const bridge = MACSHELL_BRIDGE;
  const invoke = async (action) => {
    const response = await fetch(`${bridge.endpoint}/${bridge.token}/${action}`, {
      method: "POST", mode: "cors", credentials: "omit", referrerPolicy: "no-referrer"
    });
    if (!response.ok) throw new Error("Window action unavailable");
    return response.json();
  };
  let ready = false;
  let scheduled = false;
  function mount() {
    scheduled = false;
    const toolbar = document.querySelector('#global-nav-bar, [data-testid="global-nav-bar"]');
    if (!toolbar || toolbar.querySelector("#macshell-window-controls")) return;
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
        event.stopPropagation();
        invoke(action).catch(() => {});
      });
      controls.appendChild(button);
    }
    toolbar.prepend(controls);
    if (!ready) invoke("ready").then(() => { ready = true; }).catch(() => {});
  }
  const observer = new MutationObserver(() => {
    if (!scheduled) {
      scheduled = true;
      requestAnimationFrame(mount);
    }
  });
  observer.observe(document.documentElement, {childList: true, subtree: true});
  window.addEventListener("focus", () => document.documentElement.classList.remove("macshell-inactive"));
  window.addEventListener("blur", () => document.documentElement.classList.add("macshell-inactive"));
  mount();
})();
