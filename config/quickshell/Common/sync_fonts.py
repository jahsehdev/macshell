#!/usr/bin/env python3
"""Apply MacShell's selected SF family and face to native desktop applications."""
import argparse
import configparser
from datetime import datetime, timezone
import fcntl
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from xml.sax.saxutils import escape


WEIGHTS = {"ultralight": 200, "thin": 100, "light": 300, "regular": 400,
           "medium": 500, "semibold": 600, "bold": 700, "heavy": 800, "black": 900}


def run(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=15, check=True)


def selected_font(config):
    for name in ("macdock", "macbar"):
        path = config / name / "settings.json"
        if path.is_file():
            settings = json.loads(path.read_text())
            if settings.get("fontFamily"):
                return settings["fontFamily"], settings.get("fontStyleName") or "Regular"
    return "SF Pro Text", "Regular"


def resolve_font(family, style):
    # System returns to the distribution's default UI face, without a
    # self-referencing sans-serif alias or changes to the emoji font.
    if family in ("sans-serif", "System"):
        family, style = "SF Pro Text", "Regular"
    metadata = run(["fc-list", "--format", "%{family[0]}\t%{style[0]}\t%{weight}\t%{slant}\n"]).stdout
    for line in metadata.splitlines():
        parts = line.split("\t")
        if len(parts) != 4 or parts[0] != family or parts[1].casefold() != style.casefold():
            continue
        if not re.match(r"^SF(?:\s|$)", family):
            break
        weight_name = re.sub(r"\s+italic$", "", parts[1].casefold())
        if weight_name not in WEIGHTS:
            raise ValueError("Unsupported SF font weight: " + parts[1])
        return {"family": family, "style": parts[1], "weight": WEIGHTS[weight_name],
                "fc_weight": int(parts[2].split(",")[0]), "italic": "italic" in parts[1].casefold()}
    raise ValueError(f"Font is not installed: {family} {style}. Install the SF fonts first.")


def pango_font(font, size):
    return f'{font["family"]} {font["style"]} {size:g}'


def qt_font(font, size, version=6):
    weight = font["weight"]
    if version == 5:
        weight = {100: 0, 200: 12, 300: 25, 400: 50, 500: 57, 600: 63, 700: 75, 800: 81, 900: 87}[weight]
    fields = [font["family"], str(size), "-1", "5", str(weight), str(int(font["italic"])),
              "0", "0", "0", "0"]
    if version == 6:
        fields += ["0", "0", "0", "0", "0", "1", font["style"], "0", "0"]
    else:
        fields += [font["style"]]
    # QSettings converts the serialized string back to QFont, including styleName.
    # Quoting keeps the commas in a single QVariant string.
    return '"' + ",".join(fields) + '"'


def fontconfig_xml(font):
    family = escape(font["family"])
    aliases = ""
    for name, preferred in (("sans-serif", family), ("system-ui", family),
                            ("Open Runde", family), ("monospace", "SF Mono")):
        aliases += f'  <alias binding="strong"><family>{name}</family><prefer><family>{preferred}</family></prefer></alias>\n'
    # Prepend explicitly: older user aliases can already have inserted a
    # different strong family by the time this file is evaluated.
    for name in ("sans-serif", "system-ui", "Open Runde"):
        aliases += f'''  <match target="pattern">
    <test name="family" qual="any"><string>{name}</string></test>
    <edit name="family" mode="prepend_first" binding="strong"><string>{family}</string></edit>
  </match>
'''
    aliases += f'''  <match target="pattern">
    <test name="family" qual="first"><string>{family}</string></test>
    <edit name="weight" mode="append"><const>regular</const></edit>
    <edit name="slant" mode="append"><const>roman</const></edit>
  </match>
'''
    # Base UI requests use the selected face. Explicit bold/italic text keeps
    # its own emphasis, and emoji and fixed-width families are preserved.
    return ('<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n'
            '<fontconfig>\n' + aliases + f'''  <match target="pattern">
    <test name="family" qual="first"><string>{family}</string></test>
    <test name="weight" compare="less_eq"><int>{max(100, font["fc_weight"])}</int></test>
    <test name="slant" compare="eq"><const>roman</const></test>
    <edit name="style" mode="assign"><string>{escape(font["style"])}</string></edit>
    <edit name="weight" mode="assign"><int>{font["fc_weight"]}</int></edit>
    <edit name="slant" mode="assign"><int>{100 if font["italic"] else 0}</int></edit>
  </match>
</fontconfig>
''')


