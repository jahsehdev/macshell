#!/usr/bin/env python3
"""Resolve MPRIS metadata against LRCLIB; stdout is one JSON result."""
import json
import hashlib
import re
import sys
import time
import unicodedata
from difflib import SequenceMatcher
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

USER_AGENT = "MacShell/1.0 (https://github.com/jahsehdev/macshell)"
DECORATION = re.compile(
    r"\s*[\[(][^\])]*\b(?:official|lyrics?|audio|video|visuali[sz]er|remaster(?:ed)?|hd|4k)\b[^\])]*[\])]"
    r"|\s*[-–—]\s*(?:official\b.*|lyrics?\b.*|\d{4}\s+remaster.*|remaster.*)$", re.I)


def clean(value):
    return re.sub(r"\s+", " ", DECORATION.sub("", value or "")).strip()


def normalized(value):
    value = unicodedata.normalize("NFKD", clean(value)).casefold()
    return " ".join(re.findall(r"[^\W_]+", value, re.UNICODE))


def metadata(title, artist):
    title, artist = clean(title), clean(artist)
    # Browser players often expose the channel as artist, with both names in title.
    parts = re.split(r"\s+[-–—]\s+", title, maxsplit=1)
    if len(parts) == 2 and (not artist or normalized(parts[0]) == normalized(artist)
                           or re.search(r"(?:vevo|topic)$", artist, re.I)):
        artist, title = parts
    artist = re.sub(r"\s*(?:[-–—]\s*Topic|VEVO)$", "", artist, flags=re.I).strip()
    return title, artist


def pick(records, title, artist, album, duration, synced_only=False):
    ranked = []
    for record in records:
        if not isinstance(record, dict) or record.get("instrumental"):
            continue
        if not (record.get("syncedLyrics") or record.get("plainLyrics")):
            continue
        title_match = SequenceMatcher(None, normalized(title), normalized(record.get("trackName", ""))).ratio()
        artist_match = SequenceMatcher(None, normalized(artist), normalized(record.get("artistName", ""))).ratio() if artist else 1
        if title_match < .80 or artist_match < .50:
            continue
        delta = abs(float(record.get("duration") or 0) - duration) if duration else 0
        if synced_only and (not record.get("syncedLyrics") or (duration and delta > max(5, duration * .03))):
            continue
        score = title_match * 6 + artist_match * 3
        score += .6 if normalized(album) and normalized(album) == normalized(record.get("albumName", "")) else 0
        score += max(0, 1 - delta / 20) if duration else 0
        score += .35 if record.get("syncedLyrics") else 0
        ranked.append((score, record))
    return max(ranked, key=lambda item: item[0])[1] if ranked else None


def request(endpoint, params):
    req = Request("https://lrclib.net/api/" + endpoint + "?" + urlencode(params),
                  headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(req, timeout=7) as response:
        return json.load(response)


def lookup(title, artist, album="", duration=0, fetch=request, pause=time.sleep):
    title, artist = metadata(title, artist)
    if not title:
        return {"state": "none"}
    params = {"track_name": title}
    if artist:
        params["artist_name"] = artist
    exact = dict(params)
    if album.strip():
        exact["album_name"] = album.strip()
    if 1 <= duration <= 3600:
        exact["duration"] = round(duration)
    attempts = ([("get", exact)] if artist else []) + [("search", params)]
    # A title-only fallback tolerates multiple artists and browser channel names;
    # local ranking still rejects records belonging to a different artist.
    if artist:
        attempts.append(("search", {"track_name": title}))
    failed = False
    fallback = None
    for index, (endpoint, query) in enumerate(attempts):
        if index:
            pause(.25)
        try:
            result = fetch(endpoint, query)
            if endpoint == "get" and isinstance(result, dict):
                if result.get("instrumental"):
                    return {"state": "none", "instrumental": True}
                if result.get("syncedLyrics"):
                    return result
                if result.get("plainLyrics"):
                    fallback = result
            elif isinstance(result, list):
                synced = pick(result, title, artist, album, duration, synced_only=True)
                if synced:
                    return synced
                match = pick(result, title, artist, album, duration)
                if match and fallback is None:
                    fallback = match
            else:
                failed = True
        except HTTPError as error:
            error.close()
            if error.code in (429, 503):
                # End this lookup rather than issuing fallback requests while throttled.
                delay = error.headers.get("Retry-After", "60")
                try:
                    delay = max(1, int(delay))
                except ValueError:
                    try:
                        delay = max(1, int(parsedate_to_datetime(delay).timestamp() - time.time()) + 1)
                    except (ValueError, TypeError, OverflowError):
                        delay = 60
                return dict(fallback or {"state": "error"}, retryAfter=delay)
            if error.code not in (400, 404):
                failed = True
        except (URLError, TimeoutError, OSError, ValueError):
            failed = True
    return fallback or {"state": "error" if failed else "none"}


def cached_lookup(title, artist, album="", duration=0, cache_dir=None, resolve=lookup):
    """Cache successful lyrics only; a missing track can become available later."""
    cache = None
    stale_plain = None
    if cache_dir:
        key = hashlib.sha256(json.dumps([title, artist, album, duration], ensure_ascii=False).encode()).hexdigest()
        cache = Path(cache_dir) / (key + ".json")
        try:
            data = json.loads(cache.read_text())
            age = time.time() - cache.stat().st_mtime
            if data.get("syncedLyrics") and age < 30 * 86400:
                return {key: value for key, value in data.items() if key != "_syncSearchVersion"}
            if data.get("plainLyrics"):
                stale_plain = {key: value for key, value in data.items() if key != "_syncSearchVersion"}
            if data.get("plainLyrics") and data.get("_syncSearchVersion") == 1 and age < 86400:
                return {key: value for key, value in data.items() if key != "_syncSearchVersion"}
        except (OSError, ValueError, AttributeError):
            pass
    result = resolve(title, artist, album, duration)
    if stale_plain and not (result.get("syncedLyrics") or result.get("plainLyrics")):
        result = dict(stale_plain, **({"retryAfter": result["retryAfter"]} if result.get("retryAfter") else {}))
    if cache and (result.get("syncedLyrics") or result.get("plainLyrics")):
        try:
            cache.parent.mkdir(parents=True, exist_ok=True)
            temporary = cache.with_suffix(".tmp")
            # Old plain-only caches were saved before trying synchronized search.
            saved = dict(result, _syncSearchVersion=1)
            saved.pop("retryAfter", None)
            temporary.write_text(json.dumps(saved, ensure_ascii=False))
            temporary.replace(cache)
        except OSError:
            pass
    return result


if __name__ == "__main__":
    try:
        seconds = float(sys.argv[4])
    except (IndexError, ValueError):
        seconds = 0
    cache_dir = sys.argv[5] if len(sys.argv) > 5 else None
    print(json.dumps(cached_lookup(*(sys.argv[1:4]), duration=seconds, cache_dir=cache_dir), ensure_ascii=False))
