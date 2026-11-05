#!/usr/bin/env python3
"""MacShell Notes storage: SQLite database + drawing strokes + export.

One-shot CLI, JSON on stdout, everything offline. The Quickshell app calls one
command per action; nothing here shells out or touches the network.

  notes.py list [--folder NAME] [--query QUERY]
  notes.py folders
  notes.py get --id ID
  notes.py new [--title TITLE] [--folder NAME]
  notes.py save --json '{"id":...,"title":...,"body":...,"strokes":[...]}'
  notes.py pin --id ID --on 1|0
  notes.py move --id ID --folder NAME
  notes.py duplicate --id ID
  notes.py delete --id ID            (soft: moves the note to Recently Deleted)
  notes.py restore --id ID
  notes.py purge --id ID             (delete forever)
  notes.py empty-trash
  notes.py new-folder --name NAME
  notes.py delete-folder --name NAME (moves its notes back to "Notes")
  notes.py export --id ID --out PATH [--format md|txt|png|svg]

Strokes are stored vector-style so drawings stay editable: every stroke is
{"tool": pen|line|rect|ellipse, "color": "#rrggbb", "width": <fraction of the
canvas width>, "points": [x, y, x, y, ...]} with coordinates normalised to the
0..1 canvas box, so any canvas size renders the same drawing.

Folders are plain name strings on each note; "Trash" is reserved and stores
soft-deleted notes (deleted_at timestamp). Deleted notes stay recoverable
until they are purged or the trash is emptied.
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import tempfile
import time
import unicodedata
from pathlib import Path

TOOLS = ("pen", "line", "rect", "ellipse")
EXPORT_FORMATS = ("md", "txt", "png", "svg")
TRASH = "Trash"
DEFAULT_FOLDER = "Notes"

SCHEMA = """
CREATE TABLE IF NOT EXISTS notes (
    id       TEXT PRIMARY KEY,
    title    TEXT NOT NULL DEFAULT '',
    body     TEXT NOT NULL DEFAULT '',
    folder   TEXT NOT NULL DEFAULT 'Notes',
    created  REAL NOT NULL,
    updated  REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS strokes (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    idx     INTEGER NOT NULL,
    tool    TEXT NOT NULL,
    color   TEXT NOT NULL,
    width   REAL NOT NULL,
    points  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS strokes_note ON strokes(note_id, idx);
CREATE TABLE IF NOT EXISTS folders (
    name    TEXT PRIMARY KEY,
    created REAL NOT NULL
);
"""

MIGRATIONS = (
    ("pinned", "ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0"),
    ("deleted_at", "ALTER TABLE notes ADD COLUMN deleted_at REAL"),
)


def default_db():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share")
    return os.path.join(data, "macshell", "notes", "notes.db")


def connect(path):
    path = Path(path).absolute()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(SCHEMA)
    columns = {row[1] for row in conn.execute("PRAGMA table_info(notes)")}
    for name, statement in MIGRATIONS:
        if name not in columns:
            conn.execute(statement)
    conn.execute("INSERT OR IGNORE INTO folders (name, created) VALUES (?, ?)",
                 (DEFAULT_FOLDER, time.time()))
    conn.execute("INSERT OR IGNORE INTO folders (name, created) "
                 "SELECT DISTINCT folder, ? FROM notes WHERE folder != '' AND folder != ?",
                 (time.time(), TRASH))
    conn.commit()
    return conn


def out(value, code=0):
    json.dump(value, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    raise SystemExit(code)


def fail(message, code=1):
    out({"error": message}, code)


def valid_id(value):
    return bool(re.fullmatch(r"[0-9a-zA-Z_-]{1,64}", value or ""))


def new_id():
    return time.strftime("%Y%m%d%H%M%S") + "-" + os.urandom(4).hex()


def valid_color(value):
    return bool(re.fullmatch(r"#[0-9a-fA-F]{6}", value or ""))


def clean_folder(value):
    name = " ".join(str(value or "").split())
    if not 1 <= len(name) <= 60 or any(ord(c) < 32 for c in name):
        return None
    if name.lower() == TRASH.lower():
        return None
    return name


def clean_strokes(raw):
    """Validate a stroke list coming from the UI; drops malformed entries."""
    strokes = []
    if not isinstance(raw, list):
        return strokes
    for item in raw:
        if not isinstance(item, dict):
            continue
        tool = item.get("tool")
        color = item.get("color")
        width = item.get("width")
        points = item.get("points")
        if tool not in TOOLS or not valid_color(color):
            continue
        try:
            width = float(width)
        except (TypeError, ValueError):
            continue
        if not 0.0005 <= width <= 0.2:
            continue
        if not isinstance(points, list) or len(points) < 4:
            continue
        flat = []
        try:
            for value in points:
                value = float(value)
                if not -0.05 <= value <= 1.05:
                    raise ValueError
                flat.append(value)
        except (TypeError, ValueError):
            continue
        if len(flat) % 2 != 0 or len(flat) < 4:
            continue
        strokes.append({"tool": tool, "color": color.lower(), "width": round(width, 5),
                        "points": [round(v, 5) for v in flat]})
    return strokes


def note_row(conn, note_id):
    row = conn.execute(
        "SELECT id, title, body, folder, created, updated, pinned, deleted_at FROM notes WHERE id = ?",
        (note_id,)).fetchone()
    return row


def strokes_of(conn, note_id):
    rows = conn.execute(
        "SELECT idx, tool, color, width, points FROM strokes WHERE note_id = ? ORDER BY idx",
        (note_id,)).fetchall()
    result = []
    for idx, tool, color, width, points in rows:
        try:
            flat = json.loads(points)
        except json.JSONDecodeError:
            continue
        result.append({"tool": tool, "color": color, "width": width, "points": flat})
    return result


def snippet(body, limit=90):
    text = " ".join((body or "").split())
    return text[:limit]


def title_of(title, body):
    title = (title or "").strip()
    if title:
        return title
    text = " ".join((body or "").split())
    return text[:40] or "New Note"


def summary(conn, row):
    note_id, title, body, folder, created, updated, pinned, deleted_at = row
    has_drawing = conn.execute("SELECT 1 FROM strokes WHERE note_id = ? LIMIT 1",
                               (note_id,)).fetchone() is not None
    return {"id": note_id, "title": title_of(title, body), "snippet": snippet(body),
            "folder": folder, "created": created, "updated": updated,
            "pinned": bool(pinned), "deleted": deleted_at is not None,
            "has_drawing": has_drawing,
            "words": len((body or "").split())}


def cmd_list(args):
    conn = connect(args.db)
    in_trash = args.folder == TRASH
    want = args.folder if args.folder and args.folder not in ("All", TRASH) else None
    sql = ("SELECT id, title, body, folder, created, updated, pinned, deleted_at FROM notes "
           "WHERE deleted_at IS " + ("NOT NULL" if in_trash else "NULL"))
    params = []
    if want:
        sql += " AND folder = ?"
        params.append(want)
    # Pinned first (newest first), then everything else by update time.
    sql += " ORDER BY pinned DESC, updated DESC"
    rows = conn.execute(sql, params).fetchall()
    query = (args.query or "").strip().lower()
    notes = []
    for row in rows:
        s = summary(conn, row)
        haystack = (s["title"] + " " + s["snippet"]).lower()
        if query and query not in unicodedata.normalize("NFKD", haystack).lower():
            continue
        notes.append(s)
    out({"notes": notes, "folder": args.folder or "All"})


def cmd_folders(args):
    conn = connect(args.db)
    rows = conn.execute(
        "SELECT folder, COUNT(*), MAX(updated) FROM notes WHERE deleted_at IS NULL GROUP BY folder"
    ).fetchall()
    counts = {name: (count, latest) for name, count, latest in rows}
    names = {row[0] for row in conn.execute("SELECT name FROM folders")}
    names.update(counts.keys())
    folders = [{"name": name, "count": counts.get(name, (0, 0))[0],
                "updated": counts.get(name, (0, 0))[1]}
               for name in sorted(names, key=lambda n: n.lower())]
    total = conn.execute("SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL").fetchone()[0]
    trashed = conn.execute("SELECT COUNT(*) FROM notes WHERE deleted_at IS NOT NULL").fetchone()[0]
    out({"folders": folders, "all": total, "trash": trashed})


def cmd_get(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    row = note_row(conn, args.id)
    if row is None:
        fail("note not found")
    note_id, title, body, folder, created, updated, pinned, deleted_at = row
    out({"note": {"id": note_id, "title": title, "body": body, "folder": folder,
                  "created": created, "updated": updated, "pinned": bool(pinned),
                  "deleted": deleted_at is not None,
                  "strokes": strokes_of(conn, note_id)}})


def cmd_new(args):
    conn = connect(args.db)
    folder = clean_folder(args.folder) if args.folder else DEFAULT_FOLDER
    if args.folder and folder is None:
        fail("invalid folder name")
    now = time.time()
    note_id = new_id()
    with conn:
        conn.execute("INSERT OR IGNORE INTO folders (name, created) VALUES (?, ?)", (folder, now))
        conn.execute("INSERT INTO notes (id, title, body, folder, created, updated) VALUES (?, '', '', ?, ?, ?)",
                     (note_id, folder, now, now))
    out({"note": {"id": note_id, "title": "", "body": "", "folder": folder,
                  "created": now, "updated": now, "pinned": False, "deleted": False,
                  "strokes": []}})


def cmd_save(args):
    try:
        payload = json.loads(args.json)
    except json.JSONDecodeError as error:
        fail("invalid json: " + str(error))
    if not isinstance(payload, dict) or not valid_id(payload.get("id")):
        fail("invalid payload")
    conn = connect(args.db)
    row = note_row(conn, payload["id"])
    if row is None:
        fail("note not found")
    note_id, _title, _body, _folder, created, _updated, _pinned, _deleted = row
    title = str(payload.get("title") or "")[:200]
    body = str(payload.get("body") or "")
    now = time.time()
    with conn:
        conn.execute("UPDATE notes SET title = ?, body = ?, updated = ? WHERE id = ?",
                     (title, body, now, note_id))
        if "strokes" in payload:
            strokes = clean_strokes(payload["strokes"])
            conn.execute("DELETE FROM strokes WHERE note_id = ?", (note_id,))
            conn.executemany(
                "INSERT INTO strokes (note_id, idx, tool, color, width, points) VALUES (?, ?, ?, ?, ?, ?)",
                [(note_id, i, s["tool"], s["color"], s["width"], json.dumps(s["points"]))
                 for i, s in enumerate(strokes)])
    out({"ok": True, "id": note_id, "updated": now,
         "title": title_of(title, body), "strokes": len(clean_strokes(payload.get("strokes", []))) if "strokes" in payload else None})


def cmd_pin(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    if note_row(conn, args.id) is None:
        fail("note not found")
    with conn:
        conn.execute("UPDATE notes SET pinned = ? WHERE id = ?", (1 if args.on else 0, args.id))
    out({"ok": True, "id": args.id, "pinned": bool(args.on)})


def cmd_move(args):
    if not valid_id(args.id):
        fail("invalid note id")
    folder = clean_folder(args.folder)
    if folder is None:
        fail("invalid folder name")
    conn = connect(args.db)
    if note_row(conn, args.id) is None:
        fail("note not found")
    with conn:
        conn.execute("INSERT OR IGNORE INTO folders (name, created) VALUES (?, ?)", (folder, time.time()))
        conn.execute("UPDATE notes SET folder = ? WHERE id = ?", (folder, args.id))
    out({"ok": True, "id": args.id, "folder": folder})


def cmd_duplicate(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    row = note_row(conn, args.id)
    if row is None:
        fail("note not found")
    note_id, title, body, folder, created, updated, pinned, _deleted = row
    new_note_id = new_id()
    now = time.time()
    with conn:
        conn.execute("INSERT INTO notes (id, title, body, folder, created, updated, pinned) "
                     "VALUES (?, ?, ?, ?, ?, ?, 0)",
                     (new_note_id, (title_of(title, body) + " copy")[:200], body, folder, now, now))
        conn.executemany(
            "INSERT INTO strokes (note_id, idx, tool, color, width, points) VALUES (?, ?, ?, ?, ?, ?)",
            [(new_note_id, s["idx"], s["tool"], s["color"], s["width"], s["points"])
             for s in conn.execute("SELECT idx, tool, color, width, points FROM strokes WHERE note_id = ? ORDER BY idx",
                                   (note_id,)).fetchall()])
    out({"ok": True, "id": new_note_id, "source": note_id})


def cmd_delete(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    row = note_row(conn, args.id)
    if row is None:
        fail("note not found")
    if row[7] is not None:
        fail("note is already in the trash")
    with conn:
        conn.execute("UPDATE notes SET deleted_at = ?, pinned = 0 WHERE id = ?", (time.time(), args.id))
    out({"ok": True, "deleted": args.id})


def cmd_restore(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    row = note_row(conn, args.id)
    if row is None:
        fail("note not found")
    if row[7] is None:
        fail("note is not in the trash")
    with conn:
        conn.execute("UPDATE notes SET deleted_at = NULL WHERE id = ?", (args.id,))
    out({"ok": True, "restored": args.id})


def cmd_purge(args):
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    if note_row(conn, args.id) is None:
        fail("note not found")
    with conn:
        conn.execute("DELETE FROM strokes WHERE note_id = ?", (args.id,))
        conn.execute("DELETE FROM notes WHERE id = ?", (args.id,))
    out({"ok": True, "purged": args.id})


def cmd_empty_trash(args):
    conn = connect(args.db)
    rows = conn.execute("SELECT id FROM notes WHERE deleted_at IS NOT NULL").fetchall()
    ids = [row[0] for row in rows]
    with conn:
        if ids:
            marks = ",".join("?" * len(ids))
            conn.execute("DELETE FROM strokes WHERE note_id IN (%s)" % marks, ids)
            conn.execute("DELETE FROM notes WHERE deleted_at IS NOT NULL")
    out({"ok": True, "purged": len(ids)})


def cmd_new_folder(args):
    folder = clean_folder(args.name)
    if folder is None:
        fail("invalid folder name")
    conn = connect(args.db)
    exists = conn.execute("SELECT 1 FROM folders WHERE name = ?", (folder,)).fetchone() is not None
    if exists:
        fail("folder already exists")
    with conn:
        conn.execute("INSERT INTO folders (name, created) VALUES (?, ?)", (folder, time.time()))
    out({"ok": True, "folder": folder})


def cmd_delete_folder(args):
    folder = clean_folder(args.name)
    if folder is None:
        fail("invalid folder name")
    conn = connect(args.db)
    exists = conn.execute("SELECT 1 FROM folders WHERE name = ?", (folder,)).fetchone() is not None
    if not exists:
        fail("folder not found")
    with conn:
        conn.execute("UPDATE notes SET folder = ? WHERE folder = ? AND deleted_at IS NULL",
                     (DEFAULT_FOLDER, folder))
        conn.execute("DELETE FROM folders WHERE name = ?", (folder,))
    out({"ok": True, "folder": folder})


def safe_name(title, fallback):
    name = unicodedata.normalize("NFKD", title or "").encode("ascii", "ignore").decode()
    name = re.sub(r"[^0-9a-zA-Z ._-]", "", name).strip().replace(" ", "-")
    return (name or fallback)[:60]


def unique_path(directory, stem, suffix):
    directory.mkdir(parents=True, exist_ok=True)
    candidate = directory / (stem + suffix)
    n = 1
    while candidate.exists():
        candidate = directory / ("%s-%d%s" % (stem, n, suffix))
        n += 1
    return candidate


def render_png(strokes, width=1200, height=900, background=(255, 255, 255, 255)):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    image = Image.new("RGBA", (width, height), background)
    draw = ImageDraw.Draw(image)
    for stroke in strokes:
        pts = stroke["points"]
        color = stroke["color"]
        line_width = max(1, round(stroke["width"] * width))
        if stroke["tool"] == "pen":
            xy = [(round(x * width), round(y * height)) for x, y in zip(pts[0::2], pts[1::2])]
            if len(xy) == 2:
                draw.line(xy, fill=color, width=line_width)
            else:
                draw.line(xy, fill=color, width=line_width, joint="curve")
            radius = line_width / 2
            for cx, cy in (xy[0], xy[-1]):
                draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color)
        else:
            x0, y0, x1, y1 = [round(v * (width if i % 2 == 0 else height))
                              for i, v in enumerate(pts[:4])]
            box = (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
            if stroke["tool"] == "line":
                draw.line([x0, y0, x1, y1], fill=color, width=line_width)
            elif stroke["tool"] == "rect":
                draw.rectangle(box, outline=color, width=line_width)
            else:
                draw.ellipse(box, outline=color, width=line_width)
    return image


def render_svg(strokes, width=1200, height=900):
    parts = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
             % (width, height, width, height),
             '<rect width="%d" height="%d" fill="white"/>' % (width, height)]
    for stroke in strokes:
        pts = stroke["points"]
        line_width = max(1.0, stroke["width"] * width)
        common = 'stroke="%s" stroke-width="%.2f" fill="none" stroke-linecap="round" stroke-linejoin="round"' % (
            stroke["color"], line_width)
        if stroke["tool"] == "pen":
            poly = " ".join("%.1f,%.1f" % (x * width, y * height)
                            for x, y in zip(pts[0::2], pts[1::2]))
            parts.append('<polyline points="%s" %s/>' % (poly, common))
        else:
            x0, y0, x1, y1 = [v * (width if i % 2 == 0 else height) for i, v in enumerate(pts[:4])]
            if stroke["tool"] == "line":
                parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" %s/>' % (x0, y0, x1, y1, common))
            elif stroke["tool"] == "rect":
                parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" %s/>'
                             % (min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0), common))
            else:
                parts.append('<ellipse cx="%.1f" cy="%.1f" rx="%.1f" ry="%.1f" %s/>'
                             % ((x0 + x1) / 2, (y0 + y1) / 2, abs(x1 - x0) / 2, abs(y1 - y0) / 2, common))
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def export_document(note, strokes, path, fmt):
    title = title_of(note["title"], note["body"])
    if fmt == "md":
        text = "# " + title + "\n\n" + (note["body"] or "").rstrip() + "\n"
        if strokes:
            text += "\n---\n*This note contains a drawing (%d strokes); export it separately as PNG/SVG.*\n" % len(strokes)
        path.write_text(text, encoding="utf-8")
    elif fmt == "txt":
        path.write_text(title + "\n\n" + (note["body"] or "").rstrip() + "\n", encoding="utf-8")
    elif fmt == "svg":
        path.write_text(render_svg(strokes), encoding="utf-8")
    elif fmt == "png":
        image = render_png(strokes)
        if image is None:
            return "Pillow is not installed; PNG export needs it (SVG export still works)"
        image.save(str(path))
    else:
        return "unsupported format"
    return None


def cmd_export(args):
    if args.format not in EXPORT_FORMATS:
        fail("unsupported format")
    if not valid_id(args.id):
        fail("invalid note id")
    conn = connect(args.db)
    row = note_row(conn, args.id)
    if row is None:
        fail("note not found")
    note_id, title, body, _folder, created, updated, _pinned, _deleted = row
    note = {"id": note_id, "title": title, "body": body, "created": created, "updated": updated}
    strokes = strokes_of(conn, note_id)
    out_path = Path(args.out).expanduser().absolute()
    if out_path.suffix.lower() != "." + args.format:
        out_path = out_path.with_suffix("." + args.format)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    error = export_document(note, strokes, out_path, args.format)
    if error:
        fail(error)
    out({"ok": True, "path": str(out_path), "format": args.format})


def main():
    parser = argparse.ArgumentParser(prog="notes.py", description=__doc__)
    parser.add_argument("--db", default=default_db())
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("list")
    p.add_argument("--folder", default="All")
    p.add_argument("--query", default="")
    p.set_defaults(func=cmd_list)
    p = sub.add_parser("folders")
    p.set_defaults(func=cmd_folders)
    p = sub.add_parser("get")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_get)
    p = sub.add_parser("new")
    p.add_argument("--title", default="")
    p.add_argument("--folder", default=DEFAULT_FOLDER)
    p.set_defaults(func=cmd_new)
    p = sub.add_parser("save")
    p.add_argument("--json", required=True)
    p.set_defaults(func=cmd_save)
    p = sub.add_parser("pin")
    p.add_argument("--id", required=True)
    p.add_argument("--on", type=int, default=1)
    p.set_defaults(func=cmd_pin)
    p = sub.add_parser("move")
    p.add_argument("--id", required=True)
    p.add_argument("--folder", required=True)
    p.set_defaults(func=cmd_move)
    p = sub.add_parser("duplicate")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_duplicate)
    p = sub.add_parser("delete")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_delete)
    p = sub.add_parser("restore")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_restore)
    p = sub.add_parser("purge")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_purge)
    p = sub.add_parser("empty-trash")
    p.set_defaults(func=cmd_empty_trash)
    p = sub.add_parser("new-folder")
    p.add_argument("--name", required=True)
    p.set_defaults(func=cmd_new_folder)
    p = sub.add_parser("delete-folder")
    p.add_argument("--name", required=True)
    p.set_defaults(func=cmd_delete_folder)
    p = sub.add_parser("export")
    p.add_argument("--id", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--format", default="md", choices=EXPORT_FORMATS)
    p.set_defaults(func=cmd_export)
    args = parser.parse_args()
    try:
        args.func(args)
    except sqlite3.Error as error:
        fail("database error: " + str(error))
    except OSError as error:
        fail("i/o error: " + str(error))


if __name__ == "__main__":
    main()
