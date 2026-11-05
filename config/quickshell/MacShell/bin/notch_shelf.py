#!/usr/bin/env python3
"""Inspect local Shelf references. This module never copies or deletes user files."""
import json
import mimetypes
from pathlib import Path
import subprocess
import sys
from urllib.parse import unquote, urlsplit


def local_path(value):
    if not isinstance(value, str) or not value or "\x00" in value:
        raise ValueError("Invalid file reference")
    parsed = urlsplit(value)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost") or parsed.query or parsed.fragment:
        raise ValueError("Shelf accepts local files and folders only")
    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        raise ValueError("The file path must be absolute")
    if not path.exists():
        raise ValueError(f"File is no longer available: {path.name}")
    if not path.is_file() and not path.is_dir():
        raise ValueError("Only regular files and folders can be added")
    return path


def inspect(values):
    items, errors, seen = [], [], set()
    for value in values[:100]:
        try:
            path = local_path(value)
            url = path.as_uri()
            if url in seen:
                continue
            seen.add(url)
            folder = path.is_dir()
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            items.append({"url": url, "name": path.name or str(path), "folder": folder,
                          "size": 0 if folder else path.stat().st_size, "image": not folder and mime.startswith("image/")})
        except (ValueError, OSError) as error:
            errors.append(str(error))
    return {"items": items, "errors": errors}


def main():
    try:
        action, payload = sys.argv[1:3]
        if action == "inspect":
            values = json.loads(payload)
            if not isinstance(values, list):
                raise ValueError("Expected a list of file URLs")
            result = inspect(values)
        elif action == "open":
            path = local_path(payload)
            subprocess.Popen(["xdg-open", path.as_uri()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            result = {"ok": True}
        else:
            raise ValueError("Unknown Shelf action")
    except (ValueError, OSError) as error:
        result = {"errors": [str(error)]}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
