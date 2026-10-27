#!/usr/bin/env python3
"""MacShell desktop files: newline-delimited JSON over stdin/stdout.

File names never enter a shell. Drops always copy, collisions get a new name,
and removal uses the freedesktop Trash through GIO. inotify keeps Dolphin and
the desktop in sync without repeatedly spawning directory-listing processes.
"""

import argparse
import ctypes
from datetime import datetime
import json
import mimetypes
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote, unquote, urlparse


def desktop_directory():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    dirs = config / "user-dirs.dirs"
    if dirs.exists():
        for line in dirs.read_text().splitlines():
            if line.strip().startswith("XDG_DESKTOP_DIR="):
                value = line.split("=", 1)[1].strip().strip('"')
                value = value.replace("${HOME}", str(Path.home())).replace("$HOME", str(Path.home()))
                path = Path(value).expanduser()
                if path.is_absolute() and path != Path.home():
                    return path
    path = Path.home() / "Desktop"
    # Register Desktop with Dolphin as well as the shell. Preserve other dirs.
    config.mkdir(parents=True, exist_ok=True)
    old = dirs.read_text() if dirs.exists() else ""
    lines = [line for line in old.splitlines() if not line.strip().startswith("XDG_DESKTOP_DIR=")]
    dirs.write_text("\n".join(lines + ['XDG_DESKTOP_DIR="$HOME/Desktop"']) + "\n")
    return path


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".layout-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, ensure_ascii=True)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class DesktopFiles:
    def __init__(self, desktop, state):
        self.desktop = Path(desktop).absolute()
        self.desktop.mkdir(parents=True, exist_ok=True)
        self.state = Path(state)
        try:
            self.positions = json.loads(self.state.read_text()).get("positions", {})
            if not isinstance(self.positions, dict):
                self.positions = {}
        except (OSError, ValueError, AttributeError):
            self.positions = {}

    def save(self):
        atomic_json(self.state, {"version": 1, "positions": self.positions})

    def entry(self, name):
        if not isinstance(name, str) or not name or name in (".", "..") or "/" in name or "\0" in name:
            raise ValueError("Choose a file name without a slash.")
        return self.desktop / name

    def listing(self):
        items = []
        for path in sorted(self.desktop.iterdir(), key=lambda p: p.name.casefold()):
            if path.name.startswith("."):
                continue
            directory = path.is_dir()
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            icon = "folder" if directory else mime.replace("/", "-")
            fallback = "folder" if directory else mime.split("/", 1)[0] + "-x-generic"
            items.append({"name": path.name, "path": str(path), "url": path.as_uri(),
                          "directory": directory, "icon": icon, "fallback": fallback,
                          "image": not directory and mime.startswith("image/"),
                          "position": self.positions.get(path.name)})
        return {"event": "files", "directory": str(self.desktop), "items": items}

    @staticmethod
    def source(value):
        parsed = urlparse(value)
        if parsed.scheme == "file" and parsed.netloc in ("", "localhost"):
            return Path(unquote(parsed.path))
        if not parsed.scheme and Path(value).is_absolute():
            return Path(value)
        raise ValueError("Only local files and folders can be copied to the desktop.")

    def candidate(self, name, number):
        path = Path(name)
        suffix = "" if number == 0 else (" copy" if number == 1 else " copy " + str(number))
        return self.entry(path.stem + suffix + path.suffix)

    def copy_one(self, value):
        source = self.source(value)
        if not source.exists() and not source.is_symlink():
            raise FileNotFoundError("The source file no longer exists: " + source.name)
        directory = source.is_dir() and not source.is_symlink()
        if directory and (self.desktop.resolve() == source.resolve() or source.resolve() in self.desktop.resolve().parents):
            raise ValueError("A folder cannot be copied into itself: " + source.name)
        if not directory and not source.is_file() and not source.is_symlink():
            raise ValueError("This item is not a regular file or folder: " + source.name)
        for number in range(10000):
            target = self.candidate(source.name, number)
            try:
                if source.is_symlink():
                    target.symlink_to(os.readlink(source), target_is_directory=source.is_dir())
                elif directory:
                    # copytree creates the destination exclusively; it never merges
                    # a drop into an unrelated existing folder with the same name.
                    shutil.copytree(source, target, symlinks=True)
                else:
                    with source.open("rb") as original, target.open("xb") as copied:
                        shutil.copyfileobj(original, copied, length=1024 * 1024)
                    shutil.copystat(source, target, follow_symlinks=False)
                return target.name
            except FileExistsError:
                continue
        raise FileExistsError("Too many copies with the same name.")

    def trash_one(self, path):
        result = subprocess.run(["gio", "trash", "--", str(path)], capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return
        # GIO refuses some bind mounts (including sandboxed home directories).
        # The same-filesystem fallback still follows the freedesktop Trash spec:
        # write recoverable metadata first, then atomically move without replacing.
        trash = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "Trash"
        trash.mkdir(mode=0o700, parents=True, exist_ok=True)
        for directory in (trash / "files", trash / "info"):
            directory.mkdir(mode=0o700, exist_ok=True)
        libc = ctypes.CDLL(None, use_errno=True)
        for number in range(10000):
            name = path.name + ("." + str(number) if number else "")
            target, info = trash / "files" / name, trash / "info" / (name + ".trashinfo")
            if target.exists() or target.is_symlink():
                continue
            try:
                with info.open("x") as stream:
                    os.chmod(info, 0o600)
                    stream.write("[Trash Info]\nPath=" + quote(str(path.absolute()), safe="/")
                                 + "\nDeletionDate=" + datetime.now().strftime("%Y-%m-%dT%H:%M:%S") + "\n")
                    stream.flush()
                    os.fsync(stream.fileno())
            except FileExistsError:
                continue
            try:
                if libc.renameat2(-100, os.fsencode(path), -100, os.fsencode(target), 1) != 0:
                    code = ctypes.get_errno()
                    raise OSError(code, os.strerror(code))
                return
            except FileExistsError:
                info.unlink()
                continue
            except OSError:
                info.unlink()
                raise OSError(result.stderr.strip() or "Could not move the item to Trash.")
        raise FileExistsError("Could not find a free name in Trash.")

    def command(self, request):
        action = request.get("action")
        if action == "copy":
            copied, errors = [], []
            for value in request.get("urls", []):
                try:
                    copied.append(self.copy_one(value))
                except (OSError, ValueError, shutil.Error) as error:
                    errors.append(str(error))
            return {"event": "result", "action": action, "names": copied,
                    "message": str(len(copied)) + " item(s) copied to Desktop." if copied else "",
                    "error": "\n".join(errors)}
        if action == "rename":
            source, target = self.entry(request["name"]), self.entry(request["newName"].strip())
            if source == target:
                return {"event": "result", "action": action, "message": ""}
            if target.exists() or target.is_symlink():
                raise FileExistsError("An item with that name already exists.")
            # renameat2(RENAME_NOREPLACE) also protects against a concurrent
            # Dolphin rename/copy between checking and committing the new name.
            libc = ctypes.CDLL(None, use_errno=True)
            result = libc.renameat2(-100, os.fsencode(source), -100, os.fsencode(target), 1)
            if result != 0:
                code = ctypes.get_errno()
                raise OSError(code, os.strerror(code))
            if source.name in self.positions:
                self.positions[target.name] = self.positions.pop(source.name)
                self.save()
            return {"event": "result", "action": action, "names": [target.name], "message": "Renamed."}
        if action == "trash":
            for name in request.get("names", []):
                path = self.entry(name)
                self.trash_one(path)
                self.positions.pop(name, None)
            self.save()
            return {"event": "result", "action": action, "message": "Moved to Trash."}
        if action == "mkdir":
            for number in range(10000):
                name = "New Folder" + (" " + str(number + 1) if number else "")
                try:
                    self.entry(name).mkdir()
                    return {"event": "result", "action": action, "names": [name], "message": "Folder created."}
                except FileExistsError:
                    continue
            raise FileExistsError("Too many folders with the same name.")
        if action == "positions":
            for name, position in request.get("positions", {}).items():
                self.entry(name)
                if (isinstance(position, dict) and isinstance(position.get("x"), (float, int))
                        and isinstance(position.get("y"), (float, int))):
                    self.positions[name] = {"x": position["x"], "y": position["y"]}
            self.save()
            return None
        if action != "refresh":
            raise ValueError("Unknown desktop action.")
        return None


def emit(value):
    print(json.dumps(value, ensure_ascii=True), flush=True)


def serve(files):
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin.fileno(), selectors.EVENT_READ, "input")
    libc = ctypes.CDLL(None, use_errno=True)
    watch_fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    if watch_fd >= 0:
        watch = libc.inotify_add_watch(watch_fd, os.fsencode(files.desktop), 0x00000FCC)
        if watch >= 0:
            selector.register(watch_fd, selectors.EVENT_READ, "watch")
        else:
            os.close(watch_fd)
            watch_fd = -1
    emit(files.listing())
    buffered, dirty_at = b"", 0
    previous_mtime = files.desktop.stat().st_mtime_ns
    try:
        while True:
            for key, _ in selector.select(0.15 if dirty_at else 2):
                if key.data == "watch":
                    while True:
                        try:
                            if not os.read(watch_fd, 65536):
                                break
                        except BlockingIOError:
                            break
                    dirty_at = time.monotonic()
                    continue
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    return
                buffered += chunk
                while b"\n" in buffered:
                    line, buffered = buffered.split(b"\n", 1)
                    action = ""
                    try:
                        request = json.loads(line)
                        action = request.get("action", "")
                        if action in ("copy", "trash"):
                            emit({"event": "busy", "action": action})
                        result = files.command(request)
                        if result:
                            emit(result)
                        if action != "positions":
                            emit(files.listing())
                    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
                        emit({"event": "result", "action": action, "error": str(error)})
                        emit(files.listing())
            # Coalesce a burst of file-manager events into one model update.
            if dirty_at and time.monotonic() - dirty_at >= 0.12:
                emit(files.listing())
                dirty_at = 0
            if watch_fd < 0:
                mtime = files.desktop.stat().st_mtime_ns
                if mtime != previous_mtime:
                    emit(files.listing())
                    previous_mtime = mtime
    finally:
        selector.close()
        if watch_fd >= 0:
            os.close(watch_fd)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--desktop", type=Path)
    parser.add_argument("--state", type=Path, default=Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "macdesktop" / "layout.json")
    options = parser.parse_args()
    try:
        serve(DesktopFiles(options.desktop or desktop_directory(), options.state))
    except (OSError, ValueError) as error:
        emit({"event": "result", "error": str(error)})
        sys.exit(1)


if __name__ == "__main__":
    main()
