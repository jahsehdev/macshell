# MacShell Plan — macOS Golden Gate 27-inspired features

Date: October 30, 2026\
Status: **Implementation in progress. Q1–Q7 are confirmed. Deployed work and remaining model/dependency/device requirements are tracked in [the November 2 execution report](REPORT-GOLDEN-GATE-EXECUTION-2026-11-02.md). The full plan is not yet complete.**\
Project: `/home/icentry/Projects/macshell`\
Active configuration: `/home/icentry/.config/quickshell/MacShell`

## 1. Objective and basis of the plan

Extend MacShell with functional equivalents of the features discussed from the video, using UI, interactions, and animations that fit the existing desktop.

### Confirmed user decisions that define the requirements

1. Develop UI and AI within the same sequence of milestones; both belong in the initial deliverables.
2. Preserve the MacShell/Luma identity and use Golden Gate as the design reference.
3. Run all AI inference offline on the device. No cloud inference or cloud fallback.
4. Keep **MacShell Notes** as an application. On November 2, the user cancelled the dedicated MacShell Calendar, Mail, and Photos applications; their windows and launchers are removed. The menu-bar calendar opens GNOME Calendar, and existing calendar data/reminder services remain available.
5. The dedicated **MacShell Android** application is cancelled at the user's request on November 2; its window and launcher are removed. iPhone remains outside the current implementation scope.
6. Personal context includes files/folders, email, and calendar data. Replace Qwen with a non-Qwen model.
7. Shared Albums only needs to operate on the **local network/LAN**, without public hosting or cloud storage.

These decisions supersede any conflicting recommendations in the previous draft. Do not ask the user to confirm these seven choices again.

**November 2 scope amendment:** The user cancelled the dedicated Calendar, Mail, Photos, Android, and Rename applications. This supersedes their application deliverables, UI tasks, and four-application counts in the original milestones below. Their runtime instances, IPC window entry points, commands, and desktop launchers are removed. Do not recreate those launchers or windows.

Video reference: https://www.youtube.com/watch?v=KXPbf8T5GM0&t=221s

The scope follows the **19 items explained in the conversation**, including their subfeatures. It does not claim to inventory every macOS operating system feature. All items appear in the matrix, including those requiring additional applications or compatibility research.

Limits of the reference evidence:

- The previous explanation relied on the video description/chapter list and supporting documentation; the video has not been watched directly through the available tools.
- Unverified visual details—particularly chapter 3:43, XL widgets, and animations—remain provisional design targets.
- Animation durations, easing, shapes, and effects in this document are **MacShell proposals**, not measurements taken from the video.
- MacShell runs on Linux. Siri, Apple Intelligence, Safari, iPhone Mirroring, and iCloud cannot be installed simply by adding QML configuration. The plan uses Luma and Linux integrations; native Apple services require a proven compatibility path.
- Features without an available backend must be marked unavailable rather than presenting controls that appear functional.

## 2. Initial inspection findings

This inspection only read source/configuration files and checked executable availability; it did not exercise every feature in a graphical session.

