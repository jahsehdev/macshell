#!/usr/bin/env python3
"""Application-local overlays; upstream application files are never edited."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import threading
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent
STATE = Path.home() / ".local/share/macshell/integrated-apps"
SOURCES = {"antigravity": Path("/opt/antigravity-ide"), "spotify": Path("/opt/spotify")}
EXECUTABLES = {"antigravity": "antigravity-ide", "spotify": "spotify"}
spec = importlib.util.spec_from_file_location("macshell_window_action", ROOT / "window_action.py")
actions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(actions)


def spotify_diagnostic(event, **details):
    """Local window-integration diagnostics; never record bridge credentials."""
    try:
        folder = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "macshell"
        folder.mkdir(parents=True, exist_ok=True)
        log = folder / "spotify-window.log"
        if log.exists() and log.stat().st_size > 128 * 1024:
            log.replace(log.with_suffix(".previous.log"))
        with log.open("a") as stream:
            stream.write(json.dumps({"time": datetime.now(timezone.utc).isoformat(),
                                     "event": event, **details}) + "\n")
    except OSError:
        pass


def image_uri(kind, dark, state=""):
    variant = "dark" if dark else "light"
    name = f"titlebutton-{kind}{state}{'-dark' if dark else ''}@2.png"
    path = Path.home() / ".config/macshell/window-controls" / variant / name
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


def controls_css(app):
    if app == "spotify":
        css = """
/* The local executable places Spotify's native menu at x=96 DIP.
   Traffic lights own the left corner; history navigation follows the menu. */
#global-nav-bar, [data-testid="global-nav-bar"] {
    position:relative!important;-webkit-app-region:drag!important;user-select:none;}
/* Linux CEF drag hit testing can swallow the traffic lights. On XWayland,
   route blank-toolbar gestures through the native window-manager protocol. */
html.macshell-system-move :is(#global-nav-bar,[data-testid="global-nav-bar"]),
html.macshell-system-move :is(#global-nav-bar,[data-testid="global-nav-bar"]) * {
    -webkit-app-region:no-drag!important;}
html.macshell-system-move .body-drag-top {
    -webkit-app-region:no-drag!important;pointer-events:none!important;}
#global-nav-bar [data-macshell-navigation],
[data-testid="global-nav-bar"] [data-macshell-navigation] {
    margin-inline-start:80px!important;-webkit-app-region:drag!important;}
#global-nav-bar :is(button,a,input,select,textarea,[role="button"],[role="search"],[role="textbox"]),
[data-testid="global-nav-bar"] :is(button,a,input,select,textarea,[role="button"],[role="search"],[role="textbox"]) {
    -webkit-app-region:no-drag!important;}
#macshell-window-controls {display:flex!important;align-items:center;gap:6px;flex:0 0 66px;
    box-sizing:content-box;width:66px;min-width:66px;height:32px;
    margin:0;position:absolute;left:12px;top:50%;transform:translateY(-50%);
    -webkit-app-region:drag!important;z-index:1;}
#macshell-window-controls button {display:block;flex:0 0 18px;width:18px;height:24px;min-width:18px;
    padding:0;border:0;border-radius:0;background-color:transparent;background-position:center;
    background-size:16px 16px;background-repeat:no-repeat;box-shadow:none;cursor:default;
    -webkit-app-region:no-drag!important;}
#macshell-window-controls button:focus-visible {outline:2px solid #89b4fa;outline-offset:1px;}
"""
        root = "#macshell-window-controls"
        selectors = {kind: f"{root} .macshell-{kind}" for kind in ("close", "minimize", "maximize")}
        variants = [("", True), (".encore-light-theme ", False)]
    else:
        css = """
/* MacShell: style the existing working buttons, in the existing title row. */
.monaco-workbench .part.titlebar .titlebar-container {-webkit-app-region:drag;user-select:none;}
.monaco-workbench .part.titlebar :is(button,a,input,select,textarea,[role="button"],
    .menubar,.action-item,.command-center,.window-controls-container) {-webkit-app-region:no-drag;}
