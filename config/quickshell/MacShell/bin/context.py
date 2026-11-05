#!/usr/bin/env python3
"""MacShell personal context (A3): a local index over enabled sources.

One-shot CLI, JSON on stdout, everything offline. This is the foundation the
Luma context stage (GG-04) builds on: a fixture-folder file index plus source
contracts for MacShell Notes, Calendar and Mail, with per-source enable/disable
controls and full provenance on every indexed item.

  context.py sources
  context.py enable --kind KIND        (files | notes | calendar | mail)
  context.py disable --kind KIND
  context.py configure --kind files --folders "/path,/path"   (fixture folders)
  context.py index [--full]
  context.py search --query "..." [--kind KIND] [--limit N]
  context.py forget --kind KIND
  context.py contract                  (the source contracts, as JSON)

Storage: ~/.local/share/macshell/context/context.db

Sources
  files     the "fixture folders": text files under user-configured folders.
            Nothing is indexed until folders are configured. Hidden entries,
            known dependency/cache directories, binary blobs and huge files
            are skipped. Incremental by (path, mtime); --full re-reads.
  notes     read through the Notes CLI contract: bin/notes.py `list` for ids,
            `get --id` for title/body. ref = note id.
  calendar  read through the Calendar CLI contract: bin/calendar.py `events`
            over a −30…+90 day window. ref = event id (+ occurrence).
  mail      imported messages and drafts from the local MacShell Mail store.

Provenance: every item row stores {"kind", "ref", "origin" (path or app db),
"modified", "indexed_at", "indexer"} and search results echo it verbatim, so
answers built on this index can cite where each fact came from.

Controls: a source that is disabled is skipped by both `index` and `search` —
disabled sources are not indexed (GG-04 acceptance criterion).
"""

import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
NOTES_PY = HERE / "notes.py"
CALENDAR_PY = HERE / "calendar.py"

KINDS = ("files", "notes", "calendar", "mail")
KIND_LABEL = {"files": "Files", "notes": "Notes", "calendar": "Calendar", "mail": "Mail"}
INDEXER = "macshell-context/1"

# Files: text-ish extensions worth indexing; anything else needs a sniff pass.
TEXT_EXTENSIONS = {".txt", ".md", ".markdown", ".rst", ".log", ".csv", ".tsv",
                   ".json", ".yaml", ".yml", ".toml", ".ini", ".conf", ".cfg",
                   ".html", ".htm", ".css", ".js", ".mjs", ".cjs", ".ts", ".jsx", ".tsx",
                   ".py", ".qml", ".lua", ".sh", ".bash", ".zsh", ".fish",
                   ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java", ".kt", ".swift",
                   ".sql", ".xml", ".svg", ".desktop", ".service", ".lua"}
SKIP_DIRS = {"node_modules", "__pycache__", ".git", ".svn", ".hg",
             "venv", ".venv", "env", ".cache", ".npm", ".cargo", "target", "build",
             "dist", ".tox", ".mypy_cache", ".pytest_cache", ".idea", ".vscode"}
MAX_FILE_BYTES = 512 * 1024          # read at most the first 512 KB of a file
MAX_BODY_CHARS = 20000               # and keep at most this many body characters
SNIFF_BYTES = 4096

SCHEMA = """
CREATE TABLE IF NOT EXISTS sources (
    kind     TEXT PRIMARY KEY,
    enabled  INTEGER NOT NULL DEFAULT 0,
    config   TEXT NOT NULL DEFAULT '{}',
    updated  REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS items (
    id          INTEGER PRIMARY KEY,
    kind        TEXT NOT NULL,
    ref         TEXT NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    body        TEXT NOT NULL DEFAULT '',
    mtime       REAL NOT NULL DEFAULT 0,
    provenance  TEXT NOT NULL DEFAULT '{}',
    UNIQUE (kind, ref)
);
CREATE INDEX IF NOT EXISTS items_kind ON items(kind);
CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(title, body);
"""


def default_db():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share")
    return os.path.join(data, "macshell", "context", "context.db")


