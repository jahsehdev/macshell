#!/usr/bin/env python3
"""MacShell Calendar storage: SQLite events + reminders + ICS + a sentence parser.

One-shot CLI, JSON on stdout, everything offline. The Quickshell app calls one
command per action; nothing here shells out or touches the network.

  calendar.py calendars
  calendar.py events --from ISO --to ISO [--calendar NAME] [--query Q]
  calendar.py get --id ID
  calendar.py new --json '{"title":...,"start":...,...}'
  calendar.py save --json '{"id":...,...}'
  calendar.py delete --id ID
  calendar.py new-calendar --name NAME --color #rrggbb
  calendar.py delete-calendar --name NAME
  calendar.py due [--now ISO]         (reminders that must fire; marks them done)
  calendar.py import --file PATH [--calendar NAME]
  calendar.py export --file PATH [--calendar NAME]
  calendar.py parse --text "rapat besok jam 14.00 selama 1 jam"

Times are stored as ISO-8601 strings with an explicit offset
("2026-11-01T09:00:00+07:00") so Asia/Jakarta (and any other zone) round-trips
without the process relying on its own local timezone. All-day events store
date-only strings ("2026-11-01"). Recurrence is a minimal RRULE (FREQ=DAILY |
WEEKLY[BYDAY=MO,TU,...] | MONTHLY, with INTERVAL and COUNT/UNTIL) expanded on
read for the month/week windows.

The parser (`parse`) converts an Indonesian or English sentence into an event
preview: date words (today/tomorrow/day names), clock times (14.00, 2pm,
"jam 9 malam"), durations ("selama 2 jam", "for 30 minutes"), all-day hints,
and the text before the time words becomes the title. It never saves anything;
the app shows the preview and the user confirms.
"""

import argparse
import datetime as dt
import json
import os
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

# This file is named calendar.py, which shadows the stdlib `calendar` module —
# _strptime (used by datetime.strptime) imports it internally. Drop our own
# directory from sys.path so the real stdlib module is found.
_here = os.path.dirname(os.path.abspath(__file__))
if sys.path and os.path.abspath(sys.path[0]) == _here:
    sys.path.pop(0)

CAL_COLORS = ("#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#30D158", "#007AFF",
              "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#8E8E93")
DEFAULT_CALENDAR = "Home"
WEEKDAY_NUM = {"monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
               "friday": 4, "saturday": 5, "sunday": 6}
