# Golden Gate 27 — Phase 1 + P1 UI report

Date: 2026-10-31
Scope: GG-01, GG-06, GG-07, GG-17a (+ GG-08 in a follow-up batch)
Status: implemented, deployed to the active shell, verified on the 1280×800 session

## Result

| ID | Feature | State |
| --- | --- | --- |
| GG-01 | Menu bar tray overflow | Done |
| GG-06 | Liquid Glass controls + live preview | Done |
| GG-07 | Reduce Transparency / Increase Contrast / Reduce Motion | Done |
| GG-17a | Extra Large desktop widgets | Done |
| GG-08 | Screen recording + audio options | Done (see `docs/REPORT-GOLDEN-GATE-GG08.md`) |
| GG-09 | Notes application + drawing | Done (see `docs/REPORT-GOLDEN-GATE-GG09.md`) |
| GG-15 | Calendar and Reminders | Done as GNOME Calendar (MacTahoe) + local data bridge: NL parser, Scope reminder scheduler, ICS, quick-add IPC (see `docs/REPORT-GOLDEN-GATE-GG15.md`) |
| GG-04 (A3) | Personal context foundation | Done: `bin/context.py` index (files/Notes/Calendar/Mail contracts) with provenance + enable/disable controls, LumaSettings pane, and Search or Ask now shows local results with provenance (see `docs/REPORT-GOLDEN-GATE-A3.md`) |

The active configuration is a copy of the repository; every file below was copied to
`~/.config/quickshell/...` and the shell was reloaded. The latest reload reports
`Configuration Loaded` with no new QML errors.

## What changed

### GG-01 — Tray overflow

`MacShell/UpstreamBar/MacBar.qml`

- Tray capacity is calculated after the app menus, workspace strip and fixed controls,
  using the real `SystemTray.items` model and the bar scale.
- Items that do not fit are hidden from the bar. A chevron appears only when
  `trayOverflow > 0`.
- `trayMorePop` lists the hidden items with their icons and titles, follows the same
  Liquid Glass material as the other popovers, supports wheel scrolling, keyboard
  navigation (Up/Down/Return/Escape), left-click activation and right/middle-click
  secondary actions.
- Recalculates when tray items are inserted/removed (`onObjectInsertedPost` /
  `onObjectRemovedPost`) and when the bar geometry changes.

### GG-06 — Glass controls and preview

`MacShell/MacDock.qml`, `Common/GlassMaterial.qml` (existing), widgets

- Appearance now exposes **Translucency**, **Backdrop blur (0–80)**, **Liquid
  strength**, corner radius and a live preview. Tinted mode keeps its fixed maximum
  blur, so the blur slider is disabled while Tinted is selected.
- The preview renders the wallpaper crop, applies the current blur, then the tint,
  rim and liquid line, and updates while a slider moves.
- The blur value is shared by the Dock, bar popovers and desktop widgets through
  `GlassMaterial.blurRadius()`.
- Dock/tooltip/widget glass paths use the effective values from
  `Common/DesktopPreferences` so accessibility overrides cannot drift between
  components.

### GG-07 — Accessibility

`Common/DesktopPreferences.qml`, `Common/DesktopPreferences.js`,
`MacShell/MacDock.qml`, `MacShell/UpstreamBar/MacBar.qml`, widget files

Persisted keys in `~/.config/macshell/desktop-dock.json`:

```json
{
  "reduceTransparency": false,
  "increaseContrast": false,
  "reduceMotion": false
}
```

- **Reduce transparency** raises glass fills to a near-solid tint (`0.94`), turns off
  the refraction shader, hides the live backdrop behind widgets and makes the menu
  bar strip opaque. The light-mode `opacity * 0.55` tint is bypassed through
  `glassTint()`, so light mode is also readable.
- **Increase contrast** raises glass rims to at least `0.85` and pushes the wallpaper
  menu border to the light/dark end of its range.
- **Reduce motion** collapses all numeric animation durations in the bar, Dock,
  player widget and widget host to zero; launch bounce and the Dock tear wobble are
  disabled; the dragged-clip wiggle is not started.
- The Appearance pane has an **Accessibility** card with the three switches and a
  light/dark contrast preview. The glass preview switches to a solid
  “Reduced transparency” sample when the first toggle is on.

### GG-17a — Extra Large widgets

