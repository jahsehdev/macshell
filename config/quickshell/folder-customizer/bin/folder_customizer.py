#!/usr/bin/env python3
"""Per-folder artwork shared by the desktop and Files. JSON-lines worker/CLI.

Settings live on the directory (xattr), so a rename never keys them to an old
path. Exported PNGs are immutable and stay in XDG_DATA_HOME for GIO consumers.
No shell evaluation and no hidden files are added to customized directories.
"""
import argparse
import colorsys
import errno
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unicodedata
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ATTRIBUTE = "user.macshell.folder-customization"
COLORS = ["#ffd43b", "#ff453a", "#ff9f0a", "#30c85a", "#0a84ff", "#bf5af2", "#929296"]


def symbols():
    return json.loads((ROOT / "symbols.json").read_text())


def normalize(value):
    color = value.get("color", "#0a84ff")
    if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError("Choose a six-digit folder color, such as #ffd43b.")
    symbol, emoji = value.get("symbol", ""), value.get("emoji", "")
    if symbol not in ("", *(s["id"] for s in symbols())):
        raise ValueError("Unknown folder symbol.")
    if not isinstance(emoji, str) or len(emoji) > 32 or any(
            unicodedata.category(c) in ("Cc", "Cs") for c in emoji):
        raise ValueError("Choose a valid emoji.")
    if symbol and emoji:
        raise ValueError("Choose either a symbol or an emoji.")
    return dict(color=color.lower(), symbol=symbol, emoji=emoji)


def read_state(path):
    try:
        state = json.loads(os.getxattr(path, ATTRIBUTE))
        if state.get("version") != 1:
            return {}
        normalize(state)
        return state
    except OSError as error:
        if error.errno in (errno.ENODATA, errno.ENOTSUP, errno.ENOENT, errno.EACCES):
            return {}
        raise
    except (ValueError, AttributeError, TypeError):
        return {}


def custom_icon(path):
    """Cheap read for directory listings; no GIO process for every folder."""
    state = read_state(path)
    icon = state.get("icon", "")
    return Path(icon).as_uri() if isinstance(icon, str) and Path(icon).is_absolute() and Path(icon).is_file() else ""


def default_color():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    try:
        color = json.loads((config / "macshell/folders/native-state.json").read_text())["folderColor"]
        return normalize({"color": color})["color"]
    except (OSError, ValueError, KeyError, TypeError):
        return "#0a84ff"


def shade(color, lightness):
    h, _, s = colorsys.rgb_to_hls(*(int(color[i:i+2], 16) / 255 for i in (1, 3, 5)))
    return "#" + "".join(f"{round(c * 255):02x}" for c in colorsys.hls_to_rgb(h, lightness, s))


