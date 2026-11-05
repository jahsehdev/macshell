#!/usr/bin/env python3
"""Render the default glass traffic lights; optionally refresh installed copies.

Requires rsvg-convert (librsvg). Existing names, canvas sizes and 14px artwork
diameter are retained, so the application integrations need no layout changes.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
NAME = re.compile(r"titlebutton-(close|minimize|maximize|restore)(-backdrop-hover|-backdrop|-hover|-active)?(-dark)?(@2)?\.png$")
COLORS = {
    "close": ("#ff5d52", "#ffc1a3"),
    "minimize": ("#ffc000", "#fff27d"),
    "maximize": ("#44c400", "#97e843"),
    "restore": ("#44c400", "#97e843"),
}


def artwork(kind, state, dark):
    # Hover reveals only the glyph; fill, rim and inactive gray stay unchanged.
    hovered = state in ("-hover", "-backdrop-hover")
    state = {"-hover": "", "-backdrop-hover": "-backdrop"}.get(state, state)
    base, glow = COLORS[kind]
    if state == "-backdrop":
        base, glow = ("#464a50", "#62686d") if dark else ("#c5c7cb", "#ebedf0")
    glyphs = {
        "close": '<path d="M6 6l4 4M10 6l-4 4" fill="none" stroke="currentColor" stroke-width="1.55" stroke-linecap="round"/>',
        "minimize": '<path d="M5.3 8h5.4" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
        "maximize": '<path d="M4 4h5L4 9ZM12 12H7l5-5Z"/>',
        "restore": '<path d="M7.3 3.3v4h-4ZM8.7 12.7v-4h4Z"/>',
    }
    glyph = glyphs[kind] if hovered or state == "-active" else ""
    # Small native controls need larger, darker green-button glyphs. Inward
    # restore arrows previously had only 2px sides and disappeared at 1x scale.
    glyph_opacity = ".9" if kind in ("maximize", "restore") else ".65"
    # Pressed artwork darkens while keeping the existing icon/state contract.
    shade = ".16" if state == "-active" else "0"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
<defs>
  <clipPath id="disc"><circle cx="8" cy="8" r="7"/></clipPath>
  <linearGradient id="volume" x1="0" y1="0" x2="0" y2="1" gradientUnits="objectBoundingBox">
    <stop stop-color="white" stop-opacity=".07"/>
    <stop offset=".55" stop-color="black" stop-opacity=".035"/>
    <stop offset="1" stop-color="white" stop-opacity=".045"/>
  </linearGradient>
  <radialGradient id="transmission" cx=".5" cy="1.02" r=".7" gradientTransform="translate(0 .36) scale(1 .65)">
    <stop stop-color="{glow}" stop-opacity=".68"/>
    <stop offset="1" stop-color="{glow}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="reflection" cx=".48" cy=".86" r=".54" gradientTransform="translate(0 .064) scale(1 .926)">
    <stop stop-color="{glow}" stop-opacity=".55"/>
    <stop offset=".95" stop-color="{glow}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="rim" x1=".25" y1="0" x2=".75" y2="1">
    <stop stop-color="white" stop-opacity=".94"/>
    <stop offset=".16" stop-color="white" stop-opacity=".5"/>
    <stop offset=".42" stop-color="white" stop-opacity=".07"/>
    <stop offset=".65" stop-color="white" stop-opacity=".19"/>
    <stop offset=".91" stop-color="white" stop-opacity=".85"/>
    <stop offset="1" stop-color="white" stop-opacity=".5"/>
  </linearGradient>
</defs>
<g clip-path="url(#disc)">
  <circle cx="8" cy="8" r="7" fill="{base}"/>
  <circle cx="8" cy="8" r="7" fill="url(#volume)"/>
  <circle cx="8" cy="8" r="7" fill="url(#transmission)"/>
  <circle cx="8" cy="8" r="6.5" fill="url(#reflection)"/>
  <circle cx="8" cy="8" r="6.75" fill="none" stroke="url(#rim)" stroke-width=".5" opacity=".65"/>
  <circle cx="8" cy="8" r="7" fill="black" opacity="{shade}"/>
  <g color="#271e13" fill="currentColor" opacity="{glyph_opacity}">{glyph}</g>
</g>
</svg>'''


def roots(home, installed):
    paths = [REPO / "config/macshell/window-controls",
             REPO / "themes", REPO / "share/macshell/nautilus/themes",
             REPO / "apps/tahoe-photobooth/assets/window-controls"]
    if installed:
        paths += [home / ".config/macshell/window-controls", home / ".themes",
                  home / ".local/share/macshell/nautilus/themes"]
        # A separately checked-out Photo Booth also embeds its own asset copy.
        paths += [home / "Projects/tahoe-photobooth/assets/window-controls"]
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Also refresh existing user-installed asset copies")
    parser.add_argument("--backup-dir", type=Path, required=True, help="New directory for originals and restore manifest")
    args = parser.parse_args()
    args.backup_dir.mkdir(parents=True, exist_ok=False)
    rendered, changes, seen, replacements = {}, [], set(), []
    for root in roots(Path.home(), args.install):
        for path in sorted(root.rglob("titlebutton-*.png")) if root.exists() else []:
            match = NAME.fullmatch(path.name)
            if not match or path.resolve() in seen:
                continue
            seen.add(path.resolve())
            kind, state, dark, double = match.groups()
            key = (kind, state or "", bool(dark), bool(double))
            if key not in rendered:
                size = "32" if double else "16"
                rendered[key] = subprocess.run(
                    ["rsvg-convert", "--width", size, "--height", size],
                    input=artwork(kind, state or "", bool(dark)).encode(),
                    capture_output=True, check=True).stdout
            data = rendered[key]
            original = path.read_bytes()
            if original == data:
                continue
            # Backup by absolute path beneath the backup directory.
            backup = args.backup_dir / path.relative_to(path.anchor)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, backup)
            changes.append({"path": str(path), "backup": str(backup),
                            "before_sha256": hashlib.sha256(original).hexdigest(),
                            "after_sha256": hashlib.sha256(data).hexdigest()})
            replacements.append((path, data))
    # Back up every copy before writing: installations can contain hard links.
    (args.backup_dir / "manifest.json").write_text(json.dumps(changes, indent=2) + "\n")
    for path, data in replacements:
        path.write_bytes(data)
    print(json.dumps({"changed": len(changes), "unique_artwork": len(rendered),
                      "backup": str(args.backup_dir)}, indent=2))


if __name__ == "__main__":
    main()
