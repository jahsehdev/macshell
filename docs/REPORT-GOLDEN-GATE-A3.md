# Golden Gate 27 — A3 personal-context foundation report

Date: 2026-10-31
Scope: A3 (local index + source contracts) and the first GG-04/I1 wiring step
(local results in Search or Ask)
Status: implemented, deployed to the active shell, verified

## Result

| Piece | State |
| --- | --- |
| `bin/context.py` — one-shot CLI, JSON stdout, all offline | Done |
| Source contracts: files (fixture folders), Notes, Calendar, Mail | Done (Mail = contract only, awaiting GG-16) |
| Per-source enable/disable controls + provenance on every item | Done |
| LumaSettings "Personal context" pane (sources, folders, index) | Done |
| Search or Ask shows local results with provenance | Done (display + activation; answers citing sources follow with A2) |

## What was built

### `bin/context.py` — the personal-context bridge

One-shot CLI; JSON on stdout; storage in
`~/.local/share/macshell/context/context.db` (override with `--db` for tests).

Commands: `sources`, `enable/disable --kind KIND`, `configure --kind files
--folders`, `index [--full]`, `search --query … [--kind] [--limit]`, `forget
--kind`, `contract`.

- **files** — text files under user-configured fixture folders. Hidden
  entries, dependency/cache directories, binary blobs and files over 512 KB
  are skipped. Incremental by (path, mtime); `--full` re-reads.
- **notes** — read through the Notes CLI contract (`bin/notes.py list` /
  `get --id`). ref = note id.
- **calendar** — read through the Calendar CLI contract (`bin/calendar.py
  events`) over a −30…+90 day window. ref = event id.
- **mail** — contract only; enabled mail indexes nothing and reports
  `status: awaiting-app` (GG-16 reserves the kind).

Provenance: every item stores `{"kind", "ref", "origin", "modified",
"indexed_at", "indexer"}` and search results echo it verbatim, so answers
built on the index can cite where each fact came from. Controls: a disabled
source is skipped by both `index` and `search` — disabled sources are not
indexed. All sources default to disabled; the user turns each one on.

### LumaSettings — Personal context pane

`LumaSettings.qml` grew a "Personal context" card driven by an invisible
bridge `Item` that runs `bin/context.py` as a child process: the four sources
with switches, a fixture-folder input for Files (shown only when Files is
enabled), an "Index now" button with last-index feedback, and the privacy
note ("Personal context — notes, calendar events and folders you explicitly
add — is off by default… no external inference requests").

### Search or Ask shows local results (GG-04 wiring, first step)

- `LumaSearchMenu.qml` gained a context bridge next to the search menu: while
  the user types (250 ms debounce, queries ≥ 2 chars) it runs
  `context.py search --query … --limit 5` and keeps the parsed results. A
  late answer for an older draft is dropped, and a search requested while the
  bridge process is still running is rerun after it exits.
- `LumaSearchPanel.qml` shows the matches as rows in the answer card: a kind
  chip (Notes / Calendar / File / Mail), the title, the FTS snippet with the
  matched term highlighted, and a provenance line (origin · modified date).
  Rows are clickable; ↑/↓ selects and ↵ opens the selected row before any
  question is sent — local results work with no model installed. While
  typing, a "Searching Notes, Calendar, and files…" hint shows; results hide
  again once the draft is submitted.
- **The message card only opens for something that exists.** An idle menu —
  including one with stored conversation history — is just the search
  capsule. The card appears for local matches while typing, a live answer or
  busy state, an error, or the explicit post-Enter install hint when no model
  is installed. The stored last prompt is only shown next to a live answer.
- Activation: a Notes row opens the Notes app, a Calendar row opens GNOME
  Calendar, a file row opens the file with `xdg-open`. Mail has no app yet,
  so its rows (none exist) would simply close the menu.
- The search menu reads only the enabled sources because the bridge CLI
  already excludes disabled kinds from `search`.
- **Typing never requires a model.** The field used to be disabled while
  `controller.ready` was false, which made Search or Ask impossible to type in
  whenever no model was installed (the gated Gemma file, A2). It is now only
  disabled while Luma is busy. Enter without a model keeps the prompt visible
  next to the "Install a local model" hint instead of silently doing nothing;
  the send button is available as soon as the draft is non-empty.

## Verification

- `tests/test_context.py` 14/14 OK — sources/enable/disable/configure, files
  index + search + provenance, disabled-source exclusion, empty-query error,
  forget, contract document, LumaSettings wiring.
- `tests/test_luma_context_search.py` 8/8 OK — new: menu queries the bridge
  (debounce, `--limit 5`), stale results discarded, activation targets,
  view forwards to panel, panel renders rows with provenance + keyboard
  selection, submit opens a selected result before the readiness check, and
  the CLI result shape matches what the panel renders
  (`kind/ref/title/modified/provenance/snippet`).
- `tests/test_luma_search.py` 17/17 qmltest cases OK — the qmltestrunner harness
  instantiates the real LumaSearchView + LumaSearchPanel with a stand-in
  `contextSearch` object; new cases type with `ready=false` (field stays
  enabled, Enter does not submit silently) and assert that stored history plus
  no model leaves the menu as a bare capsule with no message card. No
  QWARN/TypeError/ReferenceError in any scenario.
- Combined run with notes/calendar/system-info suites: 51/51 OK.
- `qmllint` on the edited files exits 255 with no diagnostics — the same
  pre-existing condition as every Quickshell QML file here (also fails on
  unedited HEAD); not used as a gate.
- Deployed `bin/context.py`, `LumaSettings.qml`, `LumaSearchMenu.qml`,
  `LumaSearchView.qml`, `LumaSearchPanel.qml` to `~/.config/quickshell/MacShell/`
  and verified byte-for-byte with `cmp`. Two shell reloads report
  `Configuration Loaded`; the only log errors are the known pre-existing
  `spotlightgooey` shader `#include` warnings.
- Live data: the real note `20261031140535-cb11d6f3` ("Rencana kerja minggu
  44") is indexed with provenance; `context.py search --query "rencana minggu"`
  returns it with a highlighted snippet. Calendar indexed
  0 events (the live GNOME-Calendar bridge store is intentionally empty after
  the GG-15 cleanup). Files remains disabled with no folders configured.
- Live UI proof: with the draft "rencana minggu" the open Search or Ask panel
  rendered the note row — Notes chip, title, highlighted snippet, and
  "Notes · 31 Oct 2026" provenance — below a focused, typeable search field
  (`/tmp/opencode/luma-result-crop.png`), with the model-install hint below.
  With an empty draft the menu is only the search capsule; no message card
  opens for stored history (`/tmp/opencode/luma-idle-crop.png`).

## Not done / next

- **Answers that cite sources** (the rest of GG-04) needs Luma inference
  (A2): the Gemma 3 1B GGUF is still gated on the Hugging Face download.
- Files has no folders configured yet on the live machine; the pane's
  folder input is the user's step.
- `forget`/`disable` round-trip on the live shell is covered by the CLI tests;
  no temporary IPC hooks were added and none remain.
- GG-16 Mail will extend the `mail` kind when it lands.
