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
from functools import lru_cache
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
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, UnidentifiedImageError

ROOT = Path(__file__).resolve().parents[1]
ATTRIBUTE = "user.macshell.folder-customization"
ART_VERSION = "art-v2"
COLORS = ["#ffd43b", "#ff453a", "#ff9f0a", "#30c85a", "#0a84ff", "#bf5af2", "#929296"]
ICON_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


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
    mask, style = value.get("mask", ""), value.get("style", "standard")
    if not isinstance(mask, str) or (mask and not re.fullmatch(r"[0-9a-f]{64}", mask)):
        raise ValueError("Choose an imported PNG mask.")
    if style not in ("standard", "engraved"):
        raise ValueError("Choose Standard or Engraved artwork.")
    if sum(bool(v) for v in (symbol, emoji, mask)) > 1:
        raise ValueError("Choose either a symbol, an emoji, or a PNG mask.")
    result = dict(color=color.lower(), symbol=symbol, emoji=emoji)
    # Keep legacy settings and cache identities stable until a new feature is used.
    if mask:
        result["mask"] = mask
    if style != "standard":
        result["style"] = style
    return result


def mask_path(identity):
    if not re.fullmatch(r"[0-9a-f]{64}", identity):
        raise ValueError("Invalid PNG mask reference.")
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return data / "macshell/folder-masks" / (identity + ".png")


