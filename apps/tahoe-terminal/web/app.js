"use strict";

(() => {
  const $ = id => document.getElementById(id);
  const native = Boolean(window.webkit?.messageHandlers?.tahoe);
  const defaults = Object.freeze({theme: "dark", palette: "classic", fontFamily: "SF Mono", fontSize: 13, lineHeight: 1.15, opacity: 1, padding: 4, radius: 5, cursorStyle: "block", cursorBlink: true, scrollback: 10000, showStatusBar: false, shell: "/bin/bash"});
  let config = {...defaults}, systemDark = false, home = "", initialCwd = "", nextId = 0, activeId = "";
  let saveTimer = 0, toastTimer = 0, fitFrame = 0;
  const sessions = new Map();
  const encoder = new TextEncoder();
  window.addEventListener("error", event => {
    const message = event.message || "The terminal interface could not start.";
    $("startup").hidden = false;
    $("startup").textContent = message;
  });
  const profiles = {
    classic: {light: ["255, 255, 255", "#777777"], dark: ["0, 0, 0", "#bbbbbb"]},
    tahoe: {light: ["247, 248, 250", "#587fae"], dark: ["29, 32, 39", "#91b3e3"]},
    ocean: {light: ["241, 247, 252", "#427eae"], dark: ["22, 33, 47", "#7db7ea"]},
    forest: {light: ["243, 248, 245", "#3d866b"], dark: ["24, 36, 32", "#7dc8a6"]},
    rose: {light: ["251, 245, 248", "#aa647f"], dark: ["39, 28, 38", "#da9db7"]},
    amber: {light: ["250, 247, 240", "#9c7d3f"], dark: ["39, 34, 27", "#d5b57a"]},
  };

  function send(type, values = {}) {
    if (native) window.webkit.messageHandlers.tahoe.postMessage(JSON.stringify({type, ...values}));
    else if (["edit-css", "open-config", "new-window"].includes(type)) toast("Launch the desktop app to use this action. This is the UI preview.");
  }
  function bytes64(bytes) {
    let text = "";
    for (let i = 0; i < bytes.length; i += 16384) text += String.fromCharCode(...bytes.subarray(i, i + 16384));
    return btoa(text);
  }
  function from64(text) {
    const binary = atob(text), bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; ++i) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  function input(id, text) {
    const bytes = encoder.encode(text);
    if (bytes.length > 4 * 1024 * 1024) { toast("Paste is larger than 4 MB. Please paste a smaller selection."); return; }
    // Chunk transport messages without splitting the UTF-8 byte stream.
    for (let i = 0; i < bytes.length; i += 65536) send("input", {id, data: bytes64(bytes.subarray(i, i + 65536))});
  }
  function toast(text) {
    $("toast").textContent = text; $("toast").hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => $("toast").hidden = true, 4500);
  }
  function active() { return sessions.get(activeId); }
  function shortPath(path) { return home && (path === home || path.startsWith(home + "/")) ? "~" + path.slice(home.length) : path; }
  function folder(path) { return path === home ? "Home" : path.split("/").filter(Boolean).at(-1) || "/"; }
  function icon(name) {
    const element = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    element.classList.add("icon"); element.setAttribute("aria-hidden", "true");
    const use = document.createElementNS(element.namespaceURI, "use");
    use.setAttribute("href", "#i-" + name); element.append(use); return element;
  }
  function terminalTheme() {
    const dark = document.documentElement.dataset.theme === "dark";
    if (config.palette === "classic" && dark) return {
      background: "#00000000", foreground: "#c7c7c7", cursor: "#bfbfbf", cursorAccent: "#000000",
      selectionBackground: "#70707088", selectionInactiveBackground: "#50505066",
      black: "#000000", red: "#cd3333", green: "#00cd00", yellow: "#cdcd00", blue: "#5c5cff", magenta: "#cd00cd", cyan: "#00cdcd", white: "#c7c7c7",
      brightBlack: "#686868", brightRed: "#ff5555", brightGreen: "#55ff55", brightYellow: "#ffff55", brightBlue: "#6f6fff", brightMagenta: "#ff55ff", brightCyan: "#55ffff", brightWhite: "#ffffff",
    };
    return dark ? {
      background: "#00000000", foreground: "#dce3ee", cursor: "#c4d4ea", cursorAccent: "#202630",
      selectionBackground: "#789ece55", selectionInactiveBackground: "#789ece33",
      black: "#424955", red: "#eb8b8b", green: "#96c6a1", yellow: "#d8c18d", blue: "#8bb5e7", magenta: "#cba6d9", cyan: "#8cc7ce", white: "#d8dee9",
      brightBlack: "#758195", brightRed: "#f4a2a2", brightGreen: "#acd9b6", brightYellow: "#e8d29d", brightBlue: "#a7c8f2", brightMagenta: "#dfb6e9", brightCyan: "#a2dce2", brightWhite: "#f4f6fa",
    } : {
      background: "#00000000", foreground: "#2c3441", cursor: "#52677f", cursorAccent: "#f5f7fa",
      selectionBackground: "#82a9d94c", selectionInactiveBackground: "#82a9d92c",
      black: "#303744", red: "#b64d57", green: "#387553", yellow: "#926e29", blue: "#3c70a8", magenta: "#8c5c9b", cyan: "#327e89", white: "#bcc2cc",
      brightBlack: "#7a8392", brightRed: "#c45b64", brightGreen: "#48835f", brightYellow: "#a27b32", brightBlue: "#4d81ba", brightMagenta: "#9b6caa", brightCyan: "#428f9b", brightWhite: "#f4f6f9",
    };
  }
  function terminalOptions() {
    return {fontFamily: `"${config.fontFamily.replace(/["\\]/g, "")}", "Noto Sans Mono", monospace`, fontSize: config.fontSize,
      lineHeight: config.lineHeight, cursorStyle: config.cursorStyle, cursorBlink: config.cursorBlink,
      scrollback: config.scrollback, theme: terminalTheme()};
  }
  function applyAppearance(syncFields = true) {
    const dark = config.theme === "dark" || (config.theme === "auto" && systemDark);
    const theme = dark ? "dark" : "light", root = document.documentElement;
    root.dataset.theme = theme;
    root.dataset.profile = config.palette;
    const [surface, accent] = (profiles[config.palette] || profiles.tahoe)[theme];
    root.style.setProperty("--surface-rgb", surface);
    root.style.setProperty("--accent", accent);
    root.style.setProperty("--surface-opacity", config.opacity);
    root.style.setProperty("--content-padding", config.padding + "px");
    root.style.setProperty("--radius", config.radius + "px");
    root.style.setProperty("--mono-font", `"${config.fontFamily.replace(/["\\]/g, "")}", "Noto Sans Mono", monospace`);
    $("statusbar").hidden = !config.showStatusBar;
    $("zoom-level").textContent = Math.round(config.fontSize / defaults.fontSize * 100) + "%";
    for (const session of sessions.values()) Object.assign(session.term.options, terminalOptions());
    document.querySelectorAll("[data-theme-choice]").forEach(button => {
      const selected = button.dataset.themeChoice === config.theme;
      button.classList.toggle("selected", selected); button.setAttribute("aria-pressed", selected);
    });
    document.querySelectorAll("[data-palette]").forEach(button => {
      const selected = button.dataset.palette === config.palette;
      button.classList.toggle("selected", selected); button.setAttribute("aria-pressed", selected);
    });
    if (syncFields) document.querySelectorAll("[data-setting]").forEach(field => {
      if (document.activeElement === field) return;
      if (field.type === "checkbox") field.checked = config[field.dataset.setting];
      else field.value = config[field.dataset.setting];
    });
    const values = {fontSize: config.fontSize + " px", lineHeight: config.lineHeight.toFixed(2) + "×", opacity: Math.round(config.opacity * 100) + "%", padding: config.padding + " px", radius: config.radius + " px"};
    for (const [key, value] of Object.entries(values)) $(key + "-value").textContent = value;
    send("appearance", {dark}); scheduleFit();
  }
  function saveAppearance() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => send("settings", {config}), 200);
  }
  function scheduleFit() {
    cancelAnimationFrame(fitFrame);
    fitFrame = requestAnimationFrame(() => { fit(active()); requestAnimationFrame(() => fit(active())); });
  }
  function fit(session) {
    if (!session || session.id !== activeId) return;
    const host = session.host, term = session.term;
    // The vendored xterm version is pinned. These are its measured renderer
    // dimensions, used by xterm's own fit addon as well; no guessed character grid.
    const cell = term._core?._renderService?.dimensions?.css?.cell;
    if (!cell || cell.width <= 0 || cell.height <= 0 || host.clientHeight < 1) return;
    const cols = Math.max(2, Math.min(500, Math.floor((host.clientWidth - 8) / cell.width)));
    const rows = Math.max(1, Math.min(300, Math.floor(host.clientHeight / cell.height)));
    if (cols !== term.cols || rows !== term.rows) term.resize(cols, rows);
    if (session.sentCols !== cols || session.sentRows !== rows) {
      session.sentCols = cols; session.sentRows = rows;
      if (session.spawned && !session.exited) send("resize", {id: session.id, cols, rows});
    }
    updateStatus();
  }
  function updateStatus() {
    const session = active(); if (!session) return;
    $("window-location").textContent = folder(session.cwd);
    $("status-path").textContent = shortPath(session.cwd); $("status-path").title = session.cwd;
    const shell = session.shellName;
    $("window-shell").textContent = shell;
    $("session-label").textContent = session.exited ? `Exited ${session.exitCode}` : `${shell} · Local`;
    $("status-dot").className = "status-dot" + (session.exited ? (session.exitCode ? " error" : " exited") : "");
    $("terminal-size").textContent = `${session.term.cols} × ${session.term.rows}`;
    $("restart-button").hidden = !session.exited;
  }
  function selectTab(id, focus = true) {
    if (!sessions.has(id)) return;
    activeId = id;
    $("tabstrip").hidden = sessions.size < 2;
    for (const session of sessions.values()) {
      const selected = session.id === id;
      session.pane.classList.toggle("active", selected); session.tab.classList.toggle("active", selected);
      session.select.setAttribute("aria-selected", selected); session.select.tabIndex = selected ? 0 : -1;
    }
    sessions.get(id).tab.scrollIntoView({block: "nearest", inline: "nearest"});
    updateStatus(); scheduleFit();
    if (focus) requestAnimationFrame(() => sessions.get(id)?.term.focus());
  }
  function newTab(cwd = active()?.cwd || initialCwd) {
    if (sessions.size >= 32) { toast("This window supports up to 32 tabs."); return; }
    const id = "session-" + (++nextId);
    const pane = document.createElement("div"); pane.className = "terminal-pane"; pane.id = "pane-" + id;
    pane.setAttribute("role", "tabpanel"); pane.setAttribute("aria-labelledby", "tab-" + id);
    const host = document.createElement("div"); host.className = "terminal-host"; pane.append(host); $("terminals").append(pane);
    const tab = document.createElement("div"); tab.className = "tab";
    const select = document.createElement("button"); select.className = "tab-select"; select.id = "tab-" + id;
    select.setAttribute("role", "tab"); select.setAttribute("aria-controls", pane.id);
    const label = document.createElement("span"); label.className = "tab-label"; label.textContent = folder(cwd);
    select.append(icon("terminal"), label); select.addEventListener("click", () => selectTab(id));
    const close = document.createElement("button"); close.className = "tab-close"; close.setAttribute("aria-label", "Close " + folder(cwd));
    close.append(icon("close")); close.addEventListener("click", () => closeTab(id));
    tab.append(select, close); $("tabs").append(tab);
    const term = new Terminal({allowTransparency: true, allowProposedApi: true, ...terminalOptions(), cols: 100, rows: 28, fontWeight: 400, fontWeightBold: 600, macOptionIsMeta: false, rightClickSelectsWord: true,
      linkHandler: {activate(event, uri) { if (event.ctrlKey) send("open-link", {uri}); else toast("Hold Ctrl while clicking to open this link."); }}});
    const search = new SearchAddon.SearchAddon(); term.loadAddon(search);
    const unicode = new Unicode11Addon.Unicode11Addon(); term.loadAddon(unicode); term.unicode.activeVersion = "11";
    const session = {id, pane, host, tab, select, label, term, search, cwd, shellName: config.shell.split("/").at(-1) || "shell", spawned: false, opened: false, queuedInput: "", exited: false, exitCode: 0, sentCols: 0, sentRows: 0};
    sessions.set(id, session); term.open(host); selectTab(id);
    term.onData(data => {
      if (session.exited) { if (data === "\r") restart(session); return; }
      if (native) {
        if (session.opened) input(id, data);
        else if (session.queuedInput.length < 65536) session.queuedInput += data;
      } else toast("UI preview. Open Tahoe Terminal from your desktop to run a shell.");
    });
    term.onBinary(data => { if (!session.exited) send("input", {id, data: btoa(data)}); });
    term.onTitleChange(title => {
      const clean = title.replace(/[\x00-\x1f\x7f]/g, "").slice(0, 100);
      session.label.textContent = clean || folder(session.cwd); session.tab.title = clean;
    });
    term.onResize(() => { if (id === activeId) updateStatus(); });
    search.onDidChangeResults(result => {
      if (id === activeId) $("find-result").textContent = result.resultCount ? `${result.resultIndex + 1} / ${result.resultCount}` : "No matches";
    });
    term.registerLinkProvider({provideLinks(y, callback) {
      const line = term.buffer.active.getLine(term.buffer.active.viewportY + y - 1)?.translateToString(true) || "";
      const links = [...line.matchAll(/https?:\/\/[^\s<>"\u0000-\u001f]+/g)].map(match => ({
        range: {start: {x: match.index + 1, y}, end: {x: match.index + match[0].length, y}}, text: match[0],
        activate(event, uri) { if (event.ctrlKey) send("open-link", {uri}); else toast("Hold Ctrl while clicking to open this link."); },
      }));
      callback(links);
    }});
    pane.addEventListener("contextmenu", event => {
      event.preventDefault(); selectTab(id, false);
      const menu = $("context-menu"); $("context-copy").disabled = !term.hasSelection(); menu.hidden = false;
      menu.style.left = Math.min(event.clientX, innerWidth - menu.offsetWidth - 10) + "px";
      menu.style.top = Math.min(event.clientY, innerHeight - menu.offsetHeight - 10) + "px";
      menu.querySelector("button:not(:disabled)")?.focus();
    });
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (!sessions.has(id)) return;
      fit(session); session.spawned = true;
      send("spawn", {id, cwd, cols: term.cols, rows: term.rows});
      $("startup").hidden = true;
      if (!native) {
        term.writeln("\x1b[2mTahoe Terminal · interface preview\x1b[0m\r\n");
        term.writeln("Your shell lives in the desktop application.");
        term.writeln("Use the sliders to explore your terminal's appearance.\r\n");
        term.write("\x1b[32micentry\x1b[0m \x1b[34m~\x1b[0m  › ");
      }
      term.focus();
    }));
    return session;
  }
  function removeTab(id) {
    const session = sessions.get(id); if (!session) return;
    const ids = [...sessions.keys()], index = ids.indexOf(id);
    session.term.dispose(); session.tab.remove(); session.pane.remove(); sessions.delete(id);
    $("tabstrip").hidden = sessions.size < 2;
    if (!sessions.size) { send("close-window"); if (!native) newTab(initialCwd); return; }
    if (activeId === id) selectTab(ids[index + 1] || ids[index - 1]);
  }
  function closeTab(id = activeId) { if (native) send("close-tab", {id}); else removeTab(id); }
  function restart(session = active()) { if (session) { const cwd = session.cwd; removeTabForRestart(session.id); newTab(cwd); } }
  function removeTabForRestart(id) {
    const session = sessions.get(id); if (!session) return;
    session.term.dispose(); session.tab.remove(); session.pane.remove(); sessions.delete(id);
  }
  function showSettings(force) {
    $("settings").hidden = typeof force === "boolean" ? !force : !$("settings").hidden;
    $("settings-toggle").setAttribute("aria-expanded", !$("settings").hidden);
    scheduleFit();
    if ($("settings").hidden) active()?.term.focus(); else $("settings").querySelector("button")?.focus();
  }
  function showFind(force = true) {
    $("findbar").hidden = !force; scheduleFit();
    if (force) { $("find-input").focus(); $("find-input").select(); }
    else { active()?.search.clearDecorations(); active()?.term.focus(); }
  }
  function find(previous = false, incremental = false) {
    const session = active(), query = $("find-input").value;
    if (!session || !query) { $("find-result").textContent = ""; session?.search.clearDecorations(); return; }
    session.search[previous ? "findPrevious" : "findNext"](query, {incremental,
      decorations: {matchBackground: "#ba985f55", matchBorder: "#b69965", activeMatchBackground: "#6d9edb55", activeMatchBorder: "#6d9edb", matchOverviewRuler: "#ba985f", activeMatchColorOverviewRuler: "#6d9edb"}});
  }
  function action(name) {
    $("context-menu").hidden = true;
    const session = active();
    switch (name) {
      case "new-tab": newTab(); break;
      case "settings": showSettings(); break;
      case "find": showFind(); break;
      case "close-find": showFind(false); break;
      case "find-next": find(); break;
      case "find-previous": find(true); break;
      case "copy": if (session?.term.hasSelection()) { send("copy", {text: session.term.getSelection()}); session.term.focus(); } break;
      case "paste": if (session && !session.exited) send("paste", {id: session.id}); break;
      case "clear": if (session) { session.term.clear(); if (!session.exited) input(session.id, "\x0c"); session.term.focus(); } break;
      case "restart": restart(); break;
      case "reset-zoom": config.fontSize = defaults.fontSize; applyAppearance(); saveAppearance(); break;
      case "reset": config = {...defaults, shell: config.shell, scrollback: config.scrollback}; applyAppearance(); saveAppearance(); break;
      default: send(name, session ? {id: session.id} : {});
    }
  }
  document.addEventListener("click", event => {
    const button = event.target.closest("[data-action]");
    if (button && !button.disabled) action(button.dataset.action);
    else if (!event.target.closest("#context-menu")) $("context-menu").hidden = true;
    const theme = event.target.closest("[data-theme-choice]");
    if (theme) { config.theme = theme.dataset.themeChoice; applyAppearance(); saveAppearance(); }
    const profile = event.target.closest("[data-palette]");
    if (profile) { config.palette = profile.dataset.palette; applyAppearance(); saveAppearance(); }
  });
  document.querySelectorAll("[data-setting]").forEach(field => field.addEventListener("input", () => {
    const key = field.dataset.setting;
    config[key] = field.type === "checkbox" ? field.checked : field.type === "range" || key === "scrollback" ? Number(field.value) : field.value;
    if (key === "fontFamily" && !field.value.trim()) return;
    applyAppearance(false); saveAppearance();
  }));
  $("titlebar").addEventListener("mousedown", event => {
    if (event.button === 0 && !event.target.closest("button")) send("drag");
  });
  $("titlebar").addEventListener("dblclick", event => { if (!event.target.closest("button")) send("maximize"); });
  $("find-input").addEventListener("input", () => find(false, true));
  $("find-input").addEventListener("keydown", event => {
    if (event.key === "Enter") { event.preventDefault(); find(event.shiftKey); }
  });
  document.addEventListener("keydown", event => {
    const ctrl = event.ctrlKey && !event.altKey && !event.metaKey;
    const key = event.key.toLowerCase();
    let handled = true;
    if (ctrl && event.shiftKey && key === "t") newTab();
    else if (ctrl && event.shiftKey && key === "w") closeTab();
    else if (ctrl && event.shiftKey && key === "n") send("new-window", {id: activeId});
    else if (ctrl && event.shiftKey && key === "c") action("copy");
    else if (ctrl && event.shiftKey && key === "v") action("paste");
    else if (ctrl && event.shiftKey && key === "f") showFind();
    else if (ctrl && event.shiftKey && key === "k") action("clear");
    else if (ctrl && key === ",") showSettings();
    else if (ctrl && ["=", "+", "-", "0"].includes(key)) {
      config.fontSize = key === "0" ? defaults.fontSize : Math.max(9, Math.min(28, config.fontSize + (key === "-" ? -1 : 1)));
      applyAppearance(); saveAppearance();
    } else if (ctrl && (key === "pageup" || key === "pagedown")) {
      const ids = [...sessions.keys()], index = ids.indexOf(activeId);
      selectTab(ids[(index + (key === "pageup" ? -1 : 1) + ids.length) % ids.length]);
    } else if (event.key === "F11") send("fullscreen");
    else if (event.key === "Escape" && !$("context-menu").hidden) { $("context-menu").hidden = true; active()?.term.focus(); }
    else if (event.key === "Escape" && !$("findbar").hidden) showFind(false);
    else if (event.key === "Escape" && !$("settings").hidden) showSettings(false);
    else if (event.target.closest("#tabs") && ["ArrowLeft", "ArrowRight"].includes(event.key)) {
      const ids = [...sessions.keys()], index = ids.indexOf(activeId);
      selectTab(ids[(index + (event.key === "ArrowLeft" ? -1 : 1) + ids.length) % ids.length], false);
      active()?.select.focus();
    } else handled = false;
    if (handled) { event.preventDefault(); event.stopPropagation(); }
  }, true);
  new ResizeObserver(scheduleFit).observe($("terminals"));
  document.fonts.ready.then(scheduleFit);
  window.addEventListener("focus", () => {
    if (!document.activeElement?.closest("#settings, #findbar, #context-menu")) active()?.term.focus();
  });
  window.hostEvent = event => {
    const session = sessions.get(event.id);
    switch (event.type) {
      case "init":
      case "config":
        config = {...defaults, ...event.config}; systemDark = event.systemDark;
        home = event.home; initialCwd = event.cwd;
        $("custom-style").textContent = event.customCSS || "";
        applyAppearance();
        if (event.type === "init" && !sessions.size) newTab(initialCwd);
        break;
      case "output":
        if (session) {
          const bytes = from64(event.data);
          session.term.write(bytes, () => send("ack", {id: event.id, bytes: bytes.length}));
        }
        break;
      case "opened":
        if (session) {
          session.opened = true; session.cwd = event.cwd;
          if (session.queuedInput) { input(session.id, session.queuedInput); session.queuedInput = ""; }
          updateStatus(); scheduleFit();
        }
        break;
      case "cwd":
        if (session) { session.cwd = event.cwd; session.label.textContent = folder(event.cwd); session.tab.title = event.cwd; updateStatus(); }
        break;
      case "exit":
        if (session) {
          session.exited = true; session.exitCode = event.code;
          session.term.write(`\r\n\x1b[2m[Process exited with code ${event.code}. Press Enter to start a new shell.]\x1b[0m\r\n`);
          updateStatus();
        }
        break;
      case "closed": removeTab(event.id); break;
      case "paste": if (session && !session.exited) { session.term.paste(event.text); session.term.focus(); } break;
      case "focus": if (!document.activeElement?.closest("#settings, #findbar, #context-menu")) active()?.term.focus(); break;
      case "window-state": $("app").classList.toggle("maximized", event.maximized); scheduleFit(); break;
      case "error":
        toast(event.message);
        if (session && !session.opened) { session.exited = true; session.exitCode = 1; updateStatus(); }
        break;
    }
  };
  if (native) send("ready");
  else {
    home = "@HOME@"; initialCwd = home;
    systemDark = matchMedia("(prefers-color-scheme: dark)").matches;
    applyAppearance(); newTab(initialCwd);
  }
})();
