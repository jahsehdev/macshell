#!/usr/bin/env python3
"""Watch download markers; use Chromium's transfer status when available.

Only file metadata and the browser's downloads table are read. Unknown totals
remain unknown. No network requests or file contents are inspected.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import sqlite3
import stat
import subprocess
import sys
import time

PARTIAL = (".crdownload", ".part", ".download")
CHROME_EPOCH = 11644473600


def destinations():
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    default = home / "Downloads"
    try:
        for line in (config / "user-dirs.dirs").read_text().splitlines():
            if line.startswith("XDG_DOWNLOAD_DIR="):
                value = line.split("=", 1)[1].strip().strip('"')
                default = Path(value.replace("${HOME}", str(home)).replace("$HOME", str(home)))
    except OSError:
        pass
    roots = [default]
    try:
        settings = json.loads((config / "macshell/notch-downloads.json").read_text())
        extra = settings.get("directories", []) if isinstance(settings, dict) else []
        if isinstance(extra, list):
            roots += [Path(p).expanduser() for p in extra[:8] if isinstance(p, str)]
    except (OSError, ValueError, TypeError):
        pass
    return list(dict.fromkeys(p for p in roots if p.is_absolute() and p != home and p != Path("/")))


def identifier(path):
    return hashlib.sha256(str(path).encode()).hexdigest()[:24]


def final_path(path):
    return path.with_name(path.name.rsplit(".", 1)[0]) if path.name.lower().endswith(PARTIAL) else path


def browser_paths(jobs):
    return {path for job in jobs for path in [job["path"], *job.get("_paths", [])]}


class FolderDownloads:
    def __init__(self, roots, now=None):
        self.roots = roots
        self.previous = self.files()
        self.jobs = {}
        self.started = time.time() if now is None else now

    def files(self):
        found = {}
        # Extraction and file copies are not downloads. Inspect only the
        # configured destinations, never files inside newly extracted folders.
        for root in self.roots:
            if not root.is_dir() or root.is_symlink():
                continue
            try:
                for entry in root.iterdir():
                    if entry.name.startswith(".") or entry.name.endswith(".aria2"):
                        continue
                    try:
                        info = entry.lstat()
                    except OSError:
                        continue
                    if stat.S_ISREG(info.st_mode):
                        found[str(entry)] = (info.st_size, info.st_mtime_ns, info.st_ino, info.st_dev)
                    if len(found) >= 4000:
                        return found
            except OSError:
                continue
        return found

    def update(self, now=None, excluded_paths=()):
        now = time.time() if now is None else now
        current = self.files()
        # Retire fallback identities once the browser identifies the transfer.
        # Otherwise an old fallback failure can reappear after browser feedback
        # expires, even though that download already completed successfully.
        excluded_paths = set(excluded_paths)
        self.jobs = {key: job for key, job in self.jobs.items()
                     if key not in excluded_paths and job["path"] not in excluded_paths}
        for filename, info in current.items():
            old = self.previous.get(filename)
            path = Path(filename)
            sidecar = Path(filename + ".aria2").is_file()
            partial = path.name.lower().endswith(PARTIAL) or sidecar
            existing = self.jobs.get(filename)
            if old == info and not (existing and existing.get("partial") and not partial):
                continue
            target = final_path(path) if not sidecar else path
            if filename in excluded_paths or str(target) in excluded_paths:
                continue
            job = self.jobs.get(filename)
            if job and job["state"] == "complete" and not partial:
                # Editing/extracting over an already downloaded file does not
                # start another transfer.
                continue
            renamed_partial = bool(existing and existing.get("partial") and not partial)
            if job is None:
                # A partial renamed to its final file keeps the same identity.
                moved = next((key for key, j in self.jobs.items()
                              if key not in current and j.get("partial")
                              and j["state"] in ("active", "waiting")
                              and j["inode"] == info[2:] and info[0] >= j["received"]), None)
                if moved:
                    job = self.jobs.pop(moved)
                    renamed_partial = job.get("partial", False) and not partial
                    self.jobs[filename] = job
                else:
                    # A new or growing ordinary file is also produced by
                    # Nautilus extraction/copy. Require a download marker.
                    if not partial:
                        continue
                    job = {"id": identifier(filename), "received": 0, "speed": 0,
                           "time": now, "changed": now, "inode": info[2:],
                           "target_before": self.previous.get(str(target))}
                    self.jobs[filename] = job
            elapsed = now - job["time"]
            rate = max(0, info[0] - job["received"]) / elapsed if elapsed > 0 else 0
            job["speed"] = rate if not job["speed"] else job["speed"] * .55 + rate * .45
            job.update(path=str(target), name=target.name, directory=str(target.parent),
                       received=info[0], total=-1, progress=-1, eta=-1, time=now,
                       changed=now, inode=info[2:], partial=partial, state="active",
                       source="folder", error="")
            job.pop("missing_since", None)
            if renamed_partial:
                job.update(state="complete", total=info[0], progress=1, eta=0, speed=0)
        for filename, job in list(self.jobs.items()):
            if filename not in current:
                if job["state"] in ("active", "waiting"):
                    target_info = current.get(job["path"])
                    # Finalization may copy/replace the partial, changing its
                    # inode. An unchanged old destination must not count.
                    if (target_info is not None and target_info != job["target_before"]
                            and target_info[0] >= job["received"]):
                        size = target_info[0]
                        job.update(received=size, total=size, progress=1, eta=0, speed=0,
                                   state="complete", partial=False, changed=now)
                    elif now - job.setdefault("missing_since", now) >= 2:
                        job.update(state="interrupted", error="File removed or download interrupted", changed=now)
            elif job.get("partial") and now - job["changed"] >= 15:
                job["state"] = "waiting"
            if now - job["changed"] > 30 and job["state"] in ("complete", "saved", "interrupted"):
                del self.jobs[filename]
        self.previous = current
        return [{k: v for k, v in j.items() if k not in ("time", "inode", "partial", "target_before", "missing_since")}
                for j in self.jobs.values() if j["received"] > 0]


def browser_databases():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    bases = [config / name for name in ("chromium", "google-chrome", "microsoft-edge",
             "vivaldi", "BraveSoftware/Brave-Browser", "Codex")]
    found = []
    for base in bases:
        for pattern in ("Default/History", "Profile */History", "codex-browser-app/History",
                        "Default/Partitions/*/History"):
            found += list(base.glob(pattern))
    return found[:24]


class BrowserDownloads:
    def __init__(self, databases=None, now=None):
        self.databases = browser_databases() if databases is None else databases
        self.started = time.time() if now is None else now
        self.samples = {}
        self.states = {}
        self.paths = {}
        self.auto_discover = databases is None
        self.discovered = self.started

    def update(self, now=None):
        now = time.time() if now is None else now
        jobs = []
        if self.auto_discover and now - self.discovered > 30:
            self.databases = browser_databases(); self.discovered = now
        for database in self.databases:
            try:
                connection = sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=.1)
                try:
                    connection.execute("PRAGMA query_only=ON")
                    columns = {row[1] for row in connection.execute("PRAGMA table_info(downloads)")}
                    paused_column = "paused" if "paused" in columns else "0"
                    rows = connection.execute(
                        "SELECT id,current_path,target_path,received_bytes,total_bytes,state," + paused_column + ",end_time,start_time "
                        "FROM downloads WHERE state=0 OR end_time>=? ORDER BY start_time DESC LIMIT 32",
                        ((max(self.started, now - 30) + CHROME_EPOCH) * 1e6,)).fetchall()
                finally:
                    connection.close()
            except (OSError, sqlite3.Error):
                continue
            for number, current, target, received, total, state, paused, ended, started in rows:
                path = Path(target or current or "")
                if not path.is_absolute() or not path.name or path.is_symlink():
                    continue
                key = identifier(str(database) + ":" + str(number))
                aliases = self.paths.setdefault(key, set())
                for value in (current, target):
                    if value and Path(value).is_absolute():
                        aliases.update((value, str(final_path(Path(value)))))
                received, total = max(0, int(received)), int(total)
                sample = self.samples.get(key)
                rate = 0
                if sample and now > sample[1]:
                    instant = max(0, received - sample[0]) / (now - sample[1])
                    rate = sample[2] * .6 + instant * .4
                self.samples[key] = (received, now, rate)
                # The browser owns transfer status. Completion is still valid
                # before the final path appears, for empty files, or after the
                # user moves the file. File actions validate availability later.
                complete = state == 1
                status = "complete" if complete else "interrupted" if state != 0 else "paused" if paused else "active"
                fingerprint = (received, total, state, bool(paused))
                prior = self.states.get(key)
                changed = prior[1] if prior and prior[0] == fingerprint else now
                self.states[key] = (fingerprint, changed)
                if status == "active" and now - changed >= 15:
                    status = "waiting"
                    rate = 0
                jobs.append({"id": key, "path": str(path), "name": path.name,
                             "directory": str(path.parent), "received": received, "total": total,
                             "progress": 1 if complete else min(1, received / total) if total > 0 else -1,
                             "speed": 0 if complete else rate, "eta": 0 if complete else max(0, (total-received)/rate) if total > 0 and rate > 1 and status == "active" else -1,
                             "state": status, "source": "browser", "changed": changed,
                             "_paths": sorted(aliases),
                             "_started": started,
                             "error": "Download interrupted" if status == "interrupted" else ""})
        live = {j["id"] for j in jobs}
        self.samples = {k: v for k, v in self.samples.items() if k in live}
        self.states = {k: v for k, v in self.states.items() if k in live}
        self.paths = {k: v for k, v in self.paths.items() if k in live}
        return jobs


def merge_jobs(folder, browser):
    exact = {}
    covered = browser_paths(browser)
    for job in sorted(browser, key=lambda j: j.get("_started", 0), reverse=True):
        # The newest attempt wins, including across different browser profiles.
        exact.setdefault(job["path"], {k: v for k, v in job.items() if k not in ("_paths", "_started")})
    for job in folder:
        if job["path"] not in covered:
            exact[job["path"]] = job
    return sorted(exact.values(), key=lambda j: j["changed"], reverse=True)[:32]


def file_action(action, value):
    path = Path(value)
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ValueError("The downloaded file is no longer available.")
    if action == "open":
        command = ["xdg-open", path.as_uri()]
    elif action == "reveal":
        try:
            done = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
                    "--object-path", "/org/freedesktop/FileManager1", "--method",
                    "org.freedesktop.FileManager1.ShowItems", json.dumps([path.as_uri()]), ""],
                    capture_output=True, timeout=5).returncode == 0
            if done:
                return {"ok": True}
        except (OSError, subprocess.TimeoutExpired):
            pass
        command = ["xdg-open", path.parent.as_uri()]
    else:
        raise ValueError("Unknown download action.")
    subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return {"ok": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("watch", "open", "reveal"))
    parser.add_argument("path", nargs="?")
    args = parser.parse_args()
    if args.action != "watch":
        try:
            value = file_action(args.action, args.path or "")
        except (ValueError, OSError) as error:
            value = {"ok": False, "error": str(error)}
        print(json.dumps(value), flush=True)
        return
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    folders = FolderDownloads(destinations())
    browsers = BrowserDownloads()
    previous = None
    while True:
        try:
            browser = browsers.update()
            folder = folders.update(excluded_paths=browser_paths(browser))
            jobs = merge_jobs(folder, browser)
            # Rounded transfer metrics avoid repainting for insignificant noise.
            for job in jobs:
                job["speed"] = round(job["speed"])
                job["eta"] = round(job["eta"]) if job["eta"] >= 0 else -1
            payload = json.dumps({"items": jobs}, separators=(",", ":"))
            if payload != previous:
                print(payload, flush=True)
                previous = payload
        except BrokenPipeError:
            return
        except (OSError, ValueError):
            pass
        time.sleep(.75)


if __name__ == "__main__":
    main()