| Area | Finding | Implication |
| --- | --- | --- |
| Desktop | Arch Linux + Hyprland, Quickshell/QML; the menu bar, Dock, desktop, Control Center, Launchpad, and settings already exist | Extend the existing components |
| Search and AI | `LumaController.qml`, `LumaSearchView.qml`, `LumaWindow.qml`, and `bin/luma.py` already exist | Reuse the existing assistant |
| Luma capabilities | Local chat, history, streaming, and commands to open applications/settings are documented | Personal context, OCR/vision, calendar, and email need new backends |
| Microphone | `LumaMicrophone.qml` reads audio levels; the documentation states that the visualizer does not transcribe speech | The microphone orb does not yet provide a working voice assistant |
| Material | `MacDock.qml` already has `glassOpacity`, `glassLiquid`, material settings, and preference persistence; `Common/GlassMaterial.*` already exists | Audit consistency, migration, and extensions before adding controls; avoid duplicate sliders |
| Menu bar | The loaded implementation is in `UpstreamBar/MacBar.qml` and uses SystemTray | Base overflow on the actual tray model and available menu space |
| Recorder | Screen/region recording already exists; the inspected command arguments do not add an audio source | Add audio selection to the existing flow |
| Capture stability | `shell.qml` already pauses glass capture while recording/sharing is active | All screenshot/vision features must respect this capture coordination |
| Widgets | `small`, `medium`, and `large` sizes, a grid, scaling, and persistence already exist | Add XL with actual dimensions and layouts |
| Desktop files | `DesktopFiles.qml`, `DesktopController.qml`, and `bin/desktop_files.py` already provide file operations | AI renaming can start on the desktop and later extend through a Nautilus adapter |
| Browser/file manager | `firefox` and `nautilus` were found on PATH | These offer an initial integration path close to the user's current setup |
| Capture/audio tools | `wf-recorder`, `pw-record`, `pactl`, `ffmpeg`, `grim`, and `slurp` were found | The Linux foundation is available; runtime behavior still needs testing |
| OCR/mirroring | `tesseract` and `scrcpy` were not found on PATH | Check/add optional dependencies during the relevant phase |
| AI runtime | `llama-server` was not found on PATH | This does not prove that Luma's private runtime or model is absent; inspect Luma's status during the AI phase |
| Machine at inspection | Intel Core i5-3330, approximately 7.7 GiB total RAM | Load demanding AI, vision, and generative photo editing on demand and measure resource use |
| Resolution | The active configuration contains a VGA-1 1280×800 rule | Test panels/XL on small displays; adapt reference dimensions to the available space |
| Repository versus active configuration | `UpstreamBar/MacBar.qml` and `hypr/hyprland.lua` differ between the repository and active configuration | Reconcile the differences selectively before deployment |
| Work in progress | The repository has tracked changes and new uncommitted Luma files | Preserve these changes; do not reset or overwrite the configuration wholesale |

Important differences: the active MacBar configuration has scalar alias fixes for `dark`, `rim`, and `ringW` in the Luma popup that differ from the repository. The active Hyprland configuration also has local monitor, pointer/cursor, and shortcut settings. Distinguish source fixes from machine-specific preferences when reconciling them.

## 3. Complete feature matrix

P0/P1/P2/P3/P4 indicate the recommended implementation order. P4 means additional research/providers/applications are required; it does not remove the feature from scope.