def render(value):
    value = normalize(value)
    color = value["color"]
    # Original layered folder artwork, with a paper lip and a restrained emboss.
    emblem = ""
    if value["symbol"]:
        svg = next(s["svg"] for s in symbols() if s["id"] == value["symbol"])
        svg = svg.replace('<svg ', '<svg x="88" y="104" width="80" height="80" ')
        emblem = '<g opacity="0.55">' + svg.replace("$COLOR", shade(color, 0.31)) + '</g>'
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<defs><linearGradient id="back" x2="0" y2="1"><stop stop-color="{shade(color, .66)}"/><stop offset="1" stop-color="{shade(color, .40)}"/></linearGradient>
<linearGradient id="front" x2="0" y2="1"><stop stop-color="{shade(color, .68)}"/><stop offset=".18" stop-color="{shade(color, .56)}"/><stop offset="1" stop-color="{shade(color, .45)}"/></linearGradient></defs>
<rect x="18" y="65" width="220" height="146" rx="14" fill="#000" opacity=".08"/>
<path d="M18 61Q18 47 32 47H84Q91 47 97 53L108 63H224Q238 63 238 77V194Q238 208 224 208H32Q18 208 18 194Z" fill="url(#back)"/>
<rect x="27" y="76" width="202" height="122" rx="5" fill="#fff" opacity=".9"/>
<rect x="18" y="84" width="220" height="124" rx="12" fill="url(#front)"/>
<path d="M30 85H226Q237 85 237 97" fill="none" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>
<path d="M30 207H226" stroke="#000" stroke-opacity=".12" stroke-width="2"/>{emblem}</svg>'''
    result = subprocess.run(["rsvg-convert"], input=svg.encode(), capture_output=True, check=True, timeout=10)
    image = Image.open(io.BytesIO(result.stdout)).convert("RGBA")
    if value["emoji"]:
        result = subprocess.run(["fc-match", "-f", "%{file}", "Noto Color Emoji"],
                                capture_output=True, text=True, check=True, timeout=5)
        font = ImageFont.truetype(result.stdout, 109)
        emoji = Image.new("RGBA", (320, 160))
        draw = ImageDraw.Draw(emoji)
        draw.text((5, 0), value["emoji"], font=font, embedded_color=True)
        bounds = emoji.getbbox()
        if not bounds:
            raise ValueError("This emoji is unavailable in the installed emoji font.")
        emoji = emoji.crop(bounds)
        emoji.thumbnail((84, 82), Image.Resampling.LANCZOS)
        image.alpha_composite(emoji, ((256-emoji.width)//2, 145-emoji.height//2))
    return image


def artwork(value):
    value = normalize(value)
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    digest = hashlib.sha256((json.dumps(value, sort_keys=True) + "art-v1").encode()).hexdigest()
    target = data / "macshell/folder-icons" / (digest + ".png")
    if not target.is_file():
        image = render(value)
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix=".folder-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                image.save(stream, format="PNG")
            os.replace(name, target)
        finally:
            if os.path.exists(name):
                os.unlink(name)
    return target


class Metadata:
    def get(self, path):
        result = subprocess.run(["gio", "info", "-a", "metadata::custom-icon", "--", str(path)],
                                capture_output=True, text=True, check=True, timeout=5)
        for line in result.stdout.splitlines():
            if line.strip().startswith("metadata::custom-icon:"):
                return line.split("metadata::custom-icon:", 1)[1].strip()
        return ""

    def set(self, path, value):
        args = ["gio", "set", "-t", "string" if value else "unset", "--", str(path), "metadata::custom-icon"]
        if value:
            args.append(value)
        result = subprocess.run(args, capture_output=True, text=True, timeout=5)
        if result.returncode:
            raise OSError(result.stderr.strip() or "Could not update the folder icon in Files.")


class Folder:
    def __init__(self, path, metadata=None):
        self.path = Path(path).absolute()
        if self.path.is_symlink() or not self.path.is_dir():
            raise ValueError("Choose a local folder, rather than a file or symbolic link.")
        if not os.access(self.path, os.W_OK):
            raise PermissionError("You do not have permission to customize this folder.")
        self.metadata = metadata or Metadata()

    def status(self):
        state = read_state(self.path)
        value = normalize(state or {"color": default_color()})
        return dict(event="state", path=str(self.path), name=self.path.name or "/",
                    settings=value, customized=bool(state), icon=artwork(value).as_uri(), symbols=symbols())

    def apply(self, value=None, clear=False):
        # Serialize independent panels operating on the same directory.
        fd = os.open(self.path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            old = read_state(self.path)
            if clear and not old:
                return self.status()
            before = self.metadata.get(self.path)
            if clear:
                self.metadata.set(self.path, old.get("previousIcon", ""))
                try:
                    os.removexattr(fd, ATTRIBUTE)
                except OSError:
                    self.metadata.set(self.path, before)
                    raise
            else:
                value = normalize(value or {})
                icon = artwork(value)
                state = dict(value, version=1, previousIcon=old.get("previousIcon", before), icon=str(icon))
                # Check xattr support before committing the GIO icon. On failure,
                # put the old attribute back; a half-applied icon is never success.
                os.setxattr(fd, ATTRIBUTE, json.dumps(state).encode())
                try:
                    self.metadata.set(self.path, icon.as_uri())
                except (OSError, subprocess.SubprocessError):
                    if old:
                        os.setxattr(fd, ATTRIBUTE, json.dumps(old).encode())
                    else:
                        os.removexattr(fd, ATTRIBUTE)
                    raise
            # The desktop's parent-directory inotify watch observes IN_ATTRIB.
            os.utime(fd, None)
            return self.status()
        finally:
            os.close(fd)


def serve(folder):
    print(json.dumps(folder.status()), flush=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            action = request.get("action")
            if action == "apply":
                response = folder.apply(request["settings"])
            elif action == "clear":
                response = folder.apply(clear=True)
            elif action == "preview":
                response = dict(event="preview", icon=artwork(request["settings"]).as_uri())
            elif action == "refresh":
                response = folder.status()
            else:
                raise ValueError("Unknown folder customization action.")
            print(json.dumps(response), flush=True)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
            print(json.dumps(dict(event="error", message=str(error))), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", required=True)
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--color")
    parser.add_argument("--clear", action="store_true")
    args = parser.parse_args()
    try:
        folder = Folder(args.folder)
        if args.serve:
            serve(folder)
        elif args.clear:
            print(json.dumps(folder.apply(clear=True)))
        elif args.color:
            settings = folder.status()["settings"]
            settings["color"] = args.color
            print(json.dumps(folder.apply(settings)))
        else:
            print(json.dumps(folder.status()))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(event="error", message=str(error))), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
