# Golden Gate execution report — November 2, 2026

Status: **Implementation and selective deployment completed for the features described below. The full plan remains incomplete where model weights, dependencies, browser activation, account connectors, or real-device verification are still required.**

**Later November 2 update:** At the user's request, the dedicated MacShell Calendar and Mail application instances, IPC window entry points, commands, and desktop launchers were removed from the project and active installation. The menu-bar calendar now opens GNOME Calendar. Existing local data and calendar reminder/context services are retained. Calendar/Mail implementation and validation details below describe the earlier implementation, not current application availability.

**Further November 2 update:** The user also cancelled MacShell Android, Photos, and Rename. Their runtime instances, IPC window entry points, commands, and desktop launchers are removed from both the project and active installation. Implementation and validation details for those applications below are historical; the applications are no longer available.

## Confirmed requirements

The user authorized implementation of the existing English plan and supplied the animation reference directly. The video is no longer the authority for these animation details:

- Visual Intelligence: a moving multicolor glow follows the selected region/window perimeter before results appear. Linux maps Command to Super, so the shortcut is **Super+Shift+6**.
- Menu bar: the chevron collapses/expands tray icons using clipped slide/width transitions. Displays without a physical notch use the menu boundary as the clipping edge.
- Search or Ask: 55 ms opacity and 85 ms scale transitions, without the previous 380 ms bounce. Repeated opening preserves cached rendering resources.
- Shared window controls: 110 ms hover scaling and press feedback on red/yellow/green controls.
- Liquid Glass: continuous live material controls and a persisted **Show Borders** setting. Reduced Motion disables the new transitions/loops where applicable.

The MacShell/Luma identity, offline-only AI, four new applications, Android-first mirroring, personal file/mail/calendar context, and LAN-only albums remain unchanged.

## Starting state and preserved work

Existing source already contained the previous UI/accessibility/XL-widget, recorder-audio, Notes/drawing, Calendar data bridge, Gemma catalog/import, and context-index work. This execution extends that work. It does not claim to have authored those earlier changes.

Continuous GlassMaterial/preview work also changed in the shared repository during this execution. Those changes were preserved and their required preview assets were included in the deployment. An exact endpoint calculation was added to avoid floating-point drift at the material slider endpoints.

Backup of the repository and active Quickshell configuration before changes:

`/home/icentry/dock-config-backup/golden-gate-execution-20261102-165310`

Existing preference files and machine-specific Hyprland settings were preserved. The new Visual Intelligence binding/layer rule was appended to the active Hyprland configuration rather than replacing it.

## Feature status

| ID | Current result | Remaining work or verification |
| --- | --- | --- |
| GG-01 | Tray collapse/expand animation deployed; right-click opens hidden-item overflow | Real pointer/keyboard verification of the new collapse behavior on the live display |
| GG-02 | Rename Assistant provides a local text-title suggestion, editable preview, no-overwrite rename, extension preservation, and an Ask Luma handoff | Model-generated semantic filename suggestions need Gemma inference; desktop context-menu integration remains an extension |
| GG-03 | Fast Search or Ask transitions deployed; cached views, focus, rapid reopen, and microphone reset exercised in Qt tests | Live desktop interaction beyond the automatic reload |
| GG-04 | Luma reads bounded source excerpts from enabled local context-index sources; Mail joins the existing file/Notes/Calendar index | The Gemma file is missing, so real cited answers have not been generated or validated |
| GG-05 | MacShell Android launcher/window lists ADB devices, starts an owned scrcpy process, and disconnects it | This sandbox cannot access USB or ADB sockets; pairing, input, audio, resizing, and disconnection require a real-device test |
| GG-06 | Continuous material preferences/preview preserved and deployed; short interpolation on existing scalar controls | Visual checks on the live desktop, particularly shader appearance |
| GG-07 | Show Borders added to Appearance accessibility settings and shared panel strokes | Native third-party GTK/Qt applications are outside this QML setting's scope |
| GG-08 | Existing screen/region recording with audio preserved | No new live recording was performed in this execution |
| GG-09 | Existing MacShell Notes application and drawing preserved | No new Notes redesign in this execution |
| GG-10 | Reusable pull-to-refresh added to Calendar/Mail/Photos lists, with threshold and busy protection | Additional MacShell views and browser gestures are not globally modified |
| GG-11 | New MacShell Mail window: EML/MBOX import, duplicate suppression, local inbox, plain-text viewer, persistent drafts, reply prompt handoff | IMAP/SMTP account connectors and inserting a generated reply back into the draft are not implemented; real smart replies need a model |
| GG-12 | Firefox extension source supports local topic rules, native grouping where available, topic-list fallback, and undo | Tested with API mocks; actual Firefox activation and local-model classification remain pending |
| GG-13 | Structured page customizations: reading layout, larger text, focus, reset; Try and per-site Save | This is a bounded template implementation, not a general AI extension generator |
| GG-14 | Browser background watches persist URL/selector/contains conditions, establish baselines, rebuild alarms, and support pause/remove | Real Firefox/site checks pending; checks run while Firefox is active; login-only, redirects, and JS-only content have limits |
| GG-15 | New MacShell Calendar replaces the GNOME Calendar handoff: month/week views, agenda, event CRUD, natural-language preview, recurrence, all-day, ICS import/export | Reminder scheduler remains the existing shell-owned backend; live notification verification pending |
| GG-16 | New MacShell Photos: local library, thumbnail grid/list, viewer, album assignment, non-destructive export, rotation, square crop | Generative Clean Up, Extend, and Spatial Reframing are not implemented; they require separate local models and resource research |
| GG-17a | Existing XL widgets preserved | No new changes to XL layouts in this execution |
| GG-17b | Explicit LAN album host with random per-session links, read-only default, optional image uploads, bounded files, token checking, and revocation by stopping the host | TCP listening is blocked in this sandbox; no real LAN/two-client verification has occurred; QR presentation is not implemented |
| GG-18 | Local whisper.cpp STT and espeak-ng TTS adapters, speech-model picker, microphone handoff, and Read/Stop controls prepared | whisper-cli, a local speech model, and espeak-ng are missing; real transcription/playback and voice/speed selection UI are pending |
| GG-19 | Region/window selection, animated perimeter glow, explicit capture, local OCR adapter, result preview, and Ask Luma handoff deployed | Tesseract/language data are missing; arbitrary image understanding and direct event extraction need additional local capabilities |