| ID | Feature discussed | MacShell implementation and behavior | UI/interaction | Acceptance criteria | Priority |
| --- | --- | --- | --- | --- | --- |
| GG-01 | Menu bar overflow | Calculate tray space after the active menu and fixed controls; move items that do not fit into a popup | Chevron button and themed popup; item clicks/context menus remain functional | Test many icons, long menu labels, 1280×800, and monitor changes; hidden icons remain accessible | P1 |
| GG-02 | AI filename suggestions | Luma proposes names from text/metadata or images through a supported provider; rename through the existing file backend | Suggest name action, old/new name preview, Apply/Cancel | Names are valid, extensions are preserved, collisions never overwrite files, and model failure leaves files unchanged | P2 |
| GG-03 | Search or Ask | Unify application/file search and Luma questions; evaluate the existing Spotlight/Luma entry points | Search capsule, local results, streaming answers, Stop button | Consistent shortcuts; input/results survive switching to the Luma application; fallback when AI is not ready | P1–P2 |
| GG-04 | Siri AI/personal context | Extend Luma with a local index of selected folders and MacShell Mail/Calendar data; keep all retrieval and inference local | Answers cite sources; data source settings; action preview | Files, local email, and events can be found; disabled sources are not indexed; no external inference requests | P2–P3 |
| GG-05 | Resizable phone mirroring | Android launcher/integration with scrcpy/ADB; start with USB, then extend to local Wi-Fi connections | Resizable floating window, connect/disconnect, device status | Connect a real Android device and test input, supported audio, resizing, and disconnection; video scaling is not presented as application reflow | P3 |
| GG-06 | Liquid Glass slider | Reuse existing material preferences; align tint/translucency, blur, refraction, and previews across components | Appearance settings with a live preview; light/dark themes | Changes stay synchronized across supported MacShell components, persist after restart, and preserve compatibility with older preferences | P1 |
| GG-07 | Readability when glass effects are unwanted | Add/align Reduce Transparency, borders/contrast, and Reduce Motion; finalize control names after inspecting the reference | Central accessibility panel and contrast preview | Controls remain readable on light/dark wallpapers; reduced motion actually reduces animation | P1 |
| GG-08 | Screen recording + system audio | Extend the recorder with none/system/mic/system+mic options; route available audio sources | Audio options, timer, active indicator, Stop; retain region/screen recording | Output contains the selected audio; stopping finalizes the file; missing sources are handled; no recorder/mixer processes remain | P1 |
| GG-09 | Drawing in Notes | Build the new MacShell Notes application with freehand strokes, shapes, text, undo/redo, save/export | Notes pages and a themed drawing palette | The application opens from the launcher; notes/drawings persist and reopen; export works | P3 |
| GG-10 | Pull to refresh | Add a refresh gesture to MacShell-owned views with data sources; use dedicated browser integration where supported | Drag threshold, indicator, loading/error states | One gesture triggers one request; normal scrolling remains unaffected; do not force the gesture into every GTK/Qt application | P3 |
| GG-11 | Personalized Smart Replies in Mail | Build MacShell Mail with EML/MBOX import, a local cache, compose/drafts, and local smart replies; keep IMAP/SMTP connectors separate | Inbox, message reader, compose view, context selection, reply suggestions, Edit | Imported mail can be read offline and indexed by Luma; drafts persist; email is never sent automatically; test real connectors after selecting an account | P3 |
| GG-12 | Browser tabs grouped by topic | A browser extension sends selected titles/URLs/context for classification; use grouping APIs supported by the target browser | Group preview, rename/move/undo | Existing tabs are preserved; grouping is actually applied or a clearly labeled alternative sidebar is used | P3 |
| GG-13 | Describe an Extension | Initially use structured actions for page customization; research a more general extension builder later | Description → capabilities/permissions → preview → Try/Edit/Save | Results perform real actions on test sites; template limits are explained; model output is not executed as shell commands or unvalidated extensions | P4 |
| GG-14 | Notify Me for website changes | A scheduled service checks the chosen URL/condition, stores the previous value, and sends notifications | URL/condition/schedule form, watch list, pause/delete | Relevant changes produce one notification; schedules survive restart; errors, login requirements, and dynamic pages are handled clearly | P3 |
| GG-15 | Calendar and Reminders with natural language | Build MacShell Calendar with local events/reminders, ICS import/export, and a parser that converts descriptions into event previews | Month/week/agenda views, sentence input, date/time/recurrence preview, reminders | The new application works; events enter Luma's index; test Indonesian/English and Asia/Jakarta time; ask about ambiguous dates; reminders work while the panel is closed | P2–P3 |
| GG-16 | Photos: Clean Up, Extend, Spatial Reframing | Build MacShell Photos for local libraries, albums, editing, and export; test local models for each generative capability before promising results | Photo grid, viewer, editor, mask, before/after, export | The new application and basic editing work; originals remain available; generative features require proven offline providers; crop/perspective is not labeled spatial reframing | P3–P4 |
| GG-17a | XL widgets | Add XL dimensions and adaptive content layouts to supported widgets rather than simply scaling the entire widget | Gallery preview, resize, grid snap, saved positions | Sizes persist after restart; widgets avoid Dock/icon collisions; small displays are handled sensibly | P1 |
| GG-17b | Shared Albums | A MacShell Photos LAN album server with local links, per-album tokens, read/upload permissions, and explicit start/stop | Albums, local link/QR, sharing status, upload permissions, revoke link | Another Android device/browser on the LAN can open an album; invalid tokens are rejected; uploads are bounded; revocation works; no automatic relay/cloud/port forwarding | P3 |
| GG-18 | Assistant application, voice, and history | Extend the existing Luma with speech-to-text and text-to-speech; reuse its history | Responsive orb, listening/transcribing/thinking/speaking states, voice/speed selection, Stop | Speech becomes text, answers can be spoken, Stop ends capture/playback, and history is not duplicated | P2–P3 |
| GG-19 | Visual Intelligence | Select a region/window → screenshot → OCR and/or vision provider → questions/actions | Selection overlay, context thumbnail, Ask/Copy/Create event, remove attachment | Distinguish OCR from vision; capture only on request; respect capture coordination; preview events; avoid shortcut conflicts | P2–P4 |

Feature notes:

