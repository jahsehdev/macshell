# Golden Gate 27 — GG-09 report (Notes application)

Date: 2026-10-31
Scope: GG-09
Status: implemented, deployed to the active shell, all flows verified end-to-end
on the 1280×800 session (including real pointer drawing on the live canvas)

## Result

A new **MacShell Notes** application, built from scratch inside the shell (not a
separate process), in the spirit of macOS Notes but with the MacShell identity:

- **Sidebar**: search field, note count, note list with title, snippet, drawing
  marker (✏), and relative timestamps ("Today 14:40", "Yesterday", date).
- **Text view**: title + body editor, autosave 800 ms after the last edit.
- **Drawing view**: freehand pen plus Line / Rect / Ellipse shape tools, an 8-color
  palette, a width slider (1–14 px), Clear, undo/redo, and an empty-state hint.
- **Toolbar**: Text | Drawing segmented control, Undo, Redo, New (+), Delete (✕,
  click twice to confirm — the button turns red and shows "Click again to delete"
  for 3 s), and an Export popover (Markdown / Text / PNG / SVG).
- Frameless window in the ClockApp pattern (`Window` + `WindowControls` + Corners
  palette), resizable, with system move/resize edges.

## Storage

Everything lives in SQLite at `~/.local/share/macshell/notes/notes.db`, accessed
through a one-shot CLI `MacShell/bin/notes.py` (JSON on stdout, no shell-outs, no
network):

| Command | Purpose |
| --- | --- |
| `list [--query Q]` | summaries for the sidebar (title, snippet, has_drawing, words) |
| `get --id ID` | full note + strokes |
| `new [--title T]` | create a note |
| `save --json {...}` | title, body, and (optionally) the full stroke list |
| `delete --id ID` | remove note + strokes |
| `export --id ID --out PATH --format md\|txt\|png\|svg` | export |

Strokes are stored **vector-style**: every stroke is
`{tool, color, width, points[]}` with coordinates normalised to the 0..1 canvas
box and width as a fraction of canvas width. A drawing therefore stays editable
after reopening and renders identically at any canvas or export size. The CLI
validates every stroke on save (tool whitelist, `#rrggbb` colours, width 0.0005–0.2,
coordinates clamped to −0.05..1.05, even point count) and drops malformed entries.

Exports: Markdown and Text are written from title + body (md notes that a drawing
exists); SVG is rendered by a dependency-free string builder; PNG uses Pillow
(already present, 13.0.0) at 1200×900. The export directory
(`~/Documents/MacShell Notes`) is created on demand and file names are de-collided
with a numeric suffix.

## What changed

- `MacShell/NotesApp.qml` — the application (sidebar, editor, canvas, toolbar,
  export popover, autosave timer, delete confirmation, IPC in `shell.qml`).
- `MacShell/bin/notes.py` — storage CLI (SQLite, WAL, foreign keys, stroke
  validation, four export formats).
- `MacShell/shell.qml` — `NotesApp { id: notesApp }` registration and the
  `notes` IPC target (`open`, `create`).
- `bin/macshell-notes` — launcher script (`qs -c MacShell ipc call notes open`).
- `share/applications/macshell-notes.desktop` — freedesktop entry
  (Keywords include "Catatan"; icon `@DATA_HOME@/macshell/icons/notes.png`).
- `share/macshell/icons/notes.png` and `MacShell/assets/notes.png` — icon
  (yellow note + red dot, rendered with ImageMagick, no downloaded assets).
- `MacShell/tests/test_notes.py` — 9 unit tests (see below).

## Bugs found by the end-to-end verification (all fixed)

1. **`root.drawingCanvas` is not a thing.** The canvas is a local id, so every
   `root.drawingCanvas.requestPaint()` threw
   `TypeError: Cannot call method 'requestPaint' of undefined` and strokes never
   painted. Fixed to the plain id reference.
2. **Export failed when the target directory did not exist.** `cmd_export` wrote
   into `~/Documents/MacShell Notes/` without creating it; the failure only
   surfaced as a desktop notification. The CLI now `mkdir -p`s the parent.
