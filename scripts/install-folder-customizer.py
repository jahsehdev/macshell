#!/usr/bin/env python3
"""Update only Folder Customization in an existing MacShell installation."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def payload(home):
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    if home != Path.home():
        config, data = home / ".config", home / ".local/share"
    items = []
    for relative, target in [
        ("config/quickshell/folder-customizer", config / "quickshell/folder-customizer"),
        ("share/macshell/folder-customizer", data / "macshell/folder-customizer"),
    ]:
        source_root = ROOT / relative
        for source in sorted(source_root.rglob("*")):
            if source.is_dir() or "__pycache__" in source.parts or "tests" in source.parts or source.suffix == ".pyc":
                continue
            items.append((source, target / source.relative_to(source_root)))
    for name in ("DesktopMenuIcon.qml", "DesktopSurface.qml", "DesktopMenu.qml", "DesktopIcon.qml", "bin/desktop_files.py", "FolderCustomization"):
        items.append((ROOT / "config/quickshell/MacShell" / name, config / "quickshell/MacShell" / name))
    for name in ("macshell-folder-customize", "macshell-nautilus"):
        items.append((ROOT / "bin" / name, home / ".local/bin" / name))
    return items


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".folder-install-", dir=target.parent)
    os.close(fd)
    temporary = Path(temp)
    try:
        if source.is_symlink():
            temporary.unlink()
            temporary.symlink_to(os.readlink(source))
        else:
            shutil.copy2(source, temporary)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)


def install(home, dry_run=False, skip_build=False):
    if not dry_run and not skip_build:
        subprocess.run(["sh", str(ROOT / "share/macshell/folder-customizer/native/build.sh")], check=True)
    items = payload(home)
    if dry_run:
        for source, target in items:
            print(f"{source.relative_to(ROOT)} -> {target}")
        return
    if not (ROOT / "share/macshell/folder-customizer/native/folder-menu.so").is_file():
        raise RuntimeError("Build the Nautilus folder menu before installing.")
    state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) if home == Path.home() else home / ".local/state"
    backup = state / "macshell/backups" / ("folder-customizer-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f"))
    backup.mkdir(parents=True)
    records = []
    try:
        for source, target in items:
            if target.is_dir() and not target.is_symlink():
                raise RuntimeError("Expected a file, found directory: " + str(target))
            saved = backup / str(len(records))
            existed = target.exists() or target.is_symlink()
            if existed:
                copy(target, saved)
            records.append(dict(path=str(target), original=str(saved) if existed else None))
            copy(source, target)
        (backup / "manifest.json").write_text(json.dumps(dict(files=records), indent=2) + "\n")
    except Exception:
        for record in reversed(records):
            target = Path(record["path"])
            if record["original"]:
                copy(Path(record["original"]), target)
            else:
                target.unlink(missing_ok=True)
        raise
    print(f"Installed {len(records)} files. Backup: {backup}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    options = parser.parse_args()
    install(options.home.expanduser().absolute(), options.dry_run, options.skip_build)