BYDAY_NUM = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}
ICS_WEEKDAY = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS calendars (
    name    TEXT PRIMARY KEY,
    color   TEXT NOT NULL DEFAULT '#007AFF',
    created REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
    id        TEXT PRIMARY KEY,
    calendar  TEXT NOT NULL DEFAULT 'Home',
    title     TEXT NOT NULL DEFAULT '',
    notes     TEXT NOT NULL DEFAULT '',
    location  TEXT NOT NULL DEFAULT '',
    start     TEXT NOT NULL,
    end       TEXT NOT NULL,
    all_day   INTEGER NOT NULL DEFAULT 0,
    rrule     TEXT NOT NULL DEFAULT '',
    reminders TEXT NOT NULL DEFAULT '[]',
    created   REAL NOT NULL,
    updated   REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS events_start ON events(start);
CREATE TABLE IF NOT EXISTS reminder_fires (
    event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    due      TEXT NOT NULL,
    done     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (event_id, due)
);
"""


def default_db():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share")
    return os.path.join(data, "macshell", "calendar", "calendar.db")


def out(value, code=0):
    json.dump(value, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    raise SystemExit(code)


def fail(message, code=1):
    out({"error": message}, code)


def valid_id(value):
    return bool(re.fullmatch(r"[0-9a-zA-Z_-]{1,64}", value or ""))


def new_id():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S") + "-" + os.urandom(4).hex()


def connect(path):
    path = Path(path).absolute()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(SCHEMA)
    conn.execute("INSERT OR IGNORE INTO calendars (name, color, created) VALUES (?, ?, ?)",
                 (DEFAULT_CALENDAR, "#FF3B30", dt.datetime.now(dt.timezone.utc).timestamp()))
    conn.commit()
    return conn


# ═════════════ TIME HELPERS (ISO strings with explicit offsets) ═════════════

def parse_iso(value, end_of_day=False):
    """Accepts '2026-11-01', '2026-11-01T09:00:00+07:00', '2026-11-01T09:00:00Z'."""
    s = (value or "").strip()
    if not s:
        return None
    try:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
            # date-only: interpret at midnight/next midnight in the process zone
            d = dt.date.fromisoformat(s)
            t = dt.time.max if end_of_day else dt.time.min
            local = dt.datetime.combine(d, t, tzinfo=_process_tz())
            return local.astimezone(dt.timezone.utc).isoformat()
        return dt.datetime.fromisoformat(s).astimezone(dt.timezone.utc).isoformat()
    except (ValueError, TypeError):
        return None


def _process_tz():
    return dt.datetime.now().astimezone().tzinfo


def parse_time_field(value, end_of_day=False):
    """Events store start/end; date-only values stay date-only (all-day form)."""
    s = (value or "").strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return s  # keep the date-only shape
    return parse_iso(s, end_of_day=end_of_day)


def parse_local(value):
    """Parse an ISO string (with offset, Z, or naive) into an aware datetime."""
    s = (value or "").strip()
    try:
        d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=_process_tz())
    return d


def local_date(value):
    d = parse_local(value)
    return d.astimezone(_process_tz()).date() if d else None


# ═════════════ RECURRENCE (minimal RRULE) ═════════════

def parse_rrule(rule):
    """Returns None or {'freq','interval','byday',None...,'count','until'}."""
    s = (rule or "").strip().upper()
    if not s:
        return None
    parts = {}
    for chunk in s.split(";"):
        if "=" in chunk:
            k, v = chunk.split("=", 1)
            parts[k.strip()] = v.strip()
    freq = parts.get("FREQ", "").lower()
    if freq not in ("daily", "weekly", "monthly"):
        return None
    try:
        interval = max(1, int(parts.get("INTERVAL", "1")))
    except ValueError:
        interval = 1
    count = None
    until = None
    try:
        if "COUNT" in parts:
            count = max(1, int(parts["COUNT"]))
        if "UNTIL" in parts:
            u = parts["UNTIL"]
            until = dt.date(int(u[0:4]), int(u[4:6]), int(u[6:8]))
    except (ValueError, IndexError):
        count = None
        until = None
    byday = [BYDAY_NUM[d] for d in re.findall(r"MO|TU|WE|TH|FR|SA|SU", parts.get("BYDAY", ""))]
    return {"freq": freq, "interval": interval, "byday": byday, "count": count, "until": until}


def expand_rrule(rule, first_start, window_start, window_end, limit=400):
    """Yields occurrence datetimes (aware, UTC) of a rule inside [window_start, window_end]."""
    r = parse_rrule(rule)
    if not r or not first_start:
        return
    try:
        base = parse_local(first_start)
        ws = parse_local(window_start)
        we = parse_local(window_end)
    except (ValueError, TypeError):
        return
    if not base or not ws or not we:
        return
    freq, interval = r["freq"], r["interval"]
    emitted = 0
    cursor = base
    # advance the cursor to roughly the window start
    step = {"daily": dt.timedelta(days=interval),
            "weekly": dt.timedelta(weeks=interval),
            "monthly": None}[freq]
    safety = 0
    while cursor < ws and safety < 2000:
        safety += 1
        if freq == "monthly":
            m = cursor.month - 1 + interval
            cursor = cursor.replace(year=cursor.year + m // 12, month=m % 12 + 1)
        else:
            cursor = cursor + step
    i = 0
    while cursor <= we and emitted < limit:
        i += 1
        keep = True
        if r["byday"] and freq == "weekly":
            keep = cursor.weekday() in r["byday"]
        if keep and (r["until"] is None or cursor.date() <= r["until"]) \
                and (r["count"] is None or emitted + (i - emitted) <= r["count"]):
            if cursor >= ws:
                yield cursor
                emitted += 1
            if r["count"] is not None and emitted >= r["count"]:
                return
        if freq == "monthly":
            m = cursor.month - 1 + interval
            cursor = cursor.replace(year=cursor.year + m // 12, month=m % 12 + 1)
        else:
            cursor = cursor + step
    return


def occurrence_count(rule, first_start, horizon_days=366):
    """How many occurrences the rule produces within the horizon (for cleanup)."""
    r = parse_rrule(rule)
    if not r:
        return 1
    if r["count"] is not None:
        return r["count"]
    if r["until"] is not None:
        return None  # bounded, but by date
    return None  # unbounded — expanded on read, never materialised


# ═════════════ EVENT ROWS ═════════════

def valid_color(value):
    return bool(re.fullmatch(r"#[0-9a-fA-F]{6}", value or ""))


def clean_reminders(raw):
    """Reminder offsets in seconds (negative = before start), like [300, 900]."""
    if not isinstance(raw, list):
        return []
    result = []
    for value in raw:
        try:
            value = int(value)
        except (TypeError, ValueError):
            continue
        if -86400 * 7 <= value <= 0:
            result.append(value)
    return sorted(set(result), reverse=True)


def event_row(conn, event_id):
    return conn.execute(
        "SELECT id, calendar, title, notes, location, start, end, all_day, rrule, reminders, created, updated "
        "FROM events WHERE id = ?", (event_id,)).fetchone()


def summary(row, calendar_color):
    (eid, cal, title, notes, location, start, end, all_day, rrule,
     reminders, created, updated) = row
    try:
        reminders = json.loads(reminders)
    except json.JSONDecodeError:
        reminders = []
    return {"id": eid, "calendar": cal, "color": calendar_color, "title": title,
            "notes": notes, "location": location, "start": start, "end": end,
            "allDay": bool(all_day), "rrule": rrule, "reminders": reminders,
            "created": created, "updated": updated}


def color_of(conn, name):
    row = conn.execute("SELECT color FROM calendars WHERE name = ?", (name,)).fetchone()
    return row[0] if row else "#007AFF"


def cmd_calendars(args):
    conn = connect(args.db)
    rows = conn.execute(
        "SELECT c.name, c.color, COUNT(e.id) FROM calendars c "
        "LEFT JOIN events e ON e.calendar = c.name GROUP BY c.name ORDER BY c.name COLLATE NOCASE"
    ).fetchall()
    out({"calendars": [{"name": n, "color": c, "count": k} for n, c, k in rows]})


def cmd_events(args):
    conn = connect(args.db)
    if not args.from_ or not args.to:
        fail("events needs --from and --to (ISO dates)")
    window_start = parse_iso(args.from_)
    window_end = parse_iso(args.to, end_of_day=True)
    if not window_start or not window_end:
        fail("invalid date range")
    ws = parse_local(window_start)
    we = parse_local(window_end)
    if not ws or not we:
        fail("invalid date range")
    query = (args.query or "").strip().lower()
    calendar_filter = args.calendar or None
    result = []
    for row in conn.execute(
            "SELECT id, calendar, title, notes, location, start, end, all_day, rrule, reminders, created, updated "
            "FROM events ORDER BY start").fetchall():
        (eid, cal, title, notes, location, start, end, all_day, rrule,
         reminders, created, updated) = row
        if calendar_filter and cal != calendar_filter:
            continue
        if query and query not in unicodedata.normalize("NFKD", (title + " " + notes + " " + location).lower()).lower():
            continue
        color = color_of(conn, cal)
        if rrule:
            try:
                first = parse_local(start)
                dur = parse_local(end) - first
            except (ValueError, TypeError):
                continue
            for occ in expand_rrule(rrule, start, window_start, window_end):
                result.append(summary(
                    (eid, cal, title, notes, location, occ.isoformat(),
                     (occ + dur).isoformat(), all_day, rrule, reminders, created, updated),
                    color))
        else:
            ev_start = parse_local(start)
            ev_end = parse_local(end)
            if ev_start and ev_end and ev_end >= ws and ev_start <= we:
                result.append(summary(row, color))
    result.sort(key=lambda e: (e["start"], e["title"]))
    out({"events": result, "from": window_start, "to": window_end})


def cmd_get(args):
    if not valid_id(args.id):
        fail("invalid event id")
    conn = connect(args.db)
    row = event_row(conn, args.id)
    if row is None:
        fail("event not found")
    out({"event": summary(row, color_of(conn, row[1]))})


def validate_event_payload(conn, payload, partial=False):
    """Returns (fields, error). Fields are the columns to write."""
    fields = {}
    if "calendar" in payload:
        name = str(payload["calendar"]).strip()[:60]
        if not name:
            return None, "calendar name required"
        if conn.execute("SELECT 1 FROM calendars WHERE name = ?", (name,)).fetchone() is None:
            return None, "calendar not found: " + name
        fields["calendar"] = name
    elif not partial:
        fields["calendar"] = DEFAULT_CALENDAR
    if "title" in payload:
        fields["title"] = str(payload["title"] or "")[:200]
    elif not partial:
        fields["title"] = "Event"
    if "notes" in payload:
        fields["notes"] = str(payload["notes"] or "")[:5000]
    if "location" in payload:
        fields["location"] = str(payload["location"] or "")[:200]
    if "allDay" in payload:
        fields["all_day"] = 1 if payload["allDay"] else 0
    start = payload.get("start")
    end = payload.get("end")
    if start is not None:
        parsed = parse_time_field(start)
        if not parsed:
            return None, "invalid start time"
        fields["start"] = parsed
    if end is not None:
        parsed = parse_time_field(end, end_of_day=True)
        if not parsed:
            return None, "invalid end time"
        fields["end"] = parsed
    if "start" in fields or "end" in fields or not partial:
        base = event_row(conn, payload.get("id", "")) if partial else None
        cur_start = fields.get("start", base[5] if base else None)
        cur_end = fields.get("end", base[6] if base else None)
        cur_all = fields.get("all_day", base[7] if base else 0)
        if cur_start is None or cur_end is None:
            return None, "start and end are required"
        if not cur_all:  # date-only + all_day shape mismatch guard
            s = parse_local(cur_start)
            e = parse_local(cur_end)
            if s and e and e < s:
                return None, "end is before start"
    if "rrule" in payload:
        rule = str(payload["rrule"] or "").strip()
        if rule and parse_rrule(rule) is None:
            return None, "unsupported rrule (use FREQ=DAILY|WEEKLY|MONTHLY)"
        fields["rrule"] = rule
    if "reminders" in payload:
        fields["reminders"] = json.dumps(clean_reminders(payload["reminders"]))
    return fields, None


def cmd_new(args):
    try:
        payload = json.loads(args.json)
    except json.JSONDecodeError as error:
        fail("invalid json: " + str(error))
    if not isinstance(payload, dict):
        fail("invalid payload")
    conn = connect(args.db)
    fields, error = validate_event_payload(conn, payload)
    if error:
        fail(error)
    now = dt.datetime.now(dt.timezone.utc).timestamp()
    event_id = new_id()
    with conn:
        conn.execute("INSERT INTO events (id, calendar, title, notes, location, start, end, all_day, rrule, reminders, created, updated) "
                     "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     (event_id, fields["calendar"], fields["title"], fields.get("notes", ""),
                      fields.get("location", ""), fields["start"], fields["end"],
                      fields.get("all_day", 0), fields.get("rrule", ""),
                      fields.get("reminders", "[]"), now, now))
        _schedule_fires(conn, event_id, fields["start"], fields.get("reminders", "[]"))
    rem_list = json.loads(fields.get("reminders", "[]"))
    out({"event": {"id": event_id, **{k: v for k, v in fields.items() if k != "all_day" and k != "reminders"},
                   "allDay": bool(fields.get("all_day", 0)), "reminders": rem_list}})


def _schedule_fires(conn, event_id, start, reminders_json):
    try:
        offsets = json.loads(reminders_json)
    except json.JSONDecodeError:
        offsets = []
    conn.execute("DELETE FROM reminder_fires WHERE event_id = ?", (event_id,))
    try:
        first = parse_local(start)
    except (ValueError, TypeError):
        return
    if not first:
        return
    for off in offsets:
        due = (first + dt.timedelta(seconds=off)).isoformat()
        conn.execute("INSERT OR IGNORE INTO reminder_fires (event_id, due, done) VALUES (?, ?, 0)",
                     (event_id, due))


def cmd_save(args):
    try:
        payload = json.loads(args.json)
    except json.JSONDecodeError as error:
        fail("invalid json: " + str(error))
    if not isinstance(payload, dict) or not valid_id(payload.get("id")):
        fail("invalid payload")
    conn = connect(args.db)
    row = event_row(conn, payload["id"])
    if row is None:
        fail("event not found")
    fields, error = validate_event_payload(conn, payload, partial=True)
    if error:
        fail(error)
    now = dt.datetime.now(dt.timezone.utc).timestamp()
    with conn:
        sets = ", ".join(col + " = ?" for col in fields)
        conn.execute("UPDATE events SET " + sets + ", updated = ? WHERE id = ?",
                     list(fields.values()) + [now, payload["id"]])
        if "reminders" in fields or "start" in fields:
            row2 = event_row(conn, payload["id"])
            _schedule_fires(conn, payload["id"], row2[5], row2[9])
    out({"ok": True, "id": payload["id"]})


def cmd_delete(args):
    if not valid_id(args.id):
        fail("invalid event id")
    conn = connect(args.db)
    if event_row(conn, args.id) is None:
        fail("event not found")
    with conn:
        conn.execute("DELETE FROM events WHERE id = ?", (args.id,))
    out({"ok": True, "deleted": args.id})


def cmd_new_calendar(args):
    name = " ".join(str(args.name or "").split())[:60]
    if not name:
        fail("calendar name required")
    color = args.color if valid_color(args.color) else "#007AFF"
    conn = connect(args.db)
    if conn.execute("SELECT 1 FROM calendars WHERE name = ?", (name,)).fetchone():
        fail("calendar already exists")
    with conn:
        conn.execute("INSERT INTO calendars (name, color, created) VALUES (?, ?, ?)",
                     (name, color, dt.datetime.now(dt.timezone.utc).timestamp()))
    out({"ok": True, "calendar": {"name": name, "color": color}})


def cmd_delete_calendar(args):
    name = " ".join(str(args.name or "").split())[:60]
    conn = connect(args.db)
    if conn.execute("SELECT 1 FROM calendars WHERE name = ?", (name,)).fetchone() is None:
        fail("calendar not found")
    if name == DEFAULT_CALENDAR:
        fail("the default calendar cannot be deleted")
    with conn:
        conn.execute("DELETE FROM events WHERE calendar = ?", (name,))
        conn.execute("DELETE FROM calendars WHERE name = ?", (name,))
    out({"ok": True, "deleted": name})


def cmd_due(args):
    """Reminders whose due time has passed and are not done → returns + marks done."""
    conn = connect(args.db)
    now = parse_iso(args.now) or dt.datetime.now(dt.timezone.utc).isoformat()
    rows = conn.execute(
        "SELECT f.event_id, f.due, e.title, e.calendar, e.start FROM reminder_fires f "
        "JOIN events e ON e.id = f.event_id WHERE f.done = 0 AND f.due <= ? ORDER BY f.due LIMIT 20",
        (now,)).fetchall()
    with conn:
        for row in rows:
            conn.execute("UPDATE reminder_fires SET done = 1 WHERE event_id = ? AND due = ?",
                         (row[0], row[1]))
    out({"due": [{"id": r[0], "due": r[1], "title": r[2], "calendar": r[3], "start": r[4]}
                 for r in rows], "now": now})


# ═════════════ ICS IMPORT / EXPORT ═════════════

def ics_unfold(text):
    lines = []
    for raw in text.splitlines():
        if raw.startswith((" ", "\t")) and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw.rstrip("\r"))
    return lines


def ics_parse_datetime(value, params=""):
    """VCALENDAR DTSTART value: 20261101T090000Z, 20261101T090000 (floating), 20261101."""
    value = value.strip()
    tzid = None
    for part in params.split(";"):
        if part.startswith("TZID="):
            tzid = part[5:]
    all_day = False
    tz = None
    try:
        if tzid:
            try:
                from zoneinfo import ZoneInfo
                tz = ZoneInfo(tzid)
            except Exception:
                tz = None
        if re.fullmatch(r"\d{8}", value):
            all_day = True
            d = dt.datetime(int(value[0:4]), int(value[4:6]), int(value[6:8]))
        elif value.endswith("Z"):
            d = dt.datetime.strptime(value[:-1], "%Y%m%dT%H%M%S").replace(tzinfo=dt.timezone.utc)
        else:
            d = dt.datetime.strptime(value, "%Y%m%dT%H%M%S")
            if tz:
                d = d.replace(tzinfo=tz)
    except (ValueError, IndexError):
        return None
    if all_day:
        return ("allday", d.date())
    return ("timed", d.astimezone(dt.timezone.utc))


def ics_rrule_line(params):
    rule = params.strip()
    return rule if parse_rrule(rule) else ""


def ics_parse_file(path):
    """Minimal VCALENDAR reader → list of raw event dicts (local naive datetimes)."""
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        fail("cannot read file: " + str(error))
    events = []
    current = None
    for line in ics_unfold(text):
        if line.startswith("BEGIN:VEVENT"):
            current = {}
        elif line.startswith("END:VEVENT"):
            if current and current.get("start") is not None:
                events.append(current)
            current = None
        elif current is not None and ":" in line:
            name, _, value = line.partition(":")
            name = name.upper()
            params = ""
            if ";" in name:
                name, _, params = name.partition(";")
            key = name.split(".", 1)[0]  # X-GOOGLE... prefixes
            if key == "SUMMARY":
                current["title"] = value
            elif key == "DESCRIPTION":
                current["notes"] = value.replace("\\n", "\n").replace("\\,", ",")
            elif key == "LOCATION":
                current["location"] = value.replace("\\,", ",")
            elif key == "DTSTART":
                current["start"] = ics_parse_datetime(value, params)
            elif key == "DTEND":
                current["end"] = ics_parse_datetime(value, params)
            elif key == "RRULE":
                current["rrule"] = ics_rrule_line(value)
    return events


def cmd_import(args):
    conn = connect(args.db)
    cal = args.calendar or "Imported"
    if conn.execute("SELECT 1 FROM calendars WHERE name = ?", (cal,)).fetchone() is None:
        color = CAL_COLORS[len(cal) % len(CAL_COLORS)]
        with conn:
            conn.execute("INSERT INTO calendars (name, color, created) VALUES (?, ?, ?)",
                         (cal, color, dt.datetime.now(dt.timezone.utc).timestamp()))
    raw_events = ics_parse_file(args.file)
    imported = 0
    skipped = 0
    now = dt.datetime.now(dt.timezone.utc).timestamp()
    proc_tz = _process_tz()
    with conn:
        for raw in raw_events:
            s_kind, s_value = raw.get("start", (None, None))
            e_kind, e_value = raw.get("end", (None, None))
            if s_kind is None:
                skipped += 1
                continue
            if s_kind == "allday":
                start = s_value.isoformat()
                end_day = e_value if e_kind == "allday" else s_value
                end = end_day.isoformat()
                all_day = 1
            else:
                start = s_value.astimezone(proc_tz).isoformat()
                if e_kind == "timed":
                    end = e_value.astimezone(proc_tz).isoformat()
                else:
                    end = (s_value + dt.timedelta(hours=1)).astimezone(proc_tz).isoformat()
                all_day = 0
            conn.execute("INSERT INTO events (id, calendar, title, notes, location, start, end, all_day, rrule, reminders, created, updated) "
                         "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?)",
                         (new_id(), cal, str(raw.get("title") or "Event")[:200],
                          str(raw.get("notes") or "")[:5000], str(raw.get("location") or "")[:200],
                          start, end, all_day, raw.get("rrule") or "", now, now))
            imported += 1
    out({"ok": True, "imported": imported, "skipped": skipped, "calendar": cal})


def cmd_export(args):
    conn = connect(args.db)
    cal_filter = args.calendar or None
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parts = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//MacShell//Calendar//EN",
             "CALSCALE:GREGORIAN"]
    count = 0
    for row in conn.execute(
            "SELECT id, calendar, title, notes, location, start, end, all_day, rrule, reminders, created, updated "
            "FROM events ORDER BY start").fetchall():
        eid, cal, title, notes, location, start, end, all_day, rrule, _rem, _c, _u = row
        if cal_filter and cal != cal_filter:
            continue
        def esc(s):
            return (s or "").replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")
        parts.append("BEGIN:VEVENT")
        parts.append("UID:%s@macshell" % eid)
        parts.append("DTSTAMP:" + stamp)
        if all_day:
            d0 = local_date(start)
            d1 = local_date(end)
            if d0:
                parts.append("DTSTART;VALUE=DATE:" + d0.strftime("%Y%m%d"))
                if d1:
                    # DTEND is exclusive in ICS for date values
                    try:
                        parts.append("DTEND;VALUE=DATE:" +
                                     (d1 + dt.timedelta(days=1)).strftime("%Y%m%d"))
                    except ValueError:
                        pass
        else:
            d0 = parse_local(start)
            d1 = parse_local(end)
            if d0:
                parts.append("DTSTART:" + d0.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
            if d1:
                parts.append("DTEND:" + d1.astimezone(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"))
        if rrule:
            parts.append("RRULE:" + rrule)
        if title:
            parts.append("SUMMARY:" + esc(title))
        if location:
            parts.append("LOCATION:" + esc(location))
        if notes:
            parts.append("DESCRIPTION:" + esc(notes))
        parts.append("END:VEVENT")
        count += 1
    parts.append("END:VCALENDAR")
    path = Path(args.file).expanduser().absolute()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\r\n".join(parts) + "\r\n", encoding="utf-8")
    out({"ok": True, "path": str(path), "events": count})


# ═════════════ NATURAL-LANGUAGE PARSER ═════════════

ID_DAYS = {"senin": 0, "selasa": 1, "rabu": 2, "kamis": 3, "jumat": 4, "jum'at": 4,
           "sabtu": 5, "minggu": 6, "ahad": 6}
EN_DAYS = {"monday": 0, "mon": 0, "tuesday": 1, "tue": 1, "wednesday": 2, "wed": 2,
           "thursday": 3, "thu": 3, "friday": 4, "fri": 4, "saturday": 5, "sat": 5,
           "sunday": 6, "sun": 6}
ID_MONTHS = {"januari": 1, "februari": 2, "maret": 3, "april": 4, "mei": 5, "juni": 6,
             "juli": 7, "agustus": 8, "september": 9, "oktober": 10, "november": 11, "desember": 12}
EN_MONTHS = {"january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
             "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
             "august": 8, "aug": 8, "september": 9, "sep": 9, "october": 10, "oct": 10,
             "november": 11, "nov": 11, "december": 12, "dec": 12}


def _next_weekday(base, weekday, force_next_week=False):
    delta = (weekday - base.weekday()) % 7
    if delta == 0 or force_next_week:
        delta += 7 if (delta == 0 or force_next_week) else 0
        if delta == 0:
            delta = 7
    return base + dt.timedelta(days=delta)


def _strip_spans(raw, spans):
    """Remove matched text spans (coordinates in `low`, i.e. " " + raw.lower() + " ")
    from the original title, keeping case and collapsing whitespace."""
    if not spans:
        return raw
    merged = []
    for s, e in sorted(spans):
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    out, prev = [], 1  # low index 1 == raw index 0
    for s, e in merged:
        out.append(raw[prev - 1:s - 1])
        prev = e
    out.append(raw[prev - 1:])
    return " ".join(" ".join(out).split())


def parse_sentence(text, now=None, tz=None):
    """Converts an Indonesian/English sentence into an event preview.

    Returns {"title", "start", "end", "allDay", "reminders", "match": [...] } —
    the UI shows the preview; nothing is saved. Unknown/ambiguous parts are
    reported in "ambiguities" so the app can ask before saving.
    """
    raw = " ".join(str(text or "").split())
    if not raw:
        fail("empty text")
    now = now or dt.datetime.now()
    tz = tz or _process_tz()
    base = now.astimezone(tz)
    if base.tzinfo is None:
        base = base.replace(tzinfo=tz)
    low = " " + raw.lower() + " "
    ambiguities = []

    title = raw
    all_day = False
    target_date = None
    hour = minute = None
    duration = None
    end_dt = None
    spans = []  # (start, end) in low coordinates — stripped from the title at the end

    # ── explicit dates: 2026-11-01, 1/11, 1 Nov(ember) ──
    def strip_span(m):
        spans.append(m.span())

    m = re.search(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", low)
    if m:
        try:
            target_date = dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
            strip_span(m)
        except ValueError:
            pass  # not a real date; leave it for the time parser
    if target_date is None:
        m = re.search(r"\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?(?!\s*(?:jam|menit|minutes?|mins?|hours?|hrs?)\b)", low)
        if m:
            d_, mth = int(m.group(1)), int(m.group(2))
            yr = int(m.group(3)) if m.group(3) else base.year
            if yr < 100:
                yr += 2000
            try:
                target_date = dt.date(yr, mth, d_)
                strip_span(m)
            except ValueError:
                pass  # e.g. "14.00" — a time, not a date
    if target_date is None:
        m = re.search(r"\b(\d{1,2})\s+(jan|feb|mar|apr|mei|may|jun|jul|agu|aug|agt|sep|okt|oct|nov|des|dec)[a-z]*\.?\s*(\d{4})?\b", low)
        if m:
            month_name = m.group(2)
            month = None
            for name, num in {**ID_MONTHS, **EN_MONTHS}.items():
                if name.startswith(month_name[:3]) and len(month_name) >= 3:
                    month = num
                    break
            yr = int(m.group(3)) if m.group(3) else base.year
            if yr < 100:
                yr += 2000
            try:
                target_date = dt.date(yr, month, int(m.group(1)))
                if not m.group(3) and target_date < base.date():
                    target_date = dt.date(yr + 1, month, int(m.group(1)))
                strip_span(m)
            except (ValueError, TypeError):
                pass

    if target_date is None:
        m = re.search(r"\b(jan|feb|mar|apr|mei|may|jun|jul|agu|aug|agt|sep|okt|oct|nov|des|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\.?,?\s*(\d{4})?\b", low)
        if m:
            month_name = m.group(1)
            month = None
            for name, num in {**ID_MONTHS, **EN_MONTHS}.items():
                if name.startswith(month_name[:3]) and len(month_name) >= 3:
                    month = num
                    break
            yr = int(m.group(3)) if m.group(3) else base.year
            if yr < 100:
                yr += 2000
            try:
                target_date = dt.date(yr, month, int(m.group(2)))
                if not m.group(3) and target_date < base.date():
                    target_date = dt.date(yr + 1, month, int(m.group(2)))
                spans.append(m.span())
            except (ValueError, TypeError):
                pass

    # ── relative day words ──
    if target_date is None:
        day_words = [
            (r"\bhari ini\b|\btoday\b", 0, False),
            (r"\bbesok\b|\btomorrow\b", 1, False),
            (r"\blusa\b", 2, False),
            (r"\bminggu depan\b|\bnext week\b", 7, False),
            (r"\bminggu (?:ini|next)\b|\bthis week\b", 0, False),
        ]
        for pattern, delta, _f in day_words:
            m = re.search(pattern, low)
            if m:
                target_date = (base + dt.timedelta(days=delta)).date()
                spans.append(m.span())
                break
    if target_date is None:
        # weekday names: "jumat", "next friday", "friday next week"
        for pattern, daymap, force in [
            (r"\b(?:pada\s+)?(?:hari\s+)?(senin|selasa|rabu|kamis|jum'?at|sabtu|minggu|ahad)\b", ID_DAYS, False),
            (r"\b(?:next\s+|on\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b", EN_DAYS, None),
        ]:
            m = re.search(pattern, low)
            if m:
                name = m.group(1).replace("'", "").lower()[:6]
                wd = None
                for key, num in daymap.items():
                    if key.replace("'", "").startswith(name):
                        wd = num
                        break
                if wd is not None:
                    force_next = bool(re.search(r"(next|depan|besoknya)", low[max(0, m.start() - 20):m.end() + 12]))
                    target_date = _next_weekday(base.date(), wd, force_next)
                    spans.append(m.span())
                break

    # ── all-day hints ──
    m = re.search(r"\bsepanjang hari\b|\ball[- ]?day\b|\bsemudah itu\b", low)
    if m:
        all_day = True
        spans.append(m.span())

    # ── clock times: 14.00, 14:00, 9 malam, 2pm, jam 9, at 9am ──
    def apply_ampm(h, meridiem):
        if meridiem == "pm" and 1 <= h <= 11:
            return h + 12
        if meridiem == "am" and h == 12:
            return 0
        return h

    times = []
    noon = re.search(r"\b(?:at\s+|pada\s+)?(?:tengah hari|noon)\b", low)
    if noon:
        times.append((noon, 12, 0))
    else:
        for m in re.finditer(r"\b(?:(?:pukul|jam|at)\s*)?(\d{1,2})(?:[.:](\d{2}))?\s*(am|pm)?\s*(pagi|siang|sore|malam|subuh)?\b", low):
            h = int(m.group(1))
            if h > 23:
                continue
            minute_ = int(m.group(2)) if m.group(2) else 0
            if m.group(3):
                h = apply_ampm(h, m.group(3))
            elif m.group(4):
                # Indonesian day-part words shift the hour: "jam 9 malam" → 21:00,
                # "jam 7 sore" → 19:00, "jam 1 siang" → 13:00, "jam 12 malam" → 00:00.
                part = m.group(4)
                if part == "malam":
                    h = 0 if h == 12 else h + 12 if h < 12 else h
                elif part in ("sore", "siang"):
                    if h < 12:
                        h += 12
            # "3" alone (no prefix, no meridiem) is ambiguous — only treat bare numbers
            # when preceded by jam/pukul/at (or when the match itself carries the time
            # word, e.g. the regex consumed "jam 14.00" as one unit, or has an explicit ":")
            # Bare "HH.MM"/"HH:MM" with two-digit minutes is also an explicit time.
            matched = m.group(0)
            prefix = low[max(0, m.start() - 10):m.start()]
            if not m.group(3) and not m.group(4) \
                    and not re.search(r"(jam|pukul|at|:)\s*$", prefix) \
                    and not re.match(r"(jam|pukul|at)\s", matched) \
                    and ":" not in matched \
                    and m.group(2) is None:
                continue
            times.append((m, h, minute_))
    if times:
        m, h, minute_ = times[0]
        hour, minute = h, minute_
        if len(times) > 1:
            m2, h2, min2 = times[1]
            if (h2, min2) > (h, minute_):
                end_dt = (h2, min2)
                spans.append((m.span()[0], m2.span()[1]))  # "2pm to 3:30pm" — remove the whole range
        else:
            spans.append(m.span())
    elif all_day:
        pass
    else:
        ambiguities.append("no time found — defaults to 09:00, 1 hour")
        hour, minute = 9, 0

    # ── durations: selama 2 jam, 1.5 jam, 30 menit, for 2 hours ──
    m = re.search(r"\b(?:selama|for|durasi)\s+(\d+(?:[.,]\d+)?)\s*(jam|menit|minutes?|mins?|hours?|hrs?|h)\b", low)
    if m:
        value = float(m.group(1).replace(",", "."))
        unit = m.group(2)
        duration = dt.timedelta(hours=value) if unit[0] in ("j", "h") else dt.timedelta(minutes=value)
        spans.append(m.span())
    elif end_dt is not None:
        pass

    if target_date is None:
        target_date = base.date()
        if "no time found" in " ".join(ambiguities):
            pass
    try:
        start_dt = base.replace(year=target_date.year, month=target_date.month, day=target_date.day,
                                hour=hour or 0, minute=minute or 0, second=0, microsecond=0)
    except ValueError:
        fail("internal: invalid datetime")
    if end_dt is not None and not all_day:
        end_hour, end_min = end_dt
        end_dt2 = start_dt.replace(hour=end_hour, minute=end_min)
        if end_dt2 <= start_dt:
            end_dt2 += dt.timedelta(days=1)
        end = end_dt2
    elif duration is not None:
        end = start_dt + duration
    elif all_day:
        end = start_dt
    else:
        end = start_dt + dt.timedelta(hours=1)

    # ── "tanpa pengingat" / "no reminder" — strip from the title too ──
    m = re.search(r"\btanpa pengingat\b|\bno reminder\b", low)
    if m:
        spans.append(m.span())
    # remove all matched date/time/duration spans from the original title text
    title = _strip_spans(raw, spans)
    title = re.sub(r"\s{2,}", " ", title)
    title = re.sub(r"\s+\b(tanggal|pada|at|on|hari)\b\s*$", "", title).strip(" ,-–:")
    m = re.match(r"^(reminder|pengingat|ingatkan)\b[: ]*", title.lower())
    if m:
        title = title[m.end():].strip() or "Reminder"
        title = title[:120] if title else "Reminder"
    if not title:
        title = "Event"
        ambiguities.append("no title — using 'Event'")

    # default reminder: 15 minutes before the start (negative offset = before, per the bridge convention)
    reminders = [-900] if not re.search(r"\btanpa pengingat\b|\bno reminder\b", low) else []

    preview = {
        "title": title[:200],
        "start": start_dt.astimezone(tz).isoformat() if not all_day else target_date.isoformat(),
        "end": end.astimezone(tz).isoformat() if not all_day else target_date.isoformat(),
        "allDay": all_day,
        "reminders": reminders,
        "ambiguities": ambiguities,
    }
    out({"preview": preview})


def main():
    parser = argparse.ArgumentParser(prog="calendar.py", description=__doc__)
    parser.add_argument("--db", default=default_db())
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("calendars")
    p.set_defaults(func=cmd_calendars)
    p = sub.add_parser("events")
    p.add_argument("--from", dest="from_", required=True)
    p.add_argument("--to", dest="to", required=True)
    p.add_argument("--calendar", default=None)
    p.add_argument("--query", default="")
    p.set_defaults(func=cmd_events)
    p = sub.add_parser("get")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_get)
    p = sub.add_parser("new")
    p.add_argument("--json", required=True)
    p.set_defaults(func=cmd_new)
    p = sub.add_parser("save")
    p.add_argument("--json", required=True)
    p.set_defaults(func=cmd_save)
    p = sub.add_parser("delete")
    p.add_argument("--id", required=True)
    p.set_defaults(func=cmd_delete)
    p = sub.add_parser("new-calendar")
    p.add_argument("--name", required=True)
    p.add_argument("--color", default="#007AFF")
    p.set_defaults(func=cmd_new_calendar)
    p = sub.add_parser("delete-calendar")
    p.add_argument("--name", required=True)
    p.set_defaults(func=cmd_delete_calendar)
    p = sub.add_parser("due")
    p.add_argument("--now", default=None)
    p.set_defaults(func=cmd_due)
    p = sub.add_parser("import")
    p.add_argument("--file", required=True)
    p.add_argument("--calendar", default="Imported")
    p.set_defaults(func=cmd_import)
    p = sub.add_parser("export")
    p.add_argument("--file", required=True)
    p.add_argument("--calendar", default=None)
    p.set_defaults(func=cmd_export)
    p = sub.add_parser("parse")
    p.add_argument("--text", required=True)
    p.add_argument("--now", default=None, help="override the current time (ISO, for tests)")
    p.set_defaults(func=lambda args: parse_sentence(args.text, now=parse_local(args.now)))
    args = parser.parse_args()
    try:
        args.func(args)
    except sqlite3.Error as error:
        fail("database error: " + str(error))
    except OSError as error:
        fail("i/o error: " + str(error))


if __name__ == "__main__":
    main()