## New applications and entry points

The applications use the existing Quickshell process and local Python/SQLite bridges. Calendar, Mail, and Photos are separate application windows sharing theme/control components; Notes remains its existing dedicated window.

| Entry point | Command |
| --- | --- |
| Visual Intelligence | `qs -c MacShell ipc call visual open` or Super+Shift+6 |
| Browser extension source | `~/.local/share/macshell/browser/manifest.json` |

Load the browser source temporarily using Firefox's development add-on loader as documented in `share/macshell/browser/README.md`. No Firefox profile was silently changed and no extension was submitted/published.

New local data:

- Mail messages/drafts and Photos metadata: `~/.local/share/macshell/studio/studio.db`.
- Calendar: existing `~/.local/share/macshell/calendar/calendar.db`.
- Uploaded shared-album images: `~/.local/share/macshell/photos/uploads/`.
- Temporary selected-screen captures: `~/.cache/macshell/visual/` with bounded retention.
- Local speech configuration: `~/.config/macshell/voice.json` after a model is selected.

Mail renders plain text and does not load remote HTML images. File rename and photo export refuse collisions. Photo edits leave originals unchanged. LAN sharing exposes registered album files through IDs, not arbitrary filesystem paths; stopping/restarting generates a new token. No cloud inference endpoint or fallback was added.

## Validation

- The full MacShell Python test discovery ran **106 tests: 105 passed, 1 failed**. The remaining failing test is `test_launchpad_menubar.test_render_and_lifecycle`. Running that test against the pre-change backup produced the same internal result, **6 passed / 3 failed**. It is recorded as a pre-existing failure, not hidden or marked passing.
- The top-level installer/Luma suite passes **33 tests**; its Luma-specific subset passes **26 tests**, including enabled-source exclusion and bounded cited excerpts.
- New Studio flows: **9 tests passed**, covering real Calendar CRUD, EML deduplication, draft persistence/deletion, plain-text handling, Mail indexing/disable, non-destructive photo export, filename collisions, LAN token/route validation, and invalid capture geometry.
- Search tests pass, including **19 Qt interaction cases** inside the Python harness. The previous long-bounce assertion was replaced with the user's short, non-overshooting expansion contract. Resetting microphone morph state fixes rapid reopen behavior exposed by the shorter transition.
- Browser tests: **3 passed** with mocked WebExtension APIs, covering grouping/undo, watch baseline/change/pause/removal, and rejecting arbitrary page actions. These do not establish real Firefox compatibility.
- Continuous material tests: **5 passed**. Preference normalization tests also passed.
- Qt 6's real `qmllint` checked the changed/new QML files with **zero error diagnostics**; existing dynamic-object/import warnings remain. The similarly named `/usr/bin/qmllint` was not relied upon as the Qt 6 validator.
- Calendar, Mail, Photos, and the glow were rendered offscreen using isolated sample data. Screenshots are in `docs/ui-previews/golden-gate-execution/`. Offscreen rendering does not prove Wayland selection, capture, or input works.
- Local TCP listening, live Quickshell IPC, Wayland capture access, and ADB/USB access are denied in this execution environment. Runtime/backend/device tests that depend on them were not claimed successful.

## Deployment and reload

The selected configuration files, launchers, desktop entries, browser source, and required material-preview asset were copied into the active user installation. A deployment manifest is stored with the backup. Source and deployed payloads were compared.

The first hot reload failed because the new implicit QML types were not recognized. An explicit relative namespace import (`import "." as GoldenGate`) resolved type discovery. The live Quickshell log subsequently recorded:

`2026-11-02 17:17:20.517 INFO: Configuration Loaded`

After the final application update, another successful reload was observed at `17:19:36.572`. No load/type errors appeared after that latest success. All 31 deployed configuration/asset files matched their source counterparts at final verification.

The missing material-preview image reported after that reload was then copied into the active assets directory. No desktop process was killed and no full installer/reset was run.

## Required follow-up

1. **Gemma weights:** the user confirmed the file is not available. After the user accepts the publisher's terms and downloads the official file, use the existing verified Import GGUF flow and run real offline inference tests. The old Qwen file remains untouched and is not a fallback.
2. **OCR:** install Tesseract plus English/Indonesian language data before validating actual screen text extraction.
3. **Speech:** provide whisper-cli, a compatible local whisper.cpp model, and espeak-ng; select the model in Luma settings, then validate transcription and playback cleanup on the real audio session.
4. **Devices and network:** activate the Firefox development extension, pair Android through ADB, and test album sharing between two LAN clients outside the socket/USB restrictions of this sandbox.
5. **Remaining functionality:** implement account connectors, model-backed browser classification/name suggestions, general extension generation if still desired, generative photo providers, and the remaining integration/visual acceptance items in the status table.

The entire Golden Gate plan is therefore **in progress**, with deployed foundations and explicit remaining work.