- CleanMyMac is a sponsor/third-party application in the video, so it is not a Golden Gate feature to replicate. If the user wants a Linux maintenance dashboard, make a separate scope decision.
- Firefox is the initial browser candidate because its executable is available; the operating system's default-browser preference has not been checked. It will not be presented as native Safari.
- GTK/Qt styling can align themes; adding behavior to other applications still requires their plugins/APIs/source code.
- Offline generative features require research milestones reporting feasibility, RAM/CPU needs, and alternatives before full implementation. iPhone mirroring is outside the current scope.

## 4. UI and animation design

Preserve the MacShell/Luma identity and reuse existing color, font, material, and corner settings. Golden Gate guides consistency and interaction. The user determines the desired level of visual similarity.

Initial proposals to review during prototyping:

| Interaction | Proposed motion | Requirements |
| --- | --- | --- |
| Overflow/small menus | Short fade and scale from the trigger point, approximately 120–180 ms | Accurate hitboxes; restore focus to the trigger on close |
| Search and answer panel | Transition from the capsule into the results area; preserve input continuity | Audit existing Luma motion before layering additional animations |
| Search to microphone | Reuse the existing capsule/orb morph | Backend state must drive the indicator; do not show a false listening state |
| Panels/applications | Fade/scale or resize over approximately 180–260 ms | Proposed initial values; measure on the user's machine |
| Glass slider | Live preview with short interpolation that keeps dragging responsive | Material changes must not continually start new captures/models |
| XL widgets | Resize/reflow and grid snap over approximately 180–240 ms | Content remains visible; restore positions after restart |
| Refresh | Content follows the drag; reveal the indicator after the threshold | One request per gesture; provide a button/shortcut alternative |
| Visual selection | Dim the outside area, draw a selection rectangle, preview the result | Escape cancels and releases all capture resources |
| Photo editing | Before/after and progress for demanding tasks | Progress must reflect real work rather than conceal inference time |
| Reduce Motion | Reduce scale/morph and repeating animations | Keep all functionality available |

Check 1280×800 and HiDPI scaling/multiple monitors where available. Expensive shaders/captures must stop when their view is hidden. Record idle and panel-open CPU/RAM before and after changes; claims of low resource usage require measurements.

### User-specified animation requirements — November 2, 2026

These requirements supersede the provisional animation timings and visual assumptions above:

- **Visual Intelligence:** Command+Shift+6 (Super+Shift+6 on Linux) selects a region/window and shows a moving multicolor perimeter glow before presenting results.
- **Smart menu bar:** animate excess tray icons with collapse/slide transitions behind the notch area or a clipped menu boundary on displays without a notch. Avoid a hard cut on user collapse/expand.
- **Search or Ask:** open almost immediately with a short expansion, without the previous slow bounce. The implemented initial timings are 55 ms opacity and 85 ms scale.
- **Window controls:** add polished hover/press micro-animations to the shared red/yellow/green controls.
- **Liquid Glass and Borders:** update opacity/material continuously while dragging; Show Borders adds a visible outline. Respect Reduce Motion.

See [the execution report](REPORT-GOLDEN-GATE-EXECUTION-2026-11-02.md) for implemented coverage, validation evidence, and remaining work.

## 5. Architecture and data

### Existing integration points

- `config/quickshell/MacShell/UpstreamBar/MacBar.qml`: menu bar, tray, recorder, Spotlight.
- `config/quickshell/MacShell/MacDock.qml`: shared settings and appearance preferences.
- `config/quickshell/MacShell/shell.qml`: component hub and capture coordination.
- `config/quickshell/Common/GlassMaterial.*`, `ThemeColors.*`, `CornerTheme.qml`: materials and themes.
- `LumaController.qml`, `LumaSettings.qml`, `LumaSearch*.qml`, `LumaWindow.qml`, `LumaMicrophone.qml`, `bin/luma.py`: AI and voice.
- `MacWidgets.qml`, `WidgetGallery.qml`, individual widgets: XL sizing and layouts.
- `DesktopFiles.qml`, `bin/desktop_files.py`: filename suggestions and file operations.
- `config/hypr/hyprland.lua`: shortcuts; adapt changes to the active configuration.
- `apps/`, `bin/`, `scripts/`, `tests/`: new applications, adapters, installation, and validation following the repository structure.

