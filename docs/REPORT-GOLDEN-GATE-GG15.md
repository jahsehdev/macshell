# Golden Gate — GG-15 Calendar and Reminders (data bridge + GNOME Calendar)

Date: 2026-10-31
Status: implemented, deployed to the active shell, verified end-to-end on the live session

## Decision

The plan originally called for a custom `CalendarApp.qml`. Following a mid-stage
decision, **GNOME Calendar 51** (already themed by the MacTahoe GTK 4 setup) is the
calendar UI, and MacShell keeps a **local data bridge** for the parts GNOME Calendar
does not cover: the natural-language parser, reminders that fire while no window is
open, and ICS import/export. All inference and storage stay offline and local.

## What was built

### Data bridge — `MacShell/bin/calendar.py`

One-shot CLI, JSON on stdout, SQLite at `~/.local/share/macshell/calendar/calendar.db`
(same pattern as `bin/notes.py`). No network, no new packages.

- `calendars` / `new-calendar` / `delete-calendar` — named calendars with colors;
  the default `Home` calendar is created on first connect and cannot be deleted.
- `new` / `save` / `get` / `delete` — event CRUD. Validation covers calendar
  existence, `end >= start`, id shape, unsupported RRULEs and reminder offsets.
- `events --from --to [--calendar] [--query]` — window query. Events store ISO-8601
  UTC strings, so Asia/Jakarta (and any other zone) round-trips without the process
  timezone mattering. All-day events store date-only strings.
- Recurrence: a minimal RRULE (`FREQ=DAILY|WEEKLY|MONTHLY`, `INTERVAL`, `BYDAY`,
  `COUNT`/`UNTIL`) expanded on read for the queried window — occurrences are never
  materialised in the database.
- `reminders`: offsets in seconds stored on the event (negative = before start),
  with a `reminder_fires` table marking each fire done.
- `due [--now ISO]` — returns reminders that are due and marks them fired; this is
  the scheduler's endpoint.
- `import --file` / `export --file` — ICS 2.0 with folded lines, UTC datetimes,
  date-only all-day values (DTEND exclusive), RRULE passthrough and escaping.
- `parse --text "..." [--now ISO]` — sentence parser for Indonesian and English:
  relative days (hari ini/besok/lusa/today/tomorrow), weekday and month names in
  both languages, explicit dates (`2026-11-01`, `5/11`, `25 desember`, `december 15`),
  clock times (`jam 14.00`, `pukul 19`, `9 malam`, `2pm`, `at noon`, `06.30`),
  ranges (`jam 10 sampai jam 12`, `2pm to 3:30pm`), durations (`selama 45 menit`,
  `1.5 jam`), all-day hints and "tanpa pengingat". Text outside the matched spans
  becomes the title (case preserved; all matches are stripped in one pass from the
  original string). Anything the parser had to guess is reported in `ambiguities`;
  the caller decides whether to save. The parser never saves by itself.

A note on a Python gotcha: because the file is named `calendar.py` it shadows the
stdlib `calendar` module for `_strptime`; the script drops its own directory from
`sys.path` at startup to keep `datetime.strptime` working.

### Reminder scheduler — `MacShell/shell.qml` (Scope)

- A 30 s `Timer` (with `triggeredOnStart`) polls `calendar.py due` through a
  `Process` that lives in the shared `Scope`, so reminders fire while no calendar
  window is open — a GG-15 acceptance criterion.
- Every due reminder is posted with `notify-send -a Calendar`, which the MacBar
  notification stack shows as a Liquid Glass toast.

### Quick-add — `qs -c MacShell ipc call calendar add "rapat besok jam 10"`

- Runs the parser, then: unambiguous → saves the event (default reminder −900 s)
  and posts a "Terjadwal" toast with the formatted time; ambiguous → posts a
  "Periksa dulu — belum disimpan" preview toast and saves nothing, matching the
  "ask about ambiguous dates" criterion.
- `qs -c MacShell ipc call calendar due` also exists for manual scheduler pokes.

### GNOME Calendar integration

- `MacShell/MacDock.qml`: `org.gnome.Calendar` added to `defaultPinned`.
- `MacShell/UpstreamBar/MacBar.qml`: clicking the long date in the menu-bar
  calendar popup closes the popup and launches GNOME Calendar
  (`gtk-launch org.gnome.Calendar`), with a hover highlight on the date.
- `~/.config/macdock/pinned.json` was repaired (it had accumulated 99 entries,
  including one id 13 times; now 22 unique) and pins `org.gnome.Calendar` after
  Files.
- The app inherits the MacTahoe GTK 4 theme and the native-minimize integration
  through `macshell-gnome-apps-setup`, which is already installed.

## Known limits (by design, for this stage)

- Events saved in the bridge database do **not** appear inside GNOME Calendar's own
  store (Evolution Data Server); the bridge is for parsing, reminders and context.
  Moving events into GNOME Calendar is done via `calendar.py export` + ICS import.
- The quick-add entry point is IPC only for now; wiring it into Spotlight/Luma is
  left for the context stage (A3), which will read the same bridge.

## Verification

- Unit tests: `python3 -m unittest config/quickshell/MacShell/tests/test_calendar.py`
  → 12/12 OK (calendar CRUD, event CRUD, recurrence expansion in a window query,
  all-day events, the reminder scheduler firing exactly at start−15 min and staying
  fired, Indonesian and English parser cases, ambiguity/default handling, a
  timezone cross-check (same sentence in Jakarta vs London), ICS roundtrip,
  invalid-id rejection, plus integration assertions that the shell runs the bridge
  scheduler and GNOME Calendar is the launched app). The full set run together
  with `test_notes.py` and `test_system_info.py` is 26/26 OK.
- Live shell: reload reports `Configuration Loaded` with no new QML errors
  (`qmllint` exits 255 on `shell.qml` both before and after these changes — a
  pre-existing tooling issue with Quickshell imports, not introduced here).
- End-to-end reminder: an event with a −900 s reminder was inserted into the live
  database; the 30 s Scope poll consumed the fire (a second `due` call returned
  nothing) and the toast appeared as "Calendar / <title> / Event time HH:mm"
  (screenshot `/tmp/cal-reminder-toast.png`).
- Quick-add: `calendar add "rapat desain besok jam 14.00 selama 1 jam"` saved the
  event (14:00 WIB, reminder −900) while `calendar add "obrolan santai"` was held
  back with the preview toast. Test events were deleted afterwards; the live
  database is empty again.
- Deployed copies verified with `cmp`: `bin/calendar.py`, `shell.qml`,
  `MacDock.qml`, `UpstreamBar/MacBar.qml`.

## Files

- `config/quickshell/MacShell/bin/calendar.py` (new)
- `config/quickshell/MacShell/shell.qml` (scheduler + quick-add + `calendar` IPC)
- `config/quickshell/MacShell/MacDock.qml` (Calendar pinned by default)
- `config/quickshell/MacShell/UpstreamBar/MacBar.qml` (date click opens Calendar)
- `config/quickshell/MacShell/tests/test_calendar.py` (new)
