#!/usr/bin/env python3
"""Cache a full-resolution, smoothly blurred static Launchpad wallpaper."""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import unquote, urlparse

from PIL import Image, ImageFilter, ImageOps


def render(source, width, height, radius, cache_home=None):
    parsed = urlparse(source)
    if parsed.scheme and (parsed.scheme != "file" or parsed.netloc not in ("", "localhost")):
        raise ValueError("Launchpad wallpaper must be a local image")
    path = Path(unquote(parsed.path) if parsed.scheme == "file" else source).expanduser().resolve(strict=True)
    if not 1 <= width <= 8192 or not 1 <= height <= 8192 or width * height > 40_000_000:
        raise ValueError("Invalid wallpaper render size")
    if not math.isfinite(radius) or not 0 <= radius <= 512:
        raise ValueError("Invalid wallpaper blur radius")
    stat = path.stat()
    signature = json.dumps([3, str(path), stat.st_mtime_ns, stat.st_size, width, height, round(radius, 3)])
    key = hashlib.sha256(signature.encode()).hexdigest()
    cache = Path(cache_home or os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "macshell/launchpad-backdrops"
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / (key + ".png")
    if destination.is_file():
        return destination
    # Several shell surfaces request the same wallpaper. Only one renders it;
    # others reuse the completed PNG after acquiring the lock.
    with (cache / ".render.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if destination.is_file():
            return destination
        with Image.open(path) as original:
            image = ImageOps.fit(ImageOps.exif_transpose(original).convert("RGB"),
                                 (width, height), method=Image.Resampling.LANCZOS)
            if radius:
                image = image.filter(ImageFilter.GaussianBlur(radius))
        descriptor, temporary = tempfile.mkstemp(prefix=".wallpaper-", suffix=".png", dir=cache)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                image.save(stream, format="PNG", compress_level=2)
            os.replace(temporary, destination)
        finally:
            Path(temporary).unlink(missing_ok=True)
        old = sorted(cache.glob("*.png"), key=lambda entry: entry.stat().st_mtime, reverse=True)
        for entry in old[24:]:
            if entry != destination:
                entry.unlink(missing_ok=True)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("width", type=int)
    parser.add_argument("height", type=int)
    parser.add_argument("radius", type=float)
    args = parser.parse_args()
    try:
        result = render(args.source, args.width, args.height, args.radius)
        print(json.dumps({"url": result.as_uri()}), flush=True)
    except (OSError, ValueError, Image.DecompressionBombError) as error:
        print(f"launchpad wallpaper: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