### Proposed separation of responsibilities

1. QML manages UI, state, keyboard access, and animation.
2. Python services handle models, indexing, storage, scheduling, OCR, and data adapters.
3. Select **local-only** providers per capability: text, speech-to-text, text-to-speech, OCR, vision, and image generation. A small text model is not assumed to support every capability. No cloud inference provider or cloud fallback.
4. Actions such as renaming files, creating events, or changing tabs use validated structured data and explicit adapters.
5. A browser extension bridges tabs/pages through a defined channel. Confirm technical details during the browser research spike.
6. Services expose capability states: ready, missing dependency, not configured, unsupported, or error. The UI displays the actual state.

Proposed new storage follows XDG; finalize paths after the migration audit:

- Preferences/feature flags: extend existing MacShell settings or use `~/.config/macshell/golden-gate.json` if needed.
- Event, note, watch, and album data: per-module directories under `~/.local/share/macshell/`; use SQLite where querying/scheduling is needed.
- Luma history/models: retain their existing locations.
- Temporary screenshots: runtime/cache storage with lifecycle cleanup; permanent storage only when selected.
- Integration credentials: use the system secret store where available; keep credentials out of the repository and planning file.

### New applications and context integration

Use Qt/QML and shared theme components. Evaluate the installed Quickshell runner for regular application windows; use a Python data bridge without introducing a heavy framework unnecessarily. Each application has its own launcher/desktop entry and remains usable when the Luma panel is closed.

| Application | Initial functionality that must work | Storage and Luma context |
| --- | --- | --- |
| MacShell Notes | Note list/search, text editor, drawing canvas, autosave, undo/redo, export | SQLite + local attachments; note text can enter context from enabled sources |
| MacShell Calendar | Month/agenda views, event CRUD, reminders, natural-language preview, ICS import/export | SQLite; local events/reminders provide personal context; the scheduler runs independently of the window lifecycle |
| MacShell Mail | EML/MBOX import, local inbox, text viewer, compose/drafts, offline smart replies | SQLite + original messages stored locally; index email bodies after enabling the source; HTML does not automatically load remote images/trackers |
| MacShell Photos | Photo folder selection, lazy-loaded thumbnails, viewer, albums, crop/rotate/export, LAN sharing | SQLite metadata + local original files; visual descriptions require an available local vision provider |

Mail supports reading archives/cache and composing while offline. Sending/receiving live email requires a connection to the email server; that connection does not make the AI cloud-based. Ask for account/credential details only when setting up a real account connector. Website monitoring also needs network access to the watched site, while its AI processing remains local. Both features must clearly display offline status.

Personal context uses a local index (SQLite FTS5 where available), document provenance, size limits, and an enable/disable list of sources. Answers reference their original files/messages/events. Do not silently index the entire home directory. Conversation context uses relevant excerpts to limit RAM usage.

### Replacing Qwen and running AI offline

**Default candidate: Google Gemma 3 1B instruction-tuned, GGUF QAT Q4_0**, through a local llama.cpp runtime. This is an initial technical choice to test on the user's machine, not a claim of proven quality or speed.

Publisher references checked during the revision:

