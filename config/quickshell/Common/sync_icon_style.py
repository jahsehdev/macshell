#!/usr/bin/env python3
"""Generate a folder-only icon theme; preserve the inherited application artwork."""
import argparse
import colorsys
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(text)
    temp.replace(path)


def ini_set(path, section, key, value):
    # Line edits preserve Qt's case-sensitive keys, escaped font values and other sections.
    text = path.read_text() if path.exists() else ""
    pattern = re.compile(r"(?ms)^\[" + re.escape(section) + r"\]\s*\n(.*?)(?=^\[|\Z)")
    match = pattern.search(text)
    if match:
        body = match.group(1)
        line = re.compile(r"(?m)^" + re.escape(key) + r"\s*=.*$")
        body = line.sub(key + "=" + value, body) if line.search(body) else body.rstrip("\n") + "\n" + key + "=" + value + "\n"
        text = text[:match.start(1)] + body + text[match.end(1):]
    else:
        text = text.rstrip("\n") + "\n[" + section + "]\n" + key + "=" + value + "\n"
    atomic(path, text)


def ini_get(path, section, key, fallback=""):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(path)
        return parser.get(section, key, fallback=fallback)
    except configparser.Error:
        return fallback


def recolor_svg(text, target, style, dark):
    rgb = tuple(int(target[i:i+2], 16) / 255 for i in (1, 3, 5))
    th, tl, ts = colorsys.rgb_to_hls(*rgb)

    def replace(match):
        value = match.group(0)
        source = tuple(int(value[i:i+2], 16) / 255 for i in (1, 3, 5))
        h, light, sat = colorsys.rgb_to_hls(*source)
        # Only the original blue/cyan folder material; keep white paper and emblems.
        if not (0.46 <= h <= 0.69 and sat > 0.20):
            return value
        new_l = max(0.18, min(0.89, tl + (light - 0.52) * 0.72))
        if style == "dark" and dark:
            new_l *= 0.73
        if style == "clear":
            new_l = (new_l * 0.55 + 0.35) if not dark else (new_l * 0.45 + 0.12)
        result = colorsys.hls_to_rgb(th, new_l, min(1, ts * (0.48 if style == "clear" else 0.90)))
        return "#" + "".join(f"{round(c * 255):02x}" for c in result)

    result = re.sub(r"#[0-9a-fA-F]{6}(?![0-9a-fA-F])", replace, text)
    if style == "clear":
        # A transparent folder body; no blur or glow is baked into the theme.
        result = re.sub(r"(<svg\b[^>]*>)", r'\1<g opacity="0.72">', result, count=1)
        result = result.replace("</svg>", "</g></svg>")
    return result


def apply(home, config, data, color, style, dark, notify=True):
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Invalid folder color")
    if style not in ("default", "dark", "clear", "tinted"):
        raise ValueError("Invalid icon style")
    state_path = config / "macshell/folders/native-state.json"
    try:
        previous = json.loads(state_path.read_text())
    except (OSError, ValueError):
        previous = {}
    current = ini_get(config / "gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name", "MacTahoe-dark")
    base = previous.get("baseTheme", "MacTahoe-dark") if current.startswith("MacShellFolders-") else current
    if not re.fullmatch(r"[\w. -]+", base) or base.startswith("MacShellFolders-"):
        base = "MacTahoe-dark"
    source = next((p / base / "places/scalable" for p in (data / "icons", home / ".icons", Path("/usr/share/icons"))
                   if (p / base / "places/scalable/folder.svg").is_file()), None)
    if source is None:
        raise FileNotFoundError("The current icon theme has no scalable folder artwork: " + base)
    digest = hashlib.sha256((base + color.lower() + style + str(dark) + "v1").encode()).hexdigest()[:12]
    theme = "MacShellFolders-" + digest
    destination = data / "icons" / theme
    paths = {}
    for path in sorted(source.glob("*.svg")):
        if not (path.stem.startswith("folder") or path.stem in ("user-home", "user-desktop")):
            continue
        out = destination / "scalable/places" / path.name
        atomic(out, recolor_svg(path.read_text(), color, style, dark))
        paths[path.stem] = str(out)
    if "folder" not in paths:
        raise FileNotFoundError("No generic folder icon could be generated")
    # GIO may ask for the MIME name before the generic folder name.
    inode = destination / "scalable/places/inode-directory.svg"
    atomic(inode, Path(paths["folder"]).read_text())
    paths["inode-directory"] = str(inode)
    atomic(destination / "index.theme", f"""[Icon Theme]
Name={theme}
Comment=MacShell folder appearance; inherited application icons remain original
Inherits={base},hicolor
Directories=scalable/places

[scalable/places]
Size=64
Type=Scalable
MinSize=16
MaxSize=512
Context=Places
""")
    for version in ("gtk-3.0", "gtk-4.0"):
        ini_set(config / version / "settings.ini", "Settings", "gtk-icon-theme-name", theme)
    ini_set(config / "qt6ct/qt6ct.conf", "Appearance", "icon_theme", theme)
    ini_set(config / "kdeglobals", "Icons", "Theme", theme)
    state = {"baseTheme": base, "theme": theme, "folderColor": color.lower(), "style": style,
             "dark": dark, "icons": paths}
    atomic(state_path, json.dumps(state, indent=2))
    if notify:
        for command in (["gtk-update-icon-cache", "-f", "-t", str(destination)],
                        ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", theme]):
            try:
                subprocess.run(command, timeout=3, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except (OSError, subprocess.TimeoutExpired):
                pass  # The persistent toolkit files still apply when the application reopens.
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder-color", required=True)
    parser.add_argument("--style", choices=("default", "dark", "clear", "tinted"), required=True)
    parser.add_argument("--dark", choices=("0", "1"), default="0")
    args = parser.parse_args()
    home = Path.home()
    state = apply(home, Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")),
                  Path(os.environ.get("XDG_DATA_HOME", home / ".local/share")),
                  args.folder_color, args.style, args.dark == "1")
    print(json.dumps({"theme": state["theme"], "folders": len(state["icons"])}))


if __name__ == "__main__":
    main()