.monaco-workbench:not(.web) .part.titlebar .window-controls-container {
    position:absolute!important;left:10px!important;top:0;width:66px!important;height:100%;
    display:flex!important;align-items:center;gap:6px;-webkit-app-region:no-drag;}
.monaco-workbench .part.titlebar>.titlebar-container>.titlebar-left {
    padding-left:80px!important;box-sizing:border-box;}
.monaco-workbench .part.titlebar .window-controls-container>.window-icon {
    flex:0 0 18px;width:18px!important;height:24px!important;border:0;
    background-color:transparent!important;background-position:center;background-size:16px 16px;
    background-repeat:no-repeat;}
.monaco-workbench .part.titlebar .window-controls-container>.window-icon::before {display:none!important;}
.monaco-workbench .part.titlebar .window-close {order:0;}
.monaco-workbench .part.titlebar .window-minimize {order:1;}
.monaco-workbench .part.titlebar .window-max-restore {order:2;}
.monaco-workbench.fullscreen .part.titlebar .window-controls-container {display:none!important;}
"""
        root = ".monaco-workbench .part.titlebar .window-controls-container"
        selectors = {"close": root + " .window-close", "minimize": root + " .window-minimize",
                     "maximize": root + " .window-max-restore"}
        variants = [("", True), (".vs ", False)]
    for prefix, dark in variants:
        for kind, selector in selectors.items():
            def themed(value):
                if not prefix:
                    return value
                if app == "antigravity":
                    return value.replace(".monaco-workbench", ".monaco-workbench.vs", 1)
                if value.startswith("html."):
                    return value.replace("html.", "html.encore-light-theme.", 1)
                return prefix + value
            for pseudo, state in [("", ""), (":hover", "-hover"), (":active", "-active")]:
                css += f'{themed(selector)}{pseudo} {{background-image:url("{image_uri(kind, dark, state)}")!important;}}\n'
            # Use a descendant selector that remains valid when the state and
            # the variant are on the same ancestor element.
            dim = ("html.macshell-inactive " + selector) if app == "spotify" else selector.replace(".part.titlebar", ".part.titlebar.inactive")
            css += f'{themed(dim)} {{background-image:url("{image_uri(kind, dark, "-backdrop")}")!important;}}\n'
            if app == "antigravity" and kind == "maximize":
                restore = f"{themed(selector)}.codicon-chrome-restore"
                css += f'{restore} {{background-image:url("{image_uri("restore", dark)}")!important;}}\n'
    return css


def mirror(source, target, copied, source_root):
    target.mkdir(parents=True, exist_ok=True, mode=0o700)
    for item in source.iterdir():
        destination = target / item.name
        relative = item.relative_to(source_root)
        if relative.as_posix() in copied:
            shutil.copy2(item, destination)
        elif any(path.startswith(relative.as_posix() + "/") for path in copied):
            mirror(item, destination, copied, source_root)
        else:
            destination.symlink_to(item, target_is_directory=item.is_dir())


def fingerprint(app):
    source = SOURCES[app]
    important = [source / EXECUTABLES[app], ROOT / "launch.py", ROOT / "web/spotify.js", ROOT / "web/antigravity-main.js"]
    important += [source / "Apps/xpui.spa"] if app == "spotify" else [
        source / "resources/app/out/main.js", source / "resources/app/out/vs/workbench/workbench.desktop.main.css"]
    # Electron overlays embed the PNGs as data URIs. Theme artwork changes must
    # invalidate that CSS too, even when the application itself is unchanged.
    important += sorted((Path.home() / ".config/macshell/window-controls").glob("*/*.png"))
    return [(str(p), p.stat().st_mtime_ns, p.stat().st_size) for p in important]


def patch_spotify_menu_binary(executable):
    """Move only the native menu's left inset in our private executable copy.

    Supported Spotify builds use a CEF overlay with Insets(0, 16, 0, 2).
    The single immediate below changes that left inset to 96 DIP. Docking,
    click handling, menu contents and automatic resize layout remain native.
    A different executable must be inspected again, never patched by guessing.
    """
    data = executable.read_bytes()
    # File offsets verified against the disassembled Insets construction in
    # each build. Keep the full executable hash and instruction guard: an
    # application update must never turn this into a speculative byte search.
    builds = {
        "030a6ea5fb2aa791e8acd67703eb7b21f77e8531e70871ebf211b8f9c81a826b": 0x14A2C84,  # 1.3.4.258
        "136880e2c04ba052df199adadb71c5cb8335a99bf50b111c082c53a6497ffc16": 0x2DF4A84,  # 1.3.8.620
    }
    offset = builds.get(hashlib.sha256(data).hexdigest())
    context = bytes.fromhex(
        "807b7100b902000000ba100000000f45d1be100000000f45ce"
        "c7442408000000008954240cc744241000000000894c2414"
        "488b08488d7424084889c7ff9198000000")
    if offset is None or data[offset:offset + len(context)] != context:
        raise RuntimeError("Spotify's native menu layout changed; original application retained")
    mode = executable.stat().st_mode & 0o777
    executable.chmod(mode | 0o200)
    try:
        with executable.open("r+b") as target:
            target.seek(offset + 10)  # mov edx, 16 -> mov edx, 96
            target.write(b"\x60")
    finally:
        executable.chmod(mode)


def prepare(app, force=False):
    destination = STATE / app
    manifest = destination / "macshell-overlay.json"
    current = fingerprint(app)
    if not force and manifest.exists() and json.loads(manifest.read_text()).get("fingerprint") == [list(v) for v in current]:
        return destination
    staging = STATE / (app + f".staging-{os.getpid()}")
    copied = {EXECUTABLES[app]}
    if app == "antigravity":
        copied |= {"bin/antigravity-ide", "resources/app/out/main.js", "resources/app/out/vs/workbench/workbench.desktop.main.css"}
    else:
        copied |= {"Apps/xpui.spa"}
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        mirror(SOURCES[app], staging, copied, SOURCES[app])
        if app == "antigravity":
            main = staging / "resources/app/out/main.js"
            text = main.read_text()
            original = 'async minimizeWindow(t,r){this.windowById(r?.targetWindowId,t)?.win?.minimize()}'
            if text.count(original) != 1:
                raise RuntimeError("Antigravity's window API changed; original application retained")
            hook = (ROOT / "web/antigravity-main.js").read_text().replace("MACSHELL_HELPER", json.dumps(str(ROOT / "window_action.py")))
            replacement = 'async minimizeWindow(t,r){const w=this.windowById(r?.targetWindowId,t)?.win;if(w)globalThis.__macshellWindowControls.minimize(w)}'
            # Register before asynchronous application startup creates windows.
            main.write_text(hook + "\n" + text.replace(original, replacement))
            css = staging / "resources/app/out/vs/workbench/workbench.desktop.main.css"
            css.write_text(css.read_text() + "\n" + controls_css(app))
        else:
            patch_spotify_menu_binary(staging / "spotify")
        manifest_data = {"upstream": str(SOURCES[app]), "fingerprint": current, "copied": sorted(copied)}
        (staging / "macshell-overlay.json").write_text(json.dumps(manifest_data, indent=2) + "\n")
        old = STATE / (app + f".previous-{os.getpid()}")
        if destination.exists():
            destination.rename(old)
        staging.rename(destination)
        if old.exists():
            shutil.rmtree(old)
        return destination
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def patch_spotify(destination, connection):
    target = destination / "Apps/xpui.spa"
    temporary = target.with_suffix(".spa.tmp")
    script = (ROOT / "web/spotify.js").read_text().replace("MACSHELL_BRIDGE", json.dumps(connection))
    css = controls_css("spotify")
    # CEF otherwise reuses the script containing a previous launch's port/token.
    revision = hashlib.sha256((script + css).encode()).hexdigest()[:20]
    with ZipFile(SOURCES["spotify"] / "Apps/xpui.spa") as original, ZipFile(temporary, "w") as modified:
        for item in original.infolist():
            content = original.read(item.filename)
            if item.filename == "index.html":
                content = content.replace(b"</head>", f'<link rel="stylesheet" href="/macshell-controls.css?v={revision}"></head>'.encode())
                content = content.replace(b"</body>", f'<script defer src="/macshell-controls.js?v={revision}"></script></body>'.encode())
            modified.writestr(item, content)
        modified.writestr("macshell-controls.js", script)
        modified.writestr("macshell-controls.css", css)
    temporary.replace(target)


class WindowBridge(BaseHTTPRequestHandler):
    # An ephemeral loopback bridge for this Spotify process only. No account,
    # playback, file, or arbitrary command API is exposed.
    def log_message(self, *_args):
        pass

    def authorized(self):
        path = self.path.split("/")
        return (len(path) == 3 and secrets.compare_digest(path[1], self.server.token)
                and path[2] in {"ready", "close", "minimize", "maximize", "move"}
                and self.headers.get("Origin") in {"https://xpui.app.spotify.com", "https://xpui.app.spotify.com:443"}
                and self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}")

    def reply(self, status, body=b""):
        self.send_response(status)
        if self.authorized():
            self.send_header("Access-Control-Allow-Origin", self.headers["Origin"])
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        authorized = self.authorized()
        spotify_diagnostic("preflight", authorized=authorized)
        self.reply(204 if authorized else 403)

    def do_POST(self):
        if not self.authorized() or self.headers.get("Content-Length", "0") != "0" or self.server.spotify_pid is None:
            spotify_diagnostic("request-rejected")
            self.reply(403)
            return
        try:
            with self.server.action_lock:
                action = self.path.rsplit("/", 1)[1]
                ok = actions.perform(action, "spotify", pid=self.server.spotify_pid)
                body = {"ok": ok}
                if ok and action == "ready":
                    windows = json.loads(actions.hypr("-j", "clients"))
                    body["systemMove"] = (self.server.system_move and any(
                        actions.belongs(w, "spotify", self.server.spotify_pid) and w.get("xwayland")
                        for w in windows))
            self.reply(200 if ok else 409, json.dumps(body).encode())
            spotify_diagnostic("action", action=action, ok=ok, systemMove=body.get("systemMove"))
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
            spotify_diagnostic("action-error", error=str(error))
            self.reply(503, b'{"ok":false}')


def spotify_running():
    # Do not rewrite an archive in use by a previously launched local copy.
    expected = STATE / "spotify/spotify"
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if (process / "exe").resolve() != expected:
                continue
            args = (process / "cmdline").read_bytes().split(b"\0")
            if not any(value.startswith(b"--type=") for value in args):
                return True
        except (OSError, RuntimeError):
            pass
    return False


def spotify_bridge():
    # Keep the endpoint valid across restarts even if CEF retains an older HTML
    # document. The credential stays in this user's private overlay directory.
    saved = STATE / ".spotify-bridge.json"
    connection = {}
    try:
        connection = json.loads(saved.read_text())
        if (type(connection.get("port")) is not int or not 1024 <= connection["port"] <= 65535
                or not isinstance(connection.get("token"), str)
                or len(connection["token"]) < 40):
            connection = {}
    except (OSError, ValueError, TypeError, AttributeError):
        connection = {}
    try:
        server = ThreadingHTTPServer(("127.0.0.1", connection.get("port", 0)), WindowBridge)
    except OSError:
        if not connection:
            raise
        connection = {}
        server = ThreadingHTTPServer(("127.0.0.1", 0), WindowBridge)
    server.token = connection.get("token") or secrets.token_urlsafe(32)
    server.action_lock = threading.Lock()
    server.spotify_pid = None
    temporary = saved.with_suffix(".tmp")
    try:
        temporary.write_text(json.dumps({"port": server.server_port, "token": server.token}))
        temporary.chmod(0o600)
        temporary.replace(saved)
    except OSError:
        server.server_close()
        raise
    return server


def rebuild_spotify_drag(running_commit):
    """Rebuild only when installed headers match this desktop session."""
    script = ROOT / "build.sh"
    if not script.is_file():
        return False
    flags = subprocess.run(["pkg-config", "--cflags", "hyprland"],
                           capture_output=True, text=True, check=True, timeout=5)
    definitions = subprocess.run(
        ["c++", *shlex.split(flags.stdout), "-dM", "-E", "-x", "c++",
         "-include", "hyprland/src/version.h", "/dev/null"],
        capture_output=True, text=True, check=True, timeout=10)
    header = re.search(r'^#define GIT_COMMIT_HASH\s+"([0-9a-f]{40})"$', definitions.stdout, re.M)
    if not header or header.group(1) != running_commit:
        return False
    subprocess.run(["sh", str(script), "--spotify-only"],
                   capture_output=True, text=True, check=True, timeout=120)
    spotify_diagnostic("native-drag-rebuilt", commit=running_commit)
    return True


def ensure_spotify_drag():
    library = ROOT / "spotify-drag.so"
    stamp = library.with_suffix(".so.commit")
    try:
        version = actions.hypr("version")
        commit = stamp.read_text().strip() if stamp.exists() else ""
        if len(commit) != 40 or commit not in version:
            running = re.search(r'\b[0-9a-f]{40}\b', version)
            if not running or not rebuild_spotify_drag(running.group()):
                raise RuntimeError("Spotify drag plugin does not match the running compositor")
            commit = stamp.read_text().strip()
            if commit != running.group():
                raise RuntimeError("Rebuilt Spotify drag plugin does not match the running compositor")
        plugins = json.loads(actions.hypr("-j", "plugin", "list"))
        if any(p.get("name") == "macshell-spotify-drag" and p.get("version") == "1.0" for p in plugins):
            return True
        if actions.hypr("plugin", "load", str(library)).strip() != "ok":
            raise RuntimeError("Spotify drag plugin was not loaded")
        spotify_diagnostic("native-drag-loaded")
        return True
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        spotify_diagnostic("native-drag-unavailable", error=str(error))
        return False


def launch_spotify(arguments):
    if spotify_running():
        spotify_diagnostic("existing-instance", updated=False)
        os.execv(str(STATE / "spotify/spotify"), ["spotify", *arguments])
    destination = prepare("spotify")
    server = spotify_bridge()
    server.system_move = ensure_spotify_drag()
    patch_spotify(destination, {"endpoint": f"http://127.0.0.1:{server.server_port}", "token": server.token})
    child = subprocess.Popen([str(destination / "spotify"), *arguments])
    server.spotify_pid = child.pid
    spotify_diagnostic("started", pid=child.pid, overlay=str(destination), port=server.server_port)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        return child.wait()
    finally:
        spotify_diagnostic("stopped", pid=child.pid)
        server.shutdown()
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", choices=SOURCES)
    parser.add_argument("--prepare", action="store_true")
    args, arguments = parser.parse_known_args()
    if arguments[:1] == ["--"]:
        arguments.pop(0)
    if args.prepare:
        print(prepare(args.app))
        return 0
    try:
        if args.app == "spotify":
            return launch_spotify(arguments)
        destination = prepare(args.app)
        flags = Path.home() / ".config/antigravity-ide-flags.conf"
        if flags.exists():
            arguments += shlex.split(flags.read_text(), comments=True)
        command = str(destination / "bin/antigravity-ide")
        os.execv(command, [command, *arguments])
    except (OSError, ValueError, RuntimeError) as error:
        if args.app == "spotify":
            spotify_diagnostic("launch-error", error=str(error))
        print(f"macshell-controls: {error}; starting the original application.", file=sys.stderr)
        command = "/usr/bin/spotify" if args.app == "spotify" else "/usr/bin/antigravity-ide"
        os.execv(command, [command, *arguments])


if __name__ == "__main__":
    sys.exit(main())