class Updates:
    def __init__(self, state):
        self.backup = state / "macshell/backups" / ("native-fonts-" + datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f"))
        self.records = []

    def write(self, path, text):
        if path.is_file() and path.read_text() == text:
            return
        self.backup.mkdir(parents=True, exist_ok=True)
        saved = self.backup / str(len(self.records))
        if path.exists():
            shutil.copy2(path, saved)
        self.records.append({"path": str(path), "original": str(saved) if saved.exists() else None})
        (self.backup / "manifest.json").write_text(json.dumps({"files": self.records}, indent=2) + "\n")
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".font-sync-", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as output:
                output.write(text)
            os.chmod(temporary, path.stat().st_mode & 0o777 if path.exists() else 0o644)
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)


def update_ini(updates, path, section, key, value):
    settings = configparser.ConfigParser(interpolation=None, strict=False)
    settings.optionxform = str
    if path.exists():
        settings.read(path)
    if not settings.has_section(section):
        settings.add_section(section)
    settings[section][key] = value
    output = io.StringIO()
    settings.write(output, space_around_delimiters=False)
    updates.write(path, output.getvalue())


def sync_files(config, state, font):
    updates = Updates(state)
    for version in ("gtk-3.0", "gtk-4.0"):
        update_ini(updates, config / version / "settings.ini", "Settings", "gtk-font-name", pango_font(font, 10))
    for version in (5, 6):
        path = config / f"qt{version}ct/qt{version}ct.conf"
        if version == 6 or path.exists():
            update_ini(updates, path, "Fonts", "general", qt_font(font, 10, version))
    updates.write(config / "fontconfig/conf.d/99-sf-defaults.conf", fontconfig_xml(font))
    return updates


def sync_session(state, font):
    if not shutil.which("gsettings"):
        raise RuntimeError("gsettings is unavailable; font files were updated, but live GTK updates need gsettings.")
    preferences = {
        "org.gnome.desktop.interface": {"font-name": pango_font(font, 10),
                                        "document-font-name": pango_font(font, 11),
                                        "monospace-font-name": "SF Mono 11"},
        "org.gnome.desktop.wm.preferences": {"titlebar-font": pango_font(font, 10)},
    }
    schemas = set(run(["gsettings", "list-schemas"]).stdout.splitlines())
    snapshot = state / "macshell/fonts/gsettings-before.json"
    saved = json.loads(snapshot.read_text()) if snapshot.exists() else {}
    for schema, settings in preferences.items():
        if schema not in schemas:
            continue
        keys = set(run(["gsettings", "list-keys", schema]).stdout.splitlines())
        for key, value in settings.items():
            if key not in keys:
                continue
            current = run(["gsettings", "get", schema, key]).stdout.strip()
            if current == repr(value):
                continue
            identifier = schema + "/" + key
            if identifier not in saved:
                saved[identifier] = current
                snapshot.parent.mkdir(parents=True, exist_ok=True)
                snapshot.write_text(json.dumps(saved, indent=2) + "\n")
            result = run(["gsettings", "set", schema, key, value])
            if "failed to commit" in result.stderr.lower() or run(["gsettings", "get", schema, key]).stdout.strip() != repr(value):
                raise RuntimeError("Desktop session did not retain " + schema + " " + key + ": " + result.stderr.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--family")
    parser.add_argument("--style")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--files-only", action="store_true", help="Update configuration without contacting the desktop session")
    args = parser.parse_args()
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    family, style = selected_font(config)
    font = resolve_font(args.family or family, args.style or ("Regular" if args.family else style))
    if args.check:
        print(json.dumps(font))
        return
    lock = state / "macshell/fonts/sync.lock"
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        updates = sync_files(config, state, font)
        if not args.files_only:
            sync_session(state, font)
    print(json.dumps({"family": font["family"], "style": font["style"], "session": not args.files_only,
                      "changed_files": len(updates.records), "backup": str(updates.backup) if updates.records else None}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit("Font sync failed: " + str(error))