def out(value, code=0):
    json.dump(value, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    raise SystemExit(code)


def fail(message, code=1):
    out({"error": message}, code)


def connect(path):
    path = Path(path).absolute()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(SCHEMA)
    for kind in KINDS:
        conn.execute("INSERT OR IGNORE INTO sources (kind, enabled, config, updated) VALUES (?, 0, '{}', ?)",
                     (kind, time.time()))
    conn.commit()
    return conn


def source_row(conn, kind):
    return conn.execute("SELECT enabled, config FROM sources WHERE kind = ?", (kind,)).fetchone()


def is_enabled(conn, kind):
    row = source_row(conn, kind)
    return bool(row and row[0])


def source_config(conn, kind):
    row = source_row(conn, kind)
    try:
        return json.loads(row[1]) if row else {}
    except json.JSONDecodeError:
        return {}


def item_provenance(kind, ref, origin, modified):
    return json.dumps({"kind": kind, "ref": ref, "origin": origin,
                       "modified": modified, "indexed_at": time.time(),
                       "indexer": INDEXER}, ensure_ascii=False)


def put_item(conn, kind, ref, title, body, mtime, provenance):
    """Insert or replace an item and its FTS row (rowid stays stable per ref)."""
    cur = conn.execute("SELECT id FROM items WHERE kind = ? AND ref = ?", (kind, ref))
    row = cur.fetchone()
    if row:
        item_id = row[0]
        with conn:
            conn.execute("UPDATE items SET title = ?, body = ?, mtime = ?, provenance = ? WHERE id = ?",
                         (title, body, mtime, provenance, item_id))
            conn.execute("DELETE FROM fts WHERE rowid = ?", (item_id,))
            conn.execute("INSERT INTO fts (rowid, title, body) VALUES (?, ?, ?)",
                         (item_id, title, body))
    else:
        with conn:
            cur = conn.execute(
                "INSERT INTO items (kind, ref, title, body, mtime, provenance) VALUES (?, ?, ?, ?, ?, ?)",
                (kind, ref, title, body, mtime, provenance))
            item_id = cur.lastrowid
            conn.execute("INSERT INTO fts (rowid, title, body) VALUES (?, ?, ?)",
                         (item_id, title, body))
    return item_id


def drop_item(conn, kind, ref):
    row = conn.execute("SELECT id FROM items WHERE kind = ? AND ref = ?", (kind, ref)).fetchone()
    if not row:
        return False
    with conn:
        conn.execute("DELETE FROM fts WHERE rowid = ?", (row[0],))
        conn.execute("DELETE FROM items WHERE id = ?", (row[0],))
    return True


def run_cli(script, args):
    """Run a sibling bridge CLI; the contract is its JSON stdout."""
    try:
        result = subprocess.run([sys.executable, "-B", str(script)] + list(args),
                                capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


# ═════════════ FILES (fixture folders) ═════════════

def clean_folders(raw):
    if isinstance(raw, str):
        parts = raw.split(",")
    elif isinstance(raw, list):
        parts = [str(p) for p in raw]
    else:
        return []
    seen, result = set(), []
    for part in parts:
        path = Path(os.path.expanduser(part.strip())).absolute()
        if str(path) in seen or part.strip() == "":
            continue
        seen.add(str(path))
        result.append(str(path))
    return result


def is_text_file(path):
    if path.suffix.lower() in TEXT_EXTENSIONS:
        return True
    try:
        with path.open("rb") as handle:
            chunk = handle.read(SNIFF_BYTES)
    except OSError:
        return False
    return b"\x00" not in chunk


def index_files(conn, config, full):
    folders = clean_folders(config.get("folders", []))
    if not folders:
        return {"indexed": 0, "removed": 0, "skipped-source": "no folders configured"}
    seen = set()
    indexed = 0
    now = time.time()
    for folder in folders:
        base = Path(folder)
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            ref = str(path)
            rel = path.relative_to(base)
            if any(part in SKIP_DIRS or part.startswith(".") for part in rel.parts[:-1]) \
                    or path.name.startswith("."):
                continue
            seen.add(ref)
            try:
                stat = path.stat()
            except OSError:
                continue
            if stat.st_size > MAX_FILE_BYTES or stat.st_size == 0:
                continue
            if not is_text_file(path):
                continue
            row = conn.execute("SELECT mtime FROM items WHERE kind = 'files' AND ref = ?",
                               (ref,)).fetchone()
            if row and not full and abs(row[0] - stat.st_mtime) < 1e-6:
                continue  # unchanged since the last index run
            try:
                text = path.read_text(encoding="utf-8", errors="replace")[:MAX_BODY_CHARS]
            except OSError:
                continue
            put_item(conn, "files", ref, path.name, text, stat.st_mtime,
                     item_provenance("files", ref, ref, stat.st_mtime))
            indexed += 1
    removed = 0
    for (ref,) in conn.execute("SELECT ref FROM items WHERE kind = 'files'").fetchall():
        if ref not in seen:
            drop_item(conn, "files", ref)
            removed += 1
    return {"indexed": indexed, "removed": removed, "folders": folders}


# ═════════════ NOTES (contract: bin/notes.py) ═════════════

def index_notes(conn, config, full):
    if not NOTES_PY.is_file():
        return {"indexed": 0, "skipped-source": "notes CLI not found"}
    db_arg = config.get("db") or config.get("path")
    base = ["list"] if not db_arg else ["--db", db_arg, "list"]
    listing = run_cli(NOTES_PY, base)
    if not listing or "notes" not in listing:
        return {"indexed": 0, "skipped-source": "notes CLI unavailable"}
    indexed = 0
    seen = set()
    for summary in listing["notes"]:
        note_id = summary.get("id")
        if not note_id:
            continue
        seen.add(note_id)
        row = conn.execute("SELECT mtime FROM items WHERE kind = 'notes' AND ref = ?",
                           (note_id,)).fetchone()
        if row and not full and abs(row[0] - float(summary.get("updated", 0))) < 1e-6:
            continue
        detail = run_cli(NOTES_PY, (["--db", db_arg] if db_arg else []) + ["get", "--id", note_id])
        note = (detail or {}).get("note")
        if not note:
            continue
        body = note.get("body", "")
        if note.get("strokes"):
            body += "\n[drawing: %d strokes]" % len(note["strokes"])
        mtime = float(note.get("updated", 0))
        put_item(conn, "notes", note_id, note.get("title", ""), body, mtime,
                 item_provenance("notes", note_id, db_arg or "macshell-notes", mtime))
        indexed += 1
    removed = 0
    for (ref,) in conn.execute("SELECT ref FROM items WHERE kind = 'notes'").fetchall():
        if ref not in seen:
            drop_item(conn, "notes", ref)
            removed += 1
    return {"indexed": indexed, "removed": removed}


# ═════════════ CALENDAR (contract: bin/calendar.py) ═════════════

def index_calendar(conn, config, full):
    if not CALENDAR_PY.is_file():
        return {"indexed": 0, "skipped-source": "calendar CLI not found"}
    now = dt.datetime.now(dt.timezone.utc)
    window_from = (now - dt.timedelta(days=30)).strftime("%Y-%m-%d")
    window_to = (now + dt.timedelta(days=90)).strftime("%Y-%m-%d")
    db_arg = config.get("db") or config.get("path")
    base = (["--db", db_arg] if db_arg else []) \
        + ["events", "--from", window_from, "--to", window_to]
    payload = run_cli(CALENDAR_PY, base)
    if not payload or "events" not in payload:
        return {"indexed": 0, "skipped-source": "calendar CLI unavailable"}
    indexed = 0
    seen = set()
    for event in payload["events"]:
        ref = event["id"]
        seen.add(ref)
        body = "\n".join(part for part in (event.get("notes", ""), event.get("location", "")) if part)
        body = (event.get("start", "") + "\n" + event.get("end", "") + "\n" + body).strip()
        mtime = float(event.get("updated", 0))
        row = conn.execute("SELECT mtime FROM items WHERE kind = 'calendar' AND ref = ?",
                           (ref,)).fetchone()
        if row and not full and abs(row[0] - mtime) < 1e-6:
            continue
        put_item(conn, "calendar", ref, event.get("title", ""), body, mtime,
                 item_provenance("calendar", ref, db_arg or "macshell-calendar", mtime))
        indexed += 1
    removed = 0
    for (ref,) in conn.execute("SELECT ref FROM items WHERE kind = 'calendar'").fetchall():
        if ref not in seen:
            drop_item(conn, "calendar", ref)
            removed += 1
    return {"indexed": indexed, "removed": removed}


# ═════════════ MAIL (local MacShell Mail) ═════════════

def index_mail(conn, config, full):
    studio = HERE / "studio.py"
    if not studio.is_file(): return {"indexed": 0, "skipped-source": "mail CLI not found"}
    result = run_cli(studio, ["mail.list"])
    if not result or "messages" not in result: return {"indexed": 0, "skipped-source": "mail CLI unavailable"}
    seen = set()
    for item in result["messages"]:
        ref = item["id"]; seen.add(ref)
        put_item(conn, "mail", ref, item["subject"], item["sender"] + "\n" + item["body"],
                 item["updated"], item_provenance("mail", ref, "macshell-mail", item["updated"]))
    removed = 0
    for (ref,) in conn.execute("SELECT ref FROM items WHERE kind = 'mail'").fetchall():
        if ref not in seen:
            drop_item(conn, "mail", ref)
            removed += 1
    return {"indexed": len(seen), "removed": removed}


INDEXERS = {"files": index_files, "notes": index_notes,
            "calendar": index_calendar, "mail": index_mail}


# ═════════════ COMMANDS ═════════════

def cmd_sources(args):
    conn = connect(args.db)
    rows = conn.execute(
        "SELECT s.kind, s.enabled, s.config, s.updated, COUNT(i.id) "
        "FROM sources s LEFT JOIN items i ON i.kind = s.kind "
        "GROUP BY s.kind ORDER BY s.kind").fetchall()
    sources = []
    for kind, enabled, config, updated, count in rows:
        try:
            config = json.loads(config)
        except json.JSONDecodeError:
            config = {}
        if kind == "files" and enabled and not clean_folders(config.get("folders", [])):
            status = "needs-folders"
        else:
            status = "enabled" if enabled else "disabled"
        sources.append({"kind": kind, "label": KIND_LABEL.get(kind, kind),
                        "enabled": bool(enabled), "status": status,
                        "config": config, "items": count, "updated": updated})
    out({"sources": sources})


def cmd_enable(args):
    if args.kind not in KINDS:
        fail("unknown source kind: " + str(args.kind))
    conn = connect(args.db)
    with conn:
        conn.execute("UPDATE sources SET enabled = 1, updated = ? WHERE kind = ?",
                     (time.time(), args.kind))
    out({"ok": True, "kind": args.kind, "enabled": True})


def cmd_disable(args):
    if args.kind not in KINDS:
        fail("unknown source kind: " + str(args.kind))
    conn = connect(args.db)
    with conn:
        conn.execute("UPDATE sources SET enabled = 0, updated = ? WHERE kind = ?",
                     (time.time(), args.kind))
    out({"ok": True, "kind": args.kind, "enabled": False})


def cmd_configure(args):
    if args.kind not in KINDS:
        fail("unknown source kind: " + str(args.kind))
    config = source_config(connect(args.db), args.kind)
    if args.kind == "files":
        if args.folders is None:
            fail("files needs --folders")
        config["folders"] = clean_folders(args.folders)
    if args.path is not None:
        config["path"] = args.path
    conn = connect(args.db)
    with conn:
        conn.execute("UPDATE sources SET config = ?, updated = ? WHERE kind = ?",
                     (json.dumps(config, ensure_ascii=False), time.time(), args.kind))
    out({"ok": True, "kind": args.kind, "config": config})


def cmd_index(args):
    conn = connect(args.db)
    report = {}
    for kind in KINDS:
        if not is_enabled(conn, kind):
            report[kind] = {"indexed": 0, "skipped-source": "disabled"}
            continue
        config = source_config(conn, kind)
        report[kind] = INDEXERS[kind](conn, config, args.full)
    with conn:
        conn.execute("UPDATE sources SET updated = ? WHERE enabled = 1", (time.time(),))
    out({"ok": True, "report": report})


def fts_query(raw):
    """Turn a free-text query into an FTS5 MATCH string (AND of quoted terms)."""
    terms = re.findall(r"[^\s\"'()]+", raw or "")
    if not terms:
        return None
    return " AND ".join('"%s"' % term.replace('"', '""') for term in terms)


def cmd_search(args):
    conn = connect(args.db)
    match = fts_query(args.query)
    if not match:
        fail("empty query")
    kinds = [args.kind] if args.kind else [k for k in KINDS if is_enabled(conn, k)]
    if args.kind and args.kind not in KINDS:
        fail("unknown source kind: " + str(args.kind))
    placeholders = ",".join("?" for _ in kinds) or "''"
    sql = ("SELECT i.kind, i.ref, i.title, i.mtime, i.provenance, "
           "snippet(fts, 1, '⟦', '⟧', ' … ', 12) "
           "FROM fts JOIN items i ON i.id = fts.rowid "
           "WHERE fts MATCH ? AND i.kind IN (%s) "
           "ORDER BY rank LIMIT ?" % placeholders)
    rows = conn.execute(sql, [match] + kinds + [max(1, min(args.limit, 50))]).fetchall()
    if os.environ.get("CTX_DEBUG"):
        with open("/tmp/opencode/ctxdebug.log", "a") as fh:
            fh.write(json.dumps({"match": match, "kinds": kinds, "rows": len(rows),
                                 "fts": conn.execute("SELECT rowid, title, body FROM fts LIMIT 5").fetchall(),
                                 "items": conn.execute("SELECT id, kind, ref, substr(body, 1, 40) FROM items LIMIT 5").fetchall()}) + "\n")
    results = []
    for kind, ref, title, mtime, provenance, snippet in rows:
        try:
            provenance = json.loads(provenance)
        except json.JSONDecodeError:
            provenance = {"kind": kind, "ref": ref}
        results.append({"kind": kind, "ref": ref, "title": title,
                        "modified": mtime, "provenance": provenance, "snippet": snippet})
    out({"query": args.query, "kinds": kinds, "results": results})


def cmd_forget(args):
    if args.kind not in KINDS:
        fail("unknown source kind: " + str(args.kind))
    conn = connect(args.db)
    with conn:
        for (item_id,) in conn.execute("SELECT id FROM items WHERE kind = ?", (args.kind,)).fetchall():
            conn.execute("DELETE FROM fts WHERE rowid = ?", (item_id,))
        conn.execute("DELETE FROM items WHERE kind = ?", (args.kind,))
    out({"ok": True, "kind": args.kind})


def cmd_contract(args):
    out({"contract": {
        "version": 1,
        "provenance": {
            "fields": ["kind", "ref", "origin", "modified", "indexed_at", "indexer"],
            "rule": "every indexed item and every search result carries provenance verbatim; "
                    "answers built on the index cite it",
        },
        "controls": {
            "storage": "sources table in the context database",
            "rule": "a disabled source is skipped by index and excluded from search; "
                    "disabled sources are not indexed",
            "defaults": {kind: False for kind in KINDS},
        },
        "sources": {
            "files": {
                "config": {"folders": ["absolute paths, comma separated via --folders"]},
                "reads": "text files under the configured fixture folders only; "
                         "hidden entries, dependency directories and binary blobs skipped; "
                         "first 512 KB / 20k chars per file; incremental by mtime",
                "ref": "absolute file path",
            },
            "notes": {
                "cli": "bin/notes.py list / get --id (JSON stdout)",
                "ref": "note id (YYYYMMDDHHMMSS-hex)",
                "fields": ["title", "body", "strokes (count only)", "updated"],
            },
            "calendar": {
                "cli": "bin/calendar.py events --from --to (JSON stdout)",
                "ref": "event id (YYYYMMDDHHMMSS-hex)",
                "window": "-30 … +90 days around the index run",
                "fields": ["title", "start", "end", "notes", "location", "updated"],
            },
            "mail": {
                "status": "available",
                "cli": "bin/studio.py mail.list (JSON stdout)",
                "fields": ["id", "subject", "sender", "recipient", "body", "updated"],
            },
        },
    }})


def main():
    parser = argparse.ArgumentParser(prog="context.py", description=__doc__)
    parser.add_argument("--db", default=default_db())
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("sources")
    p.set_defaults(func=cmd_sources)
    p = sub.add_parser("enable")
    p.add_argument("--kind", required=True)
    p.set_defaults(func=cmd_enable)
    p = sub.add_parser("disable")
    p.add_argument("--kind", required=True)
    p.set_defaults(func=cmd_disable)
    p = sub.add_parser("configure")
    p.add_argument("--kind", required=True)
    p.add_argument("--folders", default=None)
    p.add_argument("--path", default=None)
    p.set_defaults(func=cmd_configure)
    p = sub.add_parser("index")
    p.add_argument("--full", action="store_true")
    p.set_defaults(func=cmd_index)
    p = sub.add_parser("search")
    p.add_argument("--query", required=True)
    p.add_argument("--kind", default=None)
    p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=cmd_search)
    p = sub.add_parser("forget")
    p.add_argument("--kind", required=True)
    p.set_defaults(func=cmd_forget)
    p = sub.add_parser("contract")
    p.set_defaults(func=cmd_contract)
    args = parser.parse_args()
    try:
        args.func(args)
    except sqlite3.Error as error:
        fail("database error: " + str(error))
    except OSError as error:
        fail("i/o error: " + str(error))


if __name__ == "__main__":
    main()