def import_mask(filename):
    path = Path(filename)
    if not path.is_file() or path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("Choose a PNG mask smaller than 16 MiB.")
    try:
        with Image.open(path) as source:
            if source.format != "PNG" or max(source.size) > 4096 or min(source.size) < 1:
                raise ValueError("Choose a PNG mask no larger than 4096 × 4096 pixels.")
            alpha = source.convert("RGBA").getchannel("A")
    except (UnidentifiedImageError, Image.DecompressionBombError) as error:
        raise ValueError("This file is not a readable PNG mask.") from error
    if alpha.getextrema()[0] == 255:
        raise ValueError("The PNG needs a transparent background around the symbol.")
    bounds = alpha.getbbox()
    if not bounds:
        raise ValueError("The PNG mask is empty. Choose a visible symbol on transparency.")
    alpha = alpha.crop(bounds)
    # Store the mask itself, rather than a path that breaks after a move/delete.
    identity = hashlib.sha256(str(alpha.size).encode() + alpha.tobytes()).hexdigest()
    target = mask_path(identity)
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        fd, temporary = tempfile.mkstemp(prefix=".mask-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as output:
                alpha.save(output, format="PNG")
            os.replace(temporary, target)
        finally:
            Path(temporary).unlink(missing_ok=True)
    return identity


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
    # A new renderer gets a new URI, so Qt/GTK cannot reuse the old dark or
    # broken texture. Missing cached artwork is recreated from folder settings.
    try:
        return artwork(state).as_uri() if state else ""
    except (OSError, ValueError, subprocess.SubprocessError):
        # A removed mask/cache must not prevent the rest of a directory listing.
        return ""


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


def folder_svg(color):
    """Tint the bundled folder material while preserving the selected lightness."""
    target_h, target_l, target_s = colorsys.rgb_to_hls(*(int(color[i:i+2], 16) / 255 for i in (1, 3, 5)))

    def tint(match):
        rgb = tuple(int(match[0][i:i+2], 16) / 255 for i in (1, 3, 5))
        h, lightness, saturation = colorsys.rgb_to_hls(*rgb)
        if not (0.46 <= h <= 0.69 and saturation > .2):
            return match[0]  # retain the paper lip, shadows and highlights
        lightness = max(.04, min(.98, target_l + (lightness - .52) * .72))
        rgb = colorsys.hls_to_rgb(target_h, lightness, target_s * .95)
        return "#" + "".join(f"{round(c * 255):02x}" for c in rgb)

    template = (ROOT / "assets/folder.svg").read_text()
    template = re.sub(r"#[0-9a-fA-F]{6}(?![0-9a-fA-F])", tint, template)
    return template.replace('width="64" height="64"', 'width="256" height="256"')


@lru_cache(maxsize=1)
def emoji_font():
    """Choose one usable color font for both the picker and exported artwork.

    The Linux Apple font has a 96px bitmap strike; Noto has a 109px strike.
    Fontconfig can silently substitute another family, so verify the match.
    """
    for family, size in (("Apple Color Emoji", 96), ("Noto Color Emoji", 109)):
        try:
            result = subprocess.run(["fc-match", "-f", "%{family[0]}\n%{file}", family],
                                    capture_output=True, text=True, check=True, timeout=5)
            matched, filename = result.stdout.strip().split("\n", 1)
            if matched != family:
                continue
            path = Path(filename)
            font = ImageFont.truetype(str(path), size)
            return family, path, font
        except (OSError, ValueError, subprocess.SubprocessError):
            continue
    return None


def render(value, size=256):
    if size not in (16, 32, 64, 128, 256, 512, 1024):
        raise ValueError("Unsupported icon resolution.")
    value = normalize(value)
    color = value["color"]
    # Use the same folder geometry/material as the rest of MacShell.
    emblem = ""
    if value["symbol"] and value.get("style") != "engraved":
        lightness = colorsys.rgb_to_hls(*(int(color[i:i+2], 16) / 255 for i in (1, 3, 5)))[1]
        ink = shade(color, min(.9, lightness + .38) if lightness < .33 else max(.12, lightness - .19))
        svg = next(s["svg"] for s in symbols() if s["id"] == value["symbol"])
        # Padding keeps cap/join extents and fine marks inside the viewport.
        svg = svg.replace('viewBox="0 0 24 24"', 'viewBox="-2 -2 28 28"')
        svg = svg.replace('<svg ', '<svg x="88" y="104" width="80" height="80" ')
        emblem = '<g opacity="0.68">' + svg.replace("$COLOR", ink) + '</g>'
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
{folder_svg(color)}{emblem}</svg>'''
    # Supersample SVG details, then downsample once with premultiplied alpha.
    result = subprocess.run(["rsvg-convert", "--width", str(size * 2), "--height", str(size * 2)],
                            input=svg.encode(), capture_output=True, check=True, timeout=10)
    image = Image.open(io.BytesIO(result.stdout)).convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    if value.get("mask") or (value["symbol"] and value.get("style") == "engraved"):
        scale = size / 256
        if value.get("mask"):
            try:
                with Image.open(mask_path(value["mask"])) as stored:
                    mark = stored.convert("L")
            except OSError as error:
                raise ValueError("The saved PNG mask is missing. Import the mask again.") from error
            box = (max(1, round(144 * scale)), max(1, round(82 * scale)))
            ratio = min(box[0] / mark.width, box[1] / mark.height)
            mark = mark.resize((max(1, round(mark.width * ratio)), max(1, round(mark.height * ratio))), Image.Resampling.LANCZOS)
        else:
            svg = next(s["svg"] for s in symbols() if s["id"] == value["symbol"])
            svg = svg.replace('viewBox="0 0 24 24"', 'viewBox="-2 -2 28 28"').replace("$COLOR", "#000000")
            result = subprocess.run(["rsvg-convert", "--width", str(max(1, round(80 * scale))),
                                     "--height", str(max(1, round(80 * scale)))],
                                    input=svg.encode(), capture_output=True, check=True, timeout=10)
            mark = Image.open(io.BytesIO(result.stdout)).convert("RGBA").getchannel("A")
        alpha = Image.new("L", image.size)
        alpha.paste(mark, ((size - mark.width) // 2, round(145 * scale - mark.height / 2)))
        lightness = colorsys.rgb_to_hls(*(int(color[i:i+2], 16) / 255 for i in (1, 3, 5)))[1]
        ink = shade(color, min(.9, lightness + .38) if lightness < .33 else max(.12, lightness - .19))
        if value.get("style") == "engraved":
            # Folderify's visual model: inset fill plus opposing edge highlights.
            # Portable Pillow implementation; no iconutil, Cocoa or bundled Apple assets.
            shift = max(1, round(scale))
            down = Image.new("L", image.size); down.paste(alpha, (0, shift))
            up = Image.new("L", image.size); up.paste(alpha, (0, -shift))
            highlight = ImageChops.subtract(down, alpha).filter(ImageFilter.GaussianBlur(.4 * scale))
            shadow = ImageChops.subtract(up, alpha).filter(ImageFilter.GaussianBlur(.35 * scale))
            for tint, opacity, layer in [("#ffffff", .55, highlight), ("#000000", .23, shadow), (ink, .5, alpha)]:
                overlay = Image.new("RGBA", image.size, tint)
                overlay.putalpha(layer.point(lambda pixel: round(pixel * opacity)))
                image.alpha_composite(overlay)
        else:
            overlay = Image.new("RGBA", image.size, ink)
            overlay.putalpha(alpha.point(lambda pixel: round(pixel * .68)))
            image.alpha_composite(overlay)
    if value["emoji"]:
        selected = emoji_font()
        if selected is None:
            raise ValueError("Install Apple Color Emoji or Noto Color Emoji to use emoji on folders.")
        font = selected[2]
        emoji = Image.new("RGBA", (320, 160))
        draw = ImageDraw.Draw(emoji)
        draw.text((5, 0), value["emoji"], font=font, embedded_color=True)
        bounds = emoji.getbbox()
        if not bounds:
            raise ValueError("This emoji is unavailable in the installed emoji font.")
        emoji = emoji.crop(bounds)
        emoji = emoji.resize((max(1, round(emoji.width * size / 256)), max(1, round(emoji.height * size / 256))), Image.Resampling.LANCZOS)
        emoji.thumbnail((max(1, round(84 * size / 256)), max(1, round(82 * size / 256))), Image.Resampling.LANCZOS)
        image.alpha_composite(emoji, ((size-emoji.width)//2, round(145 * size / 256)-emoji.height//2))
    return image


def export_iconset(value, directory):
    """Export native-sized PNGs; leave .icns conversion to macOS tools."""
    value = normalize(value)
    directory = Path(directory).absolute()
    if directory.is_symlink() or not directory.is_dir() or not os.access(directory, os.W_OK):
        raise ValueError("Choose a writable local export folder.")
    # Every export gets its own folder. Never replace an existing iconset.
    target = Path(tempfile.mkdtemp(prefix="MacShell-", suffix=".iconset", dir=directory))
    try:
        for base, retina in ICON_SIZES:
            name = f"icon_{base}x{base}" + ("@2x" if retina == 2 else "") + ".png"
            render(value, base * retina).save(target / name, format="PNG")
    except Exception:
        import shutil
        shutil.rmtree(target)
        raise
    return target


def artwork_path(value, version=ART_VERSION):
    value = normalize(value)
    data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    identity = ""
    if value["emoji"] and version != "art-v1":
        selected = emoji_font()
        if selected:
            family, path, _ = selected
            info = path.stat()
            identity = f"{family}:{path}:{info.st_size}:{info.st_mtime_ns}"
    digest = hashlib.sha256((json.dumps(value, sort_keys=True) + version + identity).encode()).hexdigest()
    return data / "macshell/folder-icons" / (digest + ".png")


def artwork(value):
    value = normalize(value)
    target = artwork_path(value, ART_VERSION)
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
        selected = emoji_font()
        warning = ""
        try:
            icon = artwork(value)
        except ValueError as error:
            if not value.get("mask"):
                raise
            warning = str(error)
            icon = artwork({key: entry for key, entry in value.items() if key != "mask"})
        return dict(event="state", path=str(self.path), name=self.path.name or "/",
                    settings=value, customized=bool(state), icon=icon.as_uri(), symbols=symbols(), warning=warning,
                    emojiFontFamily=selected[0] if selected else "Noto Color Emoji",
                    emojiFontUrl=selected[1].as_uri() if selected else "")

    def repair_artwork(self):
        """Migrate saved folders to the new texture URI, retaining original icons."""
        state = read_state(self.path)
        if not state or state.get("icon") == str(artwork(state)):
            return False
        self.refresh_legacy_cache()
        self.apply(normalize(state))
        return True

    def refresh_legacy_cache(self):
        """Repair owned v1 PNGs even when the current session cannot reach GVfs."""
        state = read_state(self.path)
        if not state or state.get("icon") != str(artwork_path(state, "art-v1")):
            return False
        legacy = artwork_path(state, "art-v1")
        data = artwork(state).read_bytes()
        if legacy.is_file() and legacy.read_bytes() == data:
            return False
        fd, name = tempfile.mkstemp(prefix=".folder-repair-", dir=legacy.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            os.replace(name, legacy)
        finally:
            if os.path.exists(name):
                os.unlink(name)
        return True

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
            # xattr changes emit IN_ATTRIB for the desktop's directory watch;
            # preserve the folder's content-modification timestamp.
            return self.status()
        finally:
            os.close(fd)


def serve(folder):
    repair_error = ""
    try:
        folder.repair_artwork()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Still show the corrected preview and allow retrying if GVfs is down.
        repair_error = str(error)
    print(json.dumps(folder.status()), flush=True)
    if repair_error:
        print(json.dumps(dict(event="error", message=repair_error)), flush=True)
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
            elif action == "import-mask":
                value = normalize(request.get("settings", folder.status()["settings"]))
                value.update(mask=import_mask(request["path"]), symbol="", emoji="", style="engraved")
                response = folder.apply(value)
            elif action == "export-iconset":
                target = export_iconset(request["settings"], request["directory"])
                response = dict(event="exported", path=str(target), uri=target.as_uri())
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
    parser.add_argument("--repair-cache", action="store_true")
    parser.add_argument("--mask", help="Import a transparent PNG mask and apply an engraved icon")
    parser.add_argument("--style", choices=("standard", "engraved"))
    parser.add_argument("--export-iconset", metavar="DIRECTORY", help="Export ten PNG representations to a new .iconset folder")
    args = parser.parse_args()
    try:
        folder = Folder(args.folder)
        if args.serve:
            serve(folder)
        elif args.repair_cache:
            print(json.dumps(dict(event="repaired", changed=folder.refresh_legacy_cache())))
        elif args.clear:
            print(json.dumps(folder.apply(clear=True)))
        elif args.color or args.mask or args.style or args.export_iconset:
            settings = folder.status()["settings"]
            if args.color:
                settings["color"] = args.color
            if args.style:
                settings["style"] = args.style
            if args.mask:
                settings.update(mask=import_mask(args.mask), symbol="", emoji="", style=args.style or "engraved")
            if args.export_iconset:
                target = export_iconset(settings, args.export_iconset)
                print(json.dumps(dict(event="exported", path=str(target), uri=target.as_uri())))
            else:
                print(json.dumps(folder.apply(settings)))
        else:
            print(json.dumps(folder.status()))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(event="error", message=str(error))), flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
