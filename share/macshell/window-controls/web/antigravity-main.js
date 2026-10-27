// This application-local hook keeps Electron's existing controls and close flow.
import {app as macshellApp} from "electron";
import {spawn as macshellSpawn} from "node:child_process";
(() => {
  const helper = MACSHELL_HELPER;
  function action(kind) {
    const child = macshellSpawn("python3", [helper, kind, "antigravity", "--pid", String(process.pid)], {
      detached: true, stdio: "ignore"
    });
    child.on("error", () => {});
    child.unref();
  }
  globalThis.__macshellWindowControls = {minimize: () => action("minimize")};
  macshellApp.on("browser-window-created", (_event, window) => {
    const register = () => {
      if (window.isDestroyed() || !window.isVisible()) return;
      // Keep a header until the rendered workbench contains all real controls.
      window.webContents.executeJavaScript(
        'document.querySelectorAll(".part.titlebar .window-controls-container .window-icon").length === 3'
      ).then((ready) => { if (ready) action("ready"); }).catch(() => {});
    };
    window.webContents.on("did-finish-load", () => setTimeout(register, 1500));
    window.on("show", () => setTimeout(register, 1500));
  });
})();