3. **Stale-selection race after delete.** `deleteProc`'s handler called
   `refreshList()` (async) and then `selectAfterDelete()` (sync), so re-selection
   read the *old* list and re-selected the just-deleted note. Consequence observed:
   a second delete clicked the phantom id (no-op in the DB) and the UI kept the
   deleted note loaded — the exact path that could resurrect a deleted note through
   a pending autosave. Fixed by deferring `selectAfterDelete()` until the refreshed
   list arrives (`afterDelete` flag consumed in the `listProc` handler);
   `requestDelete()` also clears `dirty` before deleting so a pending autosave can
   never resurrect anything.

## Verification

The flows were driven through a temporary IPC hook (`notestest`, same pattern as
GG-08's `recordtest`), which was **removed after verification** — `qs ipc show` no
longer lists it, and the deployed file matches the repository byte-for-byte.

- App opens from IPC and the empty state renders correctly; note creation,
  seeding, and autosave land in SQLite (`notes.py list` shows title/snippet/words).
- Drawing: pen/rect/ellipse/line strokes pushed through the hook render on the
  canvas (screenshot with all four shapes); **real pointer drawing was then done
  live on the canvas** — freehand strokes appeared, autosaved, and persisted
  (18 strokes in the DB).
- Undo/redo: undo moves strokes to the redo stack and autosave persists the
  smaller list; redo restores them (DB counts checked at every step). Clear moves
  all strokes to the redo stack (DB → 0), redo restores them (DB → back).
- Persistence: a full shell reload (all QML state destroyed) was followed by
  reopening the note — title, body, and all 18 strokes re-rendered from SQLite
  alone. Window close + reopen behaves the same.
- Export: md and png produced under `~/Documents/MacShell Notes/`; the PNG is a
  1200×900 RGBA image containing the drawing; md contains the title, body, and a
  drawing footnote.
- Delete: a temporary note was deleted (twice-click confirm) and disappeared from
  the DB; `get` then returns `note not found`; the selection fell back to the
  remaining note with its strokes intact.
- Text view screenshot with the saved note (title, body, sidebar timestamp).
- Shell reload after every change: `Configuration Loaded`, no new QML errors.
- Unit tests: `python3 -m unittest config/quickshell/MacShell/tests/test_notes.py`
  → 9/9 OK (CRUD roundtrip, stroke validation, search filters, all four export
  formats + suffix correction + missing-directory creation, id validation,
  derived title, plus integration assertions that the QML keeps using the CLI
  contract, the shell registers the app + IPC target, and the launcher/desktop
  entry/icon files exist). `test_screen_recording.py` also gained a GG-08
  regression test (attached `--audio=` form, `recordAudio` in `settingKeys`)
  and its VM fixture gained the `recordAudio` fields the GG-08 code reads —
  4/4 OK. No packages were installed.
- Screenshots: `/tmp/notes-1-open.png`, `/tmp/notes-2f-drawing.png`,
  `/tmp/notes-4-user-strokes.png`, `/tmp/notes-6-reopen.png`,
  `/tmp/notes-7-persisted-drawing.png`, `/tmp/notes-8-textview.png`,
  `/tmp/notes-9-final.png`.

## Notes / limitations

- One note per body; folders exist in the schema (`notes.folder`) but the UI is a
  single flat list for now — folders can be added without a migration.
- The redo stack is session-only (like most editors); the committed stroke list is
  what persists.
- No pointer/key injector is available, so toolbar clicks were exercised through
  the temporary IPC hook; the real pointer path was verified by drawing on the
  canvas directly.
- Notes text is written to a plain SQLite file, ready to enter Luma's local
  context later (A3) from this source contract.

## Deployment

`NotesApp.qml`, `shell.qml`, and `bin/notes.py` were copied to
`~/.config/quickshell/MacShell/...` and verified with `cmp` (identical). The
launcher, desktop entry, and icons were copied to `~/.local/bin`,
`~/.local/share/applications`, and `~/.local/share/macshell/icons`. Nothing was
installed and no model was downloaded.