- [Official Gemma 3 1B QAT GGUF](https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf): a 1B instruction-tuned model with Q4_0 quantization; accessing weights through Hugging Face requires accepting the Gemma terms.
- [Gemma documentation and model variants](https://ai.google.dev/gemma/docs/core): model-family reference. For the 1B candidate, use the specific GGUF model card above; this variant is used for text, not vision.

Reason for the provisional choice: an official quantized GGUF is available for resource-constrained devices. File size and total RAM use are different measures; Indonesian-language benchmarks, format compliance, response time, and RAM usage on the i5-3330 determine final suitability.

Implementation requirements:

1. Run all chat, summarization, retrieval, naming, and smart replies locally; bind the inference service to loopback only.
2. Do not replace models based on the generic filename `light.gguf`: this local file already exists, and the current catalog associates it with Qwen. Use model-specific IDs and a provenance/checksum manifest so the old Qwen model cannot be mistaken for Gemma.
3. Add local GGUF and runtime import. If weights are missing, ask the user to select an existing file or explicitly follow a one-time download setup. Do not download silently or accept service terms on the user's behalf.
4. Select a non-Qwen default after validating the replacement file and passing a real inference smoke test. Do not delete the old model automatically or use it as a fallback after migration.
5. Separate prompts/templates by model; remove dependence on Qwen-specific flags. Test system-role/chat-template behavior with the chosen Gemma runtime.
6. Bound the initial context and concurrent jobs; load on demand and retain idle unloading. The runtime must support the older CPU's instruction set rather than assume AVX2 availability.
7. Choose local STT/TTS after resource testing; local OCR can provide the initial GG-19 implementation. Vision and generative editing still need separate local models and must never silently switch to cloud APIs.
8. Core acceptance: usable Indonesian answers on realistic task fixtures; test with internet access disconnected/blocked; no external DNS/HTTP requests for inference; clearly report models that are not ready.

### Sharing albums over the LAN

- Run the local host on the MacShell machine. Sharing starts only when enabled by the user and stops when disabled.
- Show the local network address and album link/QR in the UI. The host must stay powered on, and both devices must be reachable over the LAN; guest networks/client isolation can prevent access.
- Serve only files registered in shared albums; do not use the entire home folder as the document root.
- Use revocable random tokens per share, upload size limits, internal filenames, and file type validation. Downloads/previews use album/file IDs rather than accepting arbitrary filesystem paths.
- Do not enable cloud relays, UPnP, router port forwarding, or public internet access. Address firewall settings only if actual LAN testing shows a need.
- Test with at least two LAN clients, including an Android browser when a device is available; localhost testing alone does not prove that LAN sharing works.

## 6. Implementation phases and deliverables

The estimates below are approximate active workdays for scheduling, not completion promises; recalibrate after prototyping. Full implementation estimates are not yet reliable for unproven providers/devices.

| Phase | Work | Initial estimate | Deliverable for review |
| --- | --- | --- | --- |
| 0 — Planning | Read-only audit, matrix, questions, scope decisions | User choices recorded | This revised document; runtime configuration is unchanged |
| 1 — Reconciliation | Snapshot repository/active configuration, map drift, baseline resources, smoke tests | 0.5–1 day | Authoritative file inventory, tested backup and rollback |
| 2 — Initial UI + AI | Two tracks in the same milestone: overflow/material/accessibility/XL and non-Qwen migration/offline/import/basic context | 3–6 days | Interactive UI changes and one local Luma flow using context; validate with a real model once available |
| 3 — Recorder | Audio source selection, mixing where needed, lifecycle cleanup | 1–2 days | Screen/region recordings with verifiable audio sources |
| 4 — AI and application foundations | Build four applications/launchers with real storage; Notes editor, Calendar CRUD, Mail import/drafts, Photos library; file/mail/calendar indexing and renaming | 6–12 days | Four functioning new applications whose data can provide local Luma context |
| 5 — Voice, drawing, and initial vision | Local STT/TTS, Notes drawing, reminder scheduler, refresh, screen OCR | 4–8 days | Working flows, restart/cancel behavior, and an explicit distinction between OCR and vision |
| 6 — Browser and application integration | Firefox API research spike, tab topics, Notify Me, MacShell Mail smart replies; limited extension builder | 4–8 days | Extensions and application integrations work on fixtures/test sites |
| 7a — Android + LAN albums | scrcpy/ADB and local album hosting, permissions, upload, revocation | 2–5 days | Android mirroring and sharing tested on real LAN devices |
| 7b — Offline generative photo editing | Research local Clean Up/Extend/Spatial Reframing models and resource feasibility | 1–2 research days per capability | Evidence of capability/dependencies; estimate full implementation after a successful spike, with no cloud fallback |
| 8 — Final integration | Packaging, preference migration, resource measurements, visual and regression checks | 1–3 days per release group | Installable/reversible changes and a per-feature support report |

Break each phase into small, reviewable changes. Track every feature until it is complete, an alternative is chosen, or the user explicitly changes the scope. A complex phase is not complete merely because a UI demo exists.

### First work package after planning

The initial milestone includes both UI and AI, as confirmed in Q1. The tracks below divide the work; they do not instruct the use of additional agents.

| Task | Track | Depends on | Complete when |
| --- | --- | --- | --- |
| M0 | Foundation | — | Source/active-configuration backups and diffs, plus smoke/resource baselines, are available |
| U1 | UI | M0 | Tray overflow works at 1280×800; clicks/context menus and keyboard access remain usable |
| A1 | AI | M0 | Non-Qwen catalog/IDs, local model import, model manifest, and migration without misidentifying `light.gguf` are available |
| U2 | UI | M0 | Material/accessibility settings persist and apply consistently across the modified components |
| A2 | AI | A1 | A real non-Qwen offline inference smoke test passes, or missing files/runtime requirements are reported specifically; mocks are not presented as proof of inference success |
| A3 | AI/data | A1 | A local fixture-folder index and Notes/Mail/Calendar source contracts exist, with provenance and source enable/disable controls |
| U3 | UI | U2 | Adaptive XL widgets and layout persistence work on a small display |
| I1 | Integration | U1–U3, A2–A3 | Search or Ask shows local results and Luma responses; source/cancel/error/offline behavior is tested; UI evidence and capability reports are recorded |

The four applications become working deliverables in phase 4. Prepare shared data contracts and design in the first milestone to avoid reworking personal-context integration later.

## 7. Change and validation strategy

Before implementation:

1. Compare the repository and active configuration; save snapshots/diffs, including new untracked files.
2. Preserve Luma popup fixes and local Hyprland settings; do not use the installer to overwrite the entire configuration.
3. Identify source files to edit, active files to deploy, and rollback steps for each phase.
4. Record baselines for shell reloads, keyboard/input, idle resources, recording, and key popups.

During implementation:

- Check QML with the correct Quickshell imports/paths; distinguish lint noise from runtime errors.
- Run existing tests relevant to changed components. Add behavior tests only for important logic such as rename collisions, scheduling, audio routing, action validation, and cleanup.
- Test light/dark, glass/contrast modes, keyboard/Escape, small displays, restart, cancellation, missing backends, and offline conditions as applicable.
- Test the recorder with real output files: resolution/duration, audio streams, stopping, and remaining processes; use `ffprobe` where available.
- Test AI adapter logic with fixtures and mock providers, then verify one real-provider flow end to end. Mocks do not demonstrate model capability.
- Use sample documents, photos, and email rather than user data as fixtures unless necessary.
- Capture short visual evidence/screenshots at UI milestones. Assess video similarity only against reference scenes that can actually be viewed.
- Test installation in staging before applying active files. Do not restart the desktop during planning.

## 8. Confirmed user answers

All primary questions have been answered. This section records the actual decisions and supersedes draft recommendations.

| Code | Topic | Decision applied |
| --- | --- | --- |
| Q1 | Priority | Develop both UI and AI in the initial milestone |
| Q2 | Identity | Preserve MacShell/Luma with Golden Gate styling |
| Q3 | Inference | Fully offline; no cloud fallback |
| Q4 | Applications | Four new MacShell applications: Notes, Calendar, Mail, Photos |
| Q5 | Phone | Android first; iPhone is outside the current implementation scope |
| Q6 | Personal context and model | Files/folders plus email/calendar; replace the model with a non-Qwen model |
| Q7 | Albums | LAN sharing only |

Initial browser recommendation: keep Firefox. If the user wants a new Safari-like browser, treat it as an additional application with its own scope; a theme change alone does not provide Safari features.

## 9. Decision log

| Decision | Status |
| --- | --- |
| Create only the plan at this stage | Confirmed by the user's request |
| Create a Markdown file in the MacShell repository | This document has been created |
| Change or reload the active configuration | Authorized by the implementation request; selected files deployed and a successful live reload observed on November 2 |
| Q1–Q7 | All answered and incorporated into this plan |
| Replacement model candidate | Gemma 3 1B IT QAT Q4_0; initial technical choice, pending offline benchmarks before activation |
| Active model during the additional inspection | A local `light.gguf` of approximately 0.6 GiB and model ID `light` were found; weights have not been migrated during planning |
| Unseen animation and visual details | Awaiting inspectable visual references during the design phase |
| Dependency installation, model downloads, external accounts/services | Not performed; determine requirements from the features and user choices |

This revision records the actual decisions and the first work package. Planning is complete and implementation is now in progress; see the execution report for current status. Do not ask Q1–Q7 again. Collect email account and Android pairing details when device/account integration requires them, while continuing independent work.
