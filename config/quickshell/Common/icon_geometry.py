"""Measure icon artwork without changing installed assets or their aspect ratios."""
import configparser
from io import BytesIO
import json
import os
from pathlib import Path
import subprocess

from PIL import Image


def visible_ratio(path):
    if path.suffix.lower() == ".svg":
        result = subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", str(path)],
                                capture_output=True, check=True, timeout=5)
        image = Image.open(BytesIO(result.stdout))
    else:
        image = Image.open(path)
    with image:
        alpha = image.convert("RGBA").getchannel("A")
        # Ignore the soft shadow; match the visible plate rather than its canvas.
        bounds = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
        if bounds is None:
            bounds = alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
        if bounds is None:
            return 1.0
        return max(bounds[2] - bounds[0], bounds[3] - bounds[1]) / max(image.size)


def geometry(home, config, data, theme, overrides):
    names = {"view-app-grid", "application-x-executable", "systemsettings",
             "preferences-system", "user-trash", "user-trash-full"}
    direct = {}
    for root in (data / "applications", Path("/usr/share/applications"),
                 data / "flatpak/exports/share/applications", Path("/var/lib/flatpak/exports/share/applications")):
        for entry in root.glob("*.desktop"):
            for line in entry.read_text(errors="replace").splitlines():
                if line.startswith("Icon="):
                    name = line[5:].strip()
                    if name.startswith("/"):
                        direct[name] = Path(name)
                    elif name:
                        names.add(name)
    roots = (data / "icons", home / ".icons", Path("/usr/local/share/icons"), Path("/usr/share/icons"))
    sources, visited = dict(direct), set()

    def visit(name):
        if name in visited:
            return
        visited.add(name)
        inherited = []
        for root in roots:
            folder = root / name
            index = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                index_path = next((candidate / name / "index.theme" for candidate in roots
                                   if (candidate / name / "index.theme").is_file()), folder / "index.theme")
                index.read(folder / "index.theme" if (folder / "index.theme").is_file() else index_path)
                directories = index.get("Icon Theme", "Directories", fallback="").split(",")
                directories.sort(key=lambda key: index.getint(key, "Size", fallback=0), reverse=True)
                directories.sort(key=lambda key: "symbolic" in key)
                for directory in directories:
                    if not directory:
                        continue
                    for path in (folder / directory).glob("*"):
                        if path.stem in names and path.stem not in sources and path.suffix in (".png", ".svg", ".xpm"):
                            sources[path.stem] = path
                inherited.extend(index.get("Icon Theme", "Inherits", fallback="").split(","))
            except (OSError, configparser.Error, ValueError):
                continue
        for parent in inherited:
            if parent.strip():
                visit(parent.strip())

    visit(theme)
    visit("hicolor")
    for name in names - sources.keys():
        for root in (data / "pixmaps", Path("/usr/share/pixmaps")):
            for suffix in (".png", ".svg", ".xpm"):
                path = root / (name + suffix)
                if path.is_file():
                    sources.setdefault(name, path)
    sources.update({name: Path(path) for name, path in overrides.items()})
    cache_path = config / "macshell/icon-geometry-cache.json"
    try:
        cache = json.loads(cache_path.read_text())
    except (OSError, ValueError):
        cache = {}
    ratios = {}
    for name, path in sources.items():
        try:
            real = path.resolve(strict=True)
            stat = real.stat()
            signature = [stat.st_mtime_ns, stat.st_size]
            saved = cache.get(str(real), {})
            ratio = saved.get("ratio") if saved.get("signature") == signature else visible_ratio(real)
            cache[str(real)] = {"signature": signature, "ratio": ratio}
            ratios[name] = ratio
            ratios[str(path)] = ratio
            ratios[str(real)] = ratio
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temp = cache_path.with_suffix(f".{os.getpid()}.tmp")
    temp.write_text(json.dumps(cache))
    temp.replace(cache_path)
    return ratios
