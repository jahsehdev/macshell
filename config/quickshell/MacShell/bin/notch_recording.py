#!/usr/bin/env python3
"""Inspect a finalized recording and perform explicit local-file actions."""
import hashlib
import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
from urllib.parse import unquote, urlparse


def local_file(value):
    parsed = urlparse(value)
    if parsed.scheme:
        if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
            raise ValueError("Only local recording files are supported.")
        path = Path(unquote(parsed.path))
    else:
        path = Path(value)
    if not path.is_absolute() or path.is_symlink():
        raise ValueError("Choose an absolute recording file, not a shortcut.")
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
        raise ValueError("The recording is missing or empty.")
    return path


def inspect_recording(value):
    path = local_file(value)
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
         "-of", "json", str(path)], capture_output=True, text=True, timeout=15)
    if probe.returncode:
        raise ValueError("The recording could not be finalized as a video.")
    data = json.loads(probe.stdout)
    if not any(s.get("codec_type") == "video" for s in data.get("streams", [])):
        raise ValueError("The saved file has no video track.")
    duration = float(data.get("format", {}).get("duration", 0))
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("The recording has no playable duration.")
    info = path.stat()
    key = hashlib.sha256(f"{path}:{info.st_mtime_ns}:{info.st_size}".encode()).hexdigest()
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "macshell/notch-recording"
    thumbnail = ""
    try:
        cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = cache / (key + ".png")
        if not target.exists():
            result = subprocess.run(
                ["ffmpeg", "-v", "error", "-y", "-i", str(path), "-frames:v", "1",
                 "-vf", "scale=192:192:force_original_aspect_ratio=decrease", str(target)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            if result.returncode and target.exists():
                target.unlink()
        if target.is_file() and target.stat().st_size:
            thumbnail = target.as_uri()
        # Keep only the latest thumbnail cache entries, never touch recordings.
        for old in sorted(cache.glob("*.png"), key=lambda p: p.stat().st_mtime, reverse=True)[24:]:
            old.unlink(missing_ok=True)
    except (OSError, subprocess.TimeoutExpired):
        pass  # The result remains usable without a thumbnail.
    return {"ok": True, "path": str(path), "url": path.as_uri(), "name": path.name,
            "directory": str(path.parent), "duration": duration, "thumbnail": thumbnail}


def perform(action, value):
    path = local_file(value)
    if action == "watch":
        subprocess.Popen(["xdg-open", path.as_uri()], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    elif action == "reveal":
        try:
            shown = subprocess.run(
                ["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
                 "--object-path", "/org/freedesktop/FileManager1", "--method",
                 "org.freedesktop.FileManager1.ShowItems", json.dumps([path.as_uri()]), ""],
                capture_output=True, timeout=5).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            shown = False
        if not shown:
            subprocess.Popen(["xdg-open", path.parent.as_uri()], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    elif action == "copy":
        subprocess.run(["wl-copy", "--type", "text/uri-list"], input=path.as_uri()+"\r\n",
                       text=True, capture_output=True, check=True, timeout=5)
    elif action == "trash":
        subprocess.run(["gio", "trash", "--", str(path)], capture_output=True, check=True, timeout=15)
    else:
        raise ValueError("Unknown recording action.")
    return {"ok": True, "action": action}


def main():
    try:
        action, value = sys.argv[1:]
        result = inspect_recording(value) if action == "inspect" else perform(action, value)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        result = {"ok": False, "error": str(error)}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