`MacShell/MacWidgets.qml`, `WidgetGallery.qml`, `DesktopSurface.qml`,
`WeatherWidget.qml`, `CalendarWidget.qml`, `PlayerWidget.qml`,
`ImageWidget.qml`

- New `xl` size: 560×385, 3×2 grid span, supported by Weather, Calendar, Now
  Playing and Photos; Clock remains Small/Medium/Large.
- Gallery shows four preview cards (Small, Medium, Large, Extra Large) on a
  1280-wide screen. Card width adapts on narrower screens instead of clipping XL.
- The desktop context menu offers **Extra Large** only where supported and only
  when a 3×2 slot is free.
- XL layouts: Weather shows an eight-hour strip and a wider city label; Calendar
  uses the full-width month grid; Player and Photos use the wider footprint.

## Verification

- `qmllint` passes on every edited QML file.
- Shell reload: `Configuration Loaded`; no new QML errors.
- Gallery: all four cards visible and usable at 1280×800
  (`docs/ui-previews/golden-gate-phase1/widget-gallery-xl.webp`).
- Accessibility card: three switches and the contrast preview render correctly;
  toggling `reduceTransparency` through the watched JSON changed the bar to an opaque
  strip, removed the glass preview backdrop and relabelled the sample
  “Reduced transparency”. Toggles were reset afterwards.
- Tray stress test: 36 temporary StatusNotifierItems at 1280×800 produced
  `total 36, capacity 20, overflow 16`; the chevron appeared, and the popup listed
  all 16 hidden items with long titles elided. The temporary items and test hooks
  were removed.
- Reduce Motion: every `duration:` in `MacBar.qml`, `MacDock.qml`,
  `PlayerWidget.qml` and `MacWidgets.qml` is now guarded, and the two infinite
  decorative loops are stopped. Timing was verified by inspection, not with a
  stopwatch.

## Deployment

The following files were deployed to `~/.config/quickshell/...` and match the
repository byte-for-byte:

```
Common/DesktopPreferences.qml
Common/DesktopPreferences.js
MacShell/MacDock.qml
MacShell/MacWidgets.qml
MacShell/WidgetGallery.qml
MacShell/DesktopSurface.qml
MacShell/WeatherWidget.qml
MacShell/CalendarWidget.qml
MacShell/ClockWidget.qml
MacShell/PlayerWidget.qml
MacShell/ImageWidget.qml
MacShell/DockGlassSurface.qml
MacShell/UpstreamBar/MacBar.qml
```

`Common/qmldir` already exported `DesktopPreferences` and needed no change in this
batch. `UpstreamBar/UPSTREAM-RESTORE.json` is machine-specific and was deliberately
not deployed.

## Not done / next batch

- Phase 1 does not install dependencies or download models.
- Phase 2 A1 was completed in a separate batch: the catalog now uses Gemma 3
  1B/4B, imports are verified against pinned SHA-256 values, and provenance is
  recorded in `models/manifest.json`. See
  `docs/REPORT-GOLDEN-GATE-A1.md`. The old Qwen `light.gguf` remains untouched;
  the real inference smoke test still waits for the gated Gemma file to be
  downloaded/imported.
- Phase 2 A3 was completed in a separate batch: the personal-context index
  (`bin/context.py`) plus the LumaSettings pane and local results in Search or
  Ask. See `docs/REPORT-GOLDEN-GATE-A3.md`. Answers that cite sources still
  wait for A2 inference.
- GG-01 click/context-menu activation was exercised through the shared tray action
  code but not with a real pointer injector; keyboard navigation is implemented and
  the popup layout was verified.
- Reduce Motion coverage is complete for the bar, Dock, player and widget host;
  Launchpad/Spotlight-specific decorative animations should be audited when those
  surfaces are touched.

## Commands awaiting explicit approval

Nothing below has been run.

```bash
# OCR (GG-19)
sudo pacman -S --needed tesseract tesseract-data-eng tesseract-data-ind

# Android mirroring (GG-05); android-tools 37.0.0.p1-1 is already installed
sudo pacman -S --needed scrcpy

# Optional system AI runtime if the private llama.cpp runtime is not preferred
sudo pacman -S --needed llama-cpp
```

The Gemma 3 1B IT QAT Q4_0 GGUF still requires accepting the Gemma terms on Hugging
Face and downloading the weights; it is not installed by the commands above.
