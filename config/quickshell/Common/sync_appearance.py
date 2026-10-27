#!/usr/bin/env python3
"""Keep GNOME/GTK appearance in step with MacShell's resolved Light/Dark mode."""
import argparse
import configparser
import datetime
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile


def write_changed(path, text):
    path = Path(path)
    if path.is_file() and path.read_text() == text:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".appearance-", delete=False) as temporary:
        temporary.write(text)
        name = temporary.name
    try:
        os.chmod(name, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def resolved_mode(settings, hour=None):
    mode = settings.get("appearanceMode")
    if mode in ("light", "dark"):
        return mode
    if isinstance(settings.get("darkMode"), bool):
        return "dark" if settings["darkMode"] else "light"
    hour = datetime.datetime.now().hour if hour is None else hour
    return "dark" if hour < 7 or hour >= 19 else "light"


def theme_paths(home, data):
    result = {}
    for variant in ("Light", "Dark"):
        for directory in (data / "macshell/nautilus/themes", home / ".themes", data / "themes"):
            path = directory / ("MacTahoe-" + variant) / "gtk-4.0/gtk.css"
            if path.is_file():
                result[variant] = path.resolve()
                break
        else:
            raise RuntimeError("Missing MacTahoe-" + variant + " GTK 4 theme")
    return result


def stylesheet(themes):
    # GTK 4.20+ binds user CSS media queries to gtk-interface-color-scheme.
    # Both variants remain loaded, so an open app can react to portal updates.
    css = "/* MacShell: follow the system color scheme with the installed MacTahoe themes. */\n"
    for mode, variant in (("light", "Light"), ("dark", "Dark")):
        css += f'@media (prefers-color-scheme: {mode}) {{\n  @import url("{themes[variant].as_uri()}");\n}}\n'
    # Modern libadwaita apps use custom properties rather than GTK named colors.
    colors = ("window_bg", "window_fg", "view_bg", "view_fg", "headerbar_bg", "headerbar_fg",
              "headerbar_border", "headerbar_backdrop", "headerbar_shade", "sidebar_bg", "sidebar_fg",
              "sidebar_backdrop", "sidebar_border", "sidebar_shade", "secondary_sidebar_bg",
              "secondary_sidebar_fg", "secondary_sidebar_backdrop", "secondary_sidebar_border",
              "secondary_sidebar_shade", "card_bg", "card_fg", "card_shade", "popover_bg",
              "popover_fg", "popover_shade", "dialog_bg", "dialog_fg", "accent_bg", "accent_fg", "accent")
    css += ":root {\n"
    for color in colors:
        name = color + "_color"
        css += f"  --{name.replace('_', '-')}: @{name};\n"
    return css + "}\n"


def sync_files(home, config, data, mode):
    themes = theme_paths(home, data)  # Validate both variants before changing files.
    dynamic = config / "macshell/appearance/theme.css"
    write_changed(dynamic, stylesheet(themes))
    integration = config / "macshell/nautilus"
    # Preserve existing GTK entry points, Nautilus adjustments and corner hooks.
    for name in ("theme-import.css", "dark-import.css"):
        write_changed(integration / name, f'@import url("{dynamic.as_uri()}");\n')
    for version in ("gtk-3.0", "gtk-4.0"):
        path = config / version / "settings.ini"
        settings = configparser.ConfigParser(interpolation=None, strict=False)
        settings.optionxform = str
        if path.exists():
            settings.read(path)
        if not settings.has_section("Settings"):
            settings.add_section("Settings")
        settings["Settings"]["gtk-theme-name"] = "MacTahoe-" + mode.capitalize()
        settings["Settings"]["gtk-application-prefer-dark-theme"] = "1" if mode == "dark" else "0"
        # This also gives GTK a correct initial preference before the portal connects.
        if version == "gtk-4.0":
            settings["Settings"]["gtk-interface-color-scheme"] = "2" if mode == "dark" else "3"
        output = io.StringIO()
        settings.write(output, space_around_delimiters=False)
        write_changed(path, output.getvalue())


def sync_gsettings(config, mode):
    def run(*args):
        return subprocess.check_output(["gsettings", *args], text=True, stderr=subprocess.PIPE, timeout=10).strip()

    schemas = set(run("list-schemas").splitlines())
    changes = [("org.gnome.desktop.interface", "gtk-theme", "'MacTahoe-" + mode.capitalize() + "'"),
               ("org.gnome.desktop.interface", "color-scheme", "'prefer-" + mode + "'"),
               ("org.gnome.Console", "theme", "'auto'"),
               ("org.gnome.TextEditor", "style-variant", "'follow'")]
    snapshot = config / "macshell/appearance/previous-gsettings.json"
    saved = json.loads(snapshot.read_text()) if snapshot.exists() else {}
    for schema, key, value in changes:
        if schema not in schemas:
            continue
        current = run("get", schema, key)
        if current == value:
            continue
        identifier = schema + " " + key
        if identifier not in saved:
            saved[identifier] = current
            write_changed(snapshot, json.dumps(saved, indent=2) + "\n")
        run("set", schema, key, value)
        if run("get", schema, key) != value:
            raise RuntimeError(f"GNOME did not retain {schema} {key}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("light", "dark"))
    parser.add_argument("--files-only", action="store_true", help="Update theme files without contacting the desktop session")
    args = parser.parse_args()
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    data = Path(os.environ.get("XDG_DATA_HOME", home / ".local/share"))
    mode = args.mode
    if mode is None:
        mode = resolved_mode(json.loads((config / "macbar/settings.json").read_text()))
    sync_files(home, config, data, mode)
    if not args.files_only:
        sync_gsettings(config, mode)
    print(json.dumps({"appearance": mode, "gnome": not args.files_only, "theme": "MacTahoe-" + mode.capitalize()}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit("Appearance sync failed: " + str(error))
