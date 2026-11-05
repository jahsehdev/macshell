# Dynamic Notch

Dynamic Notch is enabled by default in attached mode, with fullscreen visibility
off. Change its settings under **Settings → Dynamic Notch**:

- Attached joins the top screen edge with curved shoulders and rounded bottom corners.
- Floating uses a detached capsule when compact, with fully rounded ends at
  every size and a 7-pixel top gap. Its corners blend into the expanded panel.
- Position uses two clickable desktop previews, with the selected shape outlined
  in the accent color. Clicking either preview applies and saves that position.
- Material offers **Solid Black** (default) and **Semi Liquid Glass**. Glass uses
  a dark top and a translucent lower portion when expanded. Blur follows the
  effective System Settings value directly, without an additional minimum.
  The body and bevel sample the same backdrop at that selected blur level.
  The compact notch stays black. This preference is independent of position.
  **Appearance → Liquid Glass** changes its blur and material density live, using
  the same continuous material as the Settings preview and Dock. Translucency,
  liquid strength and grain tuning are shared too; the dark camera seam
  and contrast floor remain specific to the notch. A curved bevel refracts the
  backdrop across a wider edge band, with subtle interior magnification,
  chromatic separation. Depth comes from refraction, without an inset dark band.
  The notch disables the outer
  specular rim so its silhouette has no white border.
  The lens stays inside the animated silhouette.
  Reduce Transparency disables
  the glass renderer and uses the solid fallback.
- Fullscreen supports Hide or Keep visible, independently of the selected shape.
- Size ranges from 85% to 120%. Display selection supports all displays or the first display.
- **Idle eyes** shows an animated pair of eyes when no activity is running.
- Volume feedback always uses the existing separate top-right OSD; it never
  replaces an active notch page. Disabling the notch also restores separate
  brightness feedback.

Hover for 260 ms to open a preview. Click to expand immediately; leaving for
650 ms closes it. The close button dismisses it immediately.
Controls use existing MacShell services:

- Music: title, artist, artwork, playback progress, seek, previous, play/pause and next.
- Timer: remaining time, pause/resume, cancel and Clock access; ringing gets priority.
- Recording: elapsed duration and the existing safe stop action.
- Charging: connection feedback and battery percentage.
- Brightness: hardware-key feedback with adjustable level. The Volume notch
  page has been removed; volume keys keep the separate existing OSD.

Hardware feedback briefly takes precedence, then restores the chosen activity.
Feedback controls stay mounted while the expanded panel is being used. Without
an explicit choice, recording takes priority over an active timer, then media. Activity tabs let the user switch between simultaneous tasks.
No notification contents are copied into the notch.

## Pages and local tools

The expanded notch has eight configurable pages: Music, Pomodoro, Water
Reminder, Shelf, Todo List, Calendar, Weather and System Stats. Choose a page using the
bottom indicators (a white pill marks the current page), the side arrows, or a
horizontal trackpad scroll over the notch background. Media uses a vertical
icon rail on the right with Music, Pomodoro and System Stats when enabled, plus
**•••** for the remaining pages. The More pages popover uses labeled rows;
disabled pages are omitted and temporary pages remain accessible. Pomodoro, Calendar, Weather and System Stats hide side arrows
and retain the bottom indicators. The selected page survives
collapsing, changing shape and restarting the shell. A running Clock timer or
screen recording adds its existing controls to the page list. Hardware feedback
and ringing Clock alarms temporarily take priority.

**Settings → Dynamic Notch → Pages** controls which pages appear. At least one
page remains enabled. Page selection is shared across displays. The compact
notch continues showing live activity or idle eyes independently of that choice.

- Pomodoro uses a warm, neutral dial with minute marks and a progress cursor,
  a preset list, daily session count and a toolbar. The default 560 × 256 panel
  places presets on the left and the timer on the right. Expanding Focus Target
  produces an 800 × 256 three-column panel; narrower screens show targets as a
  dedicated panel instead of shrinking three columns into unreadable text.
  Presets are Work (25 minutes), Short Break (5), Long Break (15), Quick Timer
  (5) and Custom (30), all editable in the spring/frosted settings popover.
  The center dial starts/pauses, and adjacent controls reset or skip the phase.
  Skip does not count a completed focus session. Work and Custom completions
  count toward the daily total and the four-session long-break cycle; Quick
  Timer is independent and repeats when restarted after completion. Completed
  phases notify once and wait for Start. Wall-clock deadlines survive reloads.
  Compact controls use a briefcase/preset progress badge, bold 15-pixel time,
  reset, pause/resume, skip and ×. The × hides these controls without stopping
  the timer; selecting Pomodoro again reveals them.
- Water Reminder records each Drink action, daily totals and real hourly history
  for the local day. Defaults are a 1,500 ml goal, 250 ml per drink and a 60-minute
  reminder interval. All are configurable. Undo removes the most recent drink
  for today. Reminders can be disabled and stop once today's goal is reached;
  disabling the page or notch also suppresses these reminders. History keeps
  the most recent 30 days.
- Shelf accepts local files and folders dragged onto the notch, including its
  compact state, and offers native file/folder pickers. It stores up to 100
  references with file metadata and image thumbnails. Clicking opens the original
  with the system handler. Removing an item or Clear only removes references;
  it never moves, copies or deletes the originals. Missing files and rejected
  nonlocal URLs produce an inline message. `bin/notch_shelf.py` validates local
  URLs and passes paths as separate arguments to the opener.
- Todo List supports adding, editing, completing, reopening and deleting tasks.
  Its daily count includes tasks completed on the current local day, alongside
  outstanding tasks. Task text and completion timestamps persist across restarts.
  The pencil button shows per-task edit and delete controls.
Bluetooth and Charging are automatic status cards, not selectable pages or
page settings. Bluetooth connections use a 520 × 136 detail card with an original
local device illustration, Connected/device-name hierarchy, and a 64 px battery
ring. A subtle dark layer keeps glass cards readable over bright windows.
After 4.5 seconds it becomes a 324 px compact glance with artwork on the
left and a battery ring on the right, then expires after 5 more seconds. Hovering
or clicking the glance reopens the detail card. Clicking an open card dismisses
it. The previous page and timer state are retained. Charging retains its 440 × 104
card and 4.5 second lifetime.

AirPods/earbuds, headphones, keyboards, mice, controllers, speakers and phones
have matching local vector artwork, with a Bluetooth fallback for other devices.
The existing BlueZ snapshot now carries its optional device icon so names such
as G915 can still be classified. No pairing, connection, adapter scan or system
setting is changed by the notifier. Percentages use the existing BlueZ battery
reading; unavailable data renders an em dash instead of an invented percentage.
See the [BlueZ battery API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Battery.rst).
The current integration uses the device-level percentage; it does not invent
separate left/right/case readings for devices that do not expose them.

Battery-low alerts fire once at 20% and again at 10%. Warning/critical states
rearm only after recovery to 25%/15%; ordinary polling and small fluctuations do
not repeat cards. A connection with an already-low battery generates a single
connection card with the appropriate amber/red battery ring. Late-arriving battery
reports can trigger a low alert. The first scan establishes a quiet baseline;
known connected devices do not generate false connection or low-battery events
when the shell reloads. Up to eight pending connection/low events are queued;
disconnected devices are removed immediately. Alarms, screen recording and
hardware OSDs retain priority. Bluetooth and charging never enter page rotation.
Old saved page lists still migrate to the six supported pages without removing
user records. Notification history is transient and is not written to local data.

Fixture renders cover [connected](ui-previews/notch-device-events/airpods.png),
[compact](ui-previews/notch-device-events/compact-airpods.png),
[low battery](ui-previews/notch-device-events/low.png),
[controller](ui-previews/notch-device-events/gamepad.png) and
[narrow displays](ui-previews/notch-device-events/narrow.png).

`NotchTools.qml` is instantiated once in MacBar, independently of per-screen
notch views. It owns deadlines, reminders, data and native pickers. Editing a
form or using a picker prevents hover-close until that interaction ends.
`NotchToolsState.js` handles restoration, validation and local-day calculations.
Data lives in `$XDG_CONFIG_HOME/macshell/notch-tools.json` (normally
`~/.config/macshell/notch-tools.json`) and uses atomic writes. Unreadable saved
JSON is backed up before new data is written; read/backup failures suspend
saving and surface an error. Notification delivery uses the existing
`notify-send` desktop integration.

Page UI lives in `NotchPages.qml` and separate Pomodoro, Water, Shelf, Todo and
Device components. `NotchNavigation.qml` supplies the indicators and navigation.
The new pages use the shared shape/material and fit narrower screens by scaling
their geometry and contents together. Shelf adds a subtle lower blue wash in
solid mode. Reduced Motion bypasses page fades and indicator transitions.

Focus Target reads actual local Todo tasks. Select associates the session with
a task; Clear removes that association. Targets survive phase changes, resetting
and restarting the shell. Deleting a Todo clears its active target while keeping
historical session records. Finishing a focus session does not mark its task done.
Calendar events are not supplied until a calendar source is connected.
The daily count records new Work/Custom completions at their actual deadline,
including when the shell resumes after midnight; migration preserves the old
cumulative count without inventing historical completion dates. Session history
is bounded to 90 days / 2,000 entries.

The stopwatch button opens Timer settings. More options exposes long breaks,
Quick Timer, Custom, Focus Target and Focus activities. Focus activities opens
Focus Decision; context buttons choose pages that participate in rotation.
The rotation slider sets 3–30 seconds (default 5); automatic rotation is off
by default. Accept Focus applies the draft; Dismiss leaves the previous choice
intact. Manage live activities controls which of the six pages are enabled,
with at least one required. The shared rotation timer runs only while a notch
is expanded and pauses during forms, popovers, Focus Decision, transitions and
hardware feedback. Closing every notch stops rotation. Presets, target, session
history and focus configuration persist in version 3 of the local data.

The Pomodoro UI lives in `NotchPomodoro.qml`, `NotchPomodoroRuler.qml` and
`NotchPomodoroCompact.qml`. `NotchFocusTargets.qml` and `NotchFocusDecision.qml`
remain available through settings. See the current [setup](ui-previews/pomodoro-simple/setup.png),
[running](ui-previews/pomodoro-simple/running.png),
[paused](ui-previews/pomodoro-simple/paused.png) and
[narrow setup](ui-previews/pomodoro-simple/narrow-setup.png) fixture renders.

All notch dropdowns use `NotchSettingsPopup.qml`, a
window-overlay portal, positioned 4 pixels below its Settings button with a
rounded top tail. It can overlap the notch and extend beyond its clipping bounds.
The anchor tracks the button and its ancestor layouts after page creation.
The page stays visible while editing. The surface reuses the File/Edit dropdown
glass renderer, its 42-pixel clear backdrop blur and shared material settings. It follows
the menu bar's light/dark appearance. It reuses the shared backdrop and releases
capture demand after closing. Software rendering and Reduced Transparency use
an opaque fallback. `NotchSettingsField.qml` supplies labeled numeric inputs.
Save validates and applies the draft; Cancel, Escape and clicking outside discard
it. The notch stays open while settings are in use. Short screens scroll the form.
The menu-bar and fullscreen input masks include the dropdown while it is open,
and keyboard focus is requested only for that interaction.

Opening a settings dropdown uses a damped [Qt SpringAnimation](https://doc.qt.io/qt-6/qml-qtquick-springanimation.html),
with independent horizontal/vertical squash and stretch anchored to the tail.
The panel slightly overshoots its final size before settling. Drag the title or
subtitle to move it within the screen bounds; inputs and buttons retain their
normal interaction. Motion drives two additional spring responses, bending the
outline and stretching the panel while it is dragged, then relaxing after
release. The shared glass surface follows the elastic transform; the opaque
fallback retains the custom outline. The pointer retracts when detached from its
button. The dropped position lasts until closing; reopening restores the
button anchor. Reduced Motion immediately restores normal geometry, while
allowing the panel to be dragged. No new persistence or dependencies are needed.
See the [opening](ui-previews/dynamic-notch-popover-spring/opening.png),
[overshoot](ui-previews/dynamic-notch-popover-spring/overshoot.png),
[drag deformation](ui-previews/dynamic-notch-popover-spring/drag-dragged.png) and
[settled drag](ui-previews/dynamic-notch-popover-spring/drag-settled.png) fixture
renders. The original sources are backed up under
`~/dock-config-backup/notch-popover-spring-20261103-123921/`.

Notch controls and Shelf file labels use `NotchToolTip.qml`, reusing the Dock's
`DockTooltip.qml` capsule, continuous rounded tail and Liquid Glass shader.
The popup appears after 700 ms and points its tail at its control. It prefers
the space above the button, automatically opening below with an upward tail
when there is insufficient room at the screen's top edge. The capsule outline,
text position and Liquid Glass silhouette share the same orientation, while
the backdrop remains aligned with the screen. It renders in the window overlay
outside the notch's content clip and follows ancestor layout changes.
Hover is observed from the control's container so labels also appear for
disabled playback controls, including when no media player is available.
It follows the Dock's light/dark and shared glass settings. The existing
backdrop is requested only while needed, including when the notch itself is
solid black. Closing the tooltip releases that demand. Software rendering and
Reduced Transparency use the shared normal-material fallback; Reduced Motion
disables its small fade and scale transitions.

## Idle companion

When music is paused and no other activity is active, the compact notch shows
two white eyes over a soft orange-to-yellow lower glow. They blink at varied intervals and
gently glance left, right and toward the center. After 45 seconds, the eyes
become half-lidded; after two minutes they become sleepy, with longer blinks.
Opening the notch or returning from an activity resets the expression.

Paused music controls remain available by expanding the notch. Pausing using
the compact media controls keeps that card visible for resuming. Recording,
timers and temporary hardware feedback retain their existing activity priority.
Disable the eyes under **Settings → Dynamic Notch → Idle eyes**. The preference
is saved as `notchIdleEyes`. Reduced Motion keeps the expressions static, and
the animation timers stop when the eyes are hidden. The implementation lives
in `NotchIdle.qml`.

## Screen recording

Recording is an automatic live activity, not a permanent page in the menu list.
It takes over the notch while MacShell's existing recorder is running; urgent
clock alarms, hardware feedback and OSD keep their existing priority. Existing
monitor/area selection, audio modes, recorder cleanup and output directory are
preserved. This does not monitor unrelated OBS/browser recording sessions.

- The 324-pixel compact state shows a red recording dot and elapsed time.
- Opening it shows a 520 × 120 panel with the elapsed time, Screen Recording
  label and a white circular Stop control with a red square. Stop uses the
  existing recorder's SIGINT/finalization path. During finalization it becomes
  disabled and the card says Saving; it never tries to open an unfinished file.
- After the recorder exits, `NotchRecording.qml` invokes
  `bin/notch_recording.py`. The helper verifies a nonempty local video with
  ffprobe, reads its duration and optionally generates a thumbnail with ffmpeg.
  A single shared result is then shown in a 580 × 184 card until dismissed.
  Actions sit closer to the file details with 18 pixels of bottom breathing room;
  status/error text uses the gap above the action row.
  Thumbnail cache is bounded to 24 entries. Missing or invalid video produces
  a dismissible error instead of a false success card. New recordings clear
  earlier results; generation tokens ignore stale completion/action responses.
- The result card displays thumbnail, duration, actual filename and directory.
  Watch opens the video in its associated player. Show in Files uses
  FileManager1.ShowItems to reveal it, falling back to opening its directory.
  Copy publishes a file URI on the clipboard using wl-copy (text/uri-list).
  Trash uses `gio trash` and clears the card only after success; failure stays
  visible for retry. The × button only dismisses the card, preserving the file.
  No action runs without an explicit button click, and filenames are passed as
  separate process arguments rather than shell text.

Layouts scale to narrow screens, reuse the notch shape/motion and tooltips,
and preserve the recorder's capture-quiet behavior. Completion data is transient
and never restarts recording after a shell reload. The UI is implemented in
`DynamicNotchRecording.qml`; MacBar calls the shared service after process exit.

Fixture previews use mock metadata and sample artwork:
[compact](ui-previews/notch-recording/compact.png),
[recording](ui-previews/notch-recording/live.png),
[saving](ui-previews/notch-recording/saving.png),
[result](ui-previews/notch-recording/result.png),
[error](ui-previews/notch-recording/error.png),
[narrow](ui-previews/notch-recording/narrow-result.png),
[floating](ui-previews/notch-recording/floating-result.png).
These were checked with Qt's software renderer. Helper tests create a synthetic
video and verify real metadata/thumbnail generation without capturing a desktop.

## Music layout

Media has only two sizes: a **medium** expanded player (640 × 160) and a
**small** 324-pixel collapsed player. Opening
lyrics adds 40 pixels of vertical room, producing a 740 × 200 medium lyrics
view. Narrow stacked layouts reserve 80 extra logical pixels for playback below
the lyrics. The large layout, resize button and layout setting have been removed.
The lower wash stays neutral gray. A dedicated gutter separates the timeline
and content from the navigation rail. Its three primary tabs and More button sit in a dark rounded pill, using 20 px
icons and 28 px tall hit areas, with a rounded active highlight. The pill is centered vertically,
with 20 px above/below in the standard media layout and a corner-derived
18 px gap from the body edge. Its rounded ends use 4 px padding; attached-mode
wings are included in the right inset. Extra pages use the More popover. The main player uses a 20-pixel title,
14-pixel artist line, 12-pixel times and an 80-pixel cover. The wide lyrics layout
uses a 22-pixel title, 15-pixel artist line, 13-pixel times and a 96-pixel cover.
The progress track is four pixels thick. Playback sits lower in the lyrics
layout to fill the left column, with the lyrics icon aligned below the cover.
Rounded artwork, solid playback controls and heavier rounded vector strokes
follow the reference layout. The Media heading, app badge and home button
have been removed. Artwork and track details now start 24 pixels from the top,
with a single lyrics toggle centered below the cover and vertically aligned
with the playback controls. Playback stays centered in the
main player and aligned to the left column when lyrics are open. The visualizer
toggle, Jump in launcher, mute and media settings have been removed from this toolbar. Small displays use a 440-pixel layout before scaling; lyrics
take over the body while playback remains available below. The visualizer fits
behind the controls in the medium player and retains its existing lifecycle.

- Scrolling the medium or collapsed media card never changes system volume.
  Plain lyrics remain scrollable; volume changes use the output popover,
  system volume controls or hardware keys. The Volume notch activity is removed. Unhandled media wheel events stay inside the
  overlay, and existing horizontal page navigation remains available.
- Playback includes seek-on-release, elapsed/duration labels, shuffle and repeat
  (off → playlist → track → off). Unsupported shuffle, repeat or seek stays
  disabled. Their labels remain available when no player is present.
- The 324-pixel compact view shows artwork, an elided song title, a playback
  five-bar live waveform and previous/play-pause/next controls. The waveform
  groups the shared 24 FFT bands into five levels and interpolates their height
  over 100 ms. Silence stays low; pause/Reduced Motion uses a static waveform.
  Compact playback requests the existing output monitor even if the expanded
  visualizer is disabled; no new recorder or synthetic waveform timer is added. Pausing from these controls
  keeps the card available for resuming, without expanding it. Disconnecting the
  player releases it so idle eyes can return.
- Lyrics display at most three entries: previous, active and next, with long
  lyrics allowed to wrap. The main text is 20 pixels (18 on narrow screens),
  with six-pixel row spacing and shorter feathering at the viewport edges.
  Extra entries remain in the timed model for scrolling but are not painted;
  untimed lyrics scroll through consecutive windows of three. The active row sits about one quarter down the
  viewport; header/footer spacing keeps the first and last lyrics reachable.
  Artwork and playback sit near the top rather than vertically centering against
  the lyrics pane. The column gap and top padding are reduced.
  Text focus follows `PlayerWidget.qml`: bold and sharp active lyrics, 86%
  scale and distance-based dimming/blur on surrounding rows, 480 ms cubic
  transitions and a feathered top/bottom mask. The notch uses its enlarged
  lyric font and compact viewport. The viewport glides explicitly over 650 ms
  with cubic easing; departing/arriving rows crossfade over 480 ms, preserving
  the three-entry window after each transition. Opening adds the widget-style
  opacity, scale and focus transition. Rapid/backward seeks retarget the current
  motion, while resizing/model resets realign to playback.
  Reduced Motion disables animations; software
  rendering uses the unblurred opacity/scale fallback.
  Lyrics highlight and follow the actual playback position. Clicking a timed
  line seeks there. Untimed lyrics remain scrollable with no invented timing;
  loading and unavailable states have explicit messages. The lyrics selection
  survives collapsing and temporary hardware feedback. Opening and closing
  lyrics uses the shared smooth content transition.
- Player choice is shared with the menu bar and desktop widget lyrics. The
  notch no longer exposes a player picker; disconnecting a selected player falls
  back to a playing/available player.
- The output popover contains system volume and the actual PipeWire devices;
  choosing one invokes the existing default-output action. It does not pretend
  to provide native AirPlay discovery. The output menu uses the shared frosted,
  spring-animated, draggable portal.

`NotchMedia.qml` is instantiated once in MacBar. It owns player choice, the
visualizer preference and a single spectrum process across displays. The
visualizer preference uses atomic writes to `macshell/notch-media.json` (version
2). Older density fields are ignored and cannot restore the removed large layout.
Transient player IDs are not persisted. Existing notch-tool data and player
settings are untouched.

`bin/notch_spectrum.py` reads the **output monitor**, using `parec`, and emits
24 logarithmic FFT bands. Audio stays in memory; it is never recorded to disk,
and the microphone is not used. Capture runs only while a playing app and a
visible expanded visualizer or compact waveform need it. Closing the notch, opening another panel,
changing page, disabling the visualizer or Reduced Motion releases demand.
Changing output restarts the monitor on that device; capture failure leaves
flat bars and an internal service error status. The helper needs Python and PulseAudio
client tools (`parec`/`pactl`, also usable with pipewire-pulse).

Shared components are `NotchMediaButton.qml`, `NotchMediaArt.qml`,
`NotchMediaMenuItem.qml` and `NotchMediaOption.qml`. Software rendering uses a
rounded Canvas artwork fallback; GPU rendering uses a rounded alpha mask.
Tooltip positions still flip below top-edge controls, with an upward tail.
They share the root hover observer, so disabled buttons keep their labels.
Notch tooltip glass composites the shared desktop backdrop with a live capture
of the notch surface before blur/refraction. Opaque notch pixels therefore hide
the desktop in the reflection, while transparent areas retain the backdrop.
The popup stays in the window overlay outside the captured notch to prevent
feedback. Only the tooltip region plus optical padding is sampled; coordinate
mapping follows its opening scale, and captures unload when glass is inactive.
Notch labels opt into a contrast veil above the optics, with 14-pixel semibold
text and a subtle text shadow. Dark labels use white text over a 60% dark veil;
light labels use dark text over a 78% white veil. This bounds text contrast even
over bright cover art while preserving the shared liquid silhouette and tail.
A minimum blur of 12 and reduced refraction/rim/grain soften busy reflections.
Dock labels retain their existing material and typography defaults.
[Readability preview](ui-previews/media-redesign/tooltip-readable.png) uses the
software material fallback over light/dark patterned backgrounds.

Fixture previews: [player](ui-previews/media-redesign/player.png),
[lyrics](ui-previews/media-redesign/lyrics.png),
[compact controls](ui-previews/media-redesign/collapsed.png).
They use mock metadata, original sample artwork and fixed spectrum values for
repeatable visual checks; production bands come only from output audio.

Media validation adds shuffle/repeat capability checks, compact playback,
player switching/disconnection, output selection, capture demand lifecycle,
lyrics-only toolbar, preference restoration and narrow-layout interaction. The suite now has 15 Node,
14 Python and 63 QML checks. Recording helper checks cover valid/invalid video,
quoted filenames, local-file validation, clipboard MIME data and recoverable
Trash dispatch. Four existing recorder tests also pass, covering monitor/area
selection, start/stop guards, crop overlay and audio command construction. Spectrum tests verify silence, frequency peaks,
amplitude response and partial PCM framing.


## Validation

Run:

```sh
bash config/quickshell/MacShell/tests/run-dynamic-notch-tests.sh
```

On 2026-11-03, all 12 Node tests, 3 Shelf Python tests and the QML suite
(42 passes, 0 failures,
including its lifecycle case) passed. These cover fullscreen/workspace filtering,
simultaneous activities, hardware-feedback expiry during adjustment, hover/click
and close timing, media actions, timer actions, stopping recording, both shapes,
size changes, availability, animated geometry, seek-on-release, music-page
navigation without opening the source player, independent lyrics consumers, synced line tracking and seeking,
and plain/loading/missing lyrics states. Motion checks also cover staged content
reveal, reversing rapid open/close gestures, final settled geometry and Reduced
Motion. Page transition checks cover retaining the outgoing page through its
fade, coordinated entry/size changes, rapid navigation, reversing direction,
repeated next-page actions, close interruption and enabling Reduced Motion
mid-transition. Additional checks cover idle expressions, paused/playing transitions,
the idle preference, and a glass shader whose readiness status remains pending.
Page checks cover navigation and restoring the selected page, disabled pages,
hardware/alarm priority, Pomodoro phase completion and long-break cycles,
water/task actions, Shelf metadata and rejected URLs, and saving/reloading the
new local data. Pomodoro checks include all preset modes, independent quick
timers, real target selection, compact pause/skip/hide actions, save/reload of
new settings and targets, daily completion attribution, actual timed rotation,
Focus Decision apply/cancel and management of enabled pages. Python checks cover encoded filenames, duplicate references,
remote/missing/special-file rejection, argument-based opening and preserving
original file contents.
Settings checks also cover rejecting invalid durations, saving valid values,
and discarding canceled Pomodoro/water reminder drafts. Dropdown checks also
cover the overlay placement, small-screen scrolling, hover-close suppression,
Escape/outside-click dismissal and cleanup on notch close. Portal checks verify
the tail and vertical gap against the actual Settings button after layout,
including changing from Pomodoro to Water Reminder. Motion checks verify a
measured spring overshoot and settlement, interruption by Reduced Motion,
header dragging, release settlement, saving after dragging and restoration of
the button anchor on reopening.
[Pomodoro](ui-previews/dynamic-notch-settings-anchor/pomodoro.png),
[Water Reminder](ui-previews/dynamic-notch-settings-anchor/water.png),
[light mode](ui-previews/dynamic-notch-settings/light.png) and
[narrow screen](ui-previews/dynamic-notch-settings/narrow.png) were rendered with
mock data and the software material fallback. The active host's OpenGL render
also confirmed the frosted backdrop and rounded tail. The settings update was
backed up under `~/dock-config-backup/notch-settings-popover-20261102-231056/`.
Device event checks cover new Bluetooth connections, startup baseline scans,
reconnection, battery-only updates, disconnection, charger insertion/removal,
actual card expiry and returning to the previous page. Saved seven-page lists
are checked for migration while retaining local data.
The [Bluetooth](ui-previews/dynamic-notch-device-events/bluetooth.png) and
[Charging](ui-previews/dynamic-notch-device-events/charging.png) cards were
visually checked with mock device data. The installed sources were backed up
under `~/dock-config-backup/notch-device-events-20261102-224757/`.
The tooltip case verifies hover display, the shared label's tail, positioning
outside the content clip, Reduced Transparency and releasing demand on close.
A regression case hovers Play, Previous and Next with no player and verifies
that all three tooltips appear while the playback actions remain disabled.
Qt 6 lint reports no error-level
diagnostics for the notch, menu bar and Settings sources; the existing sources
still have lint warnings. `git diff --check` passed. Use
`/usr/lib/qt6/bin/qmllint`; the system `/usr/bin/qmllint` is an older Qt 5 tool.

The current [music preview](ui-previews/dynamic-notch-music/music-preview.png)
shows the redesigned compact and expanded states. Four music renders were
checked, including attached, floating and reduced size. The mock artwork and
metadata are preview fixtures. Earlier renders of the initial implementation
are retained below for the other activity types.

The [lyrics preview](ui-previews/dynamic-notch-music/lyrics-expanded.png) shows
the two-column layout with mock timed lyrics. Attached, floating, loading and
missing-lyrics renders were also checked. After installation, the host shell
auto-reloaded successfully at 2026-11-02 20:05:00.821 with no related runtime
diagnostics. The lyrics update's source and installed-file backups are under
`~/dock-config-backup/dynamic-notch-lyrics-20261102-200213/`.

Seventeen offscreen transition frames were rendered and checked for the motion
update. The host shell then auto-reloaded successfully at
2026-11-02 20:26:44.698 with no related runtime diagnostics. Live compositor
frame pacing remains unmeasured from this sandbox.

Material checks cover switching style, compact/expanded demand, Reduced
Transparency, software fallback and resource release on close. The new shader
compiled successfully with Qt 6 qsb. A live host render subsequently exposed
a status-gating bug: the packaged shader was rendering while its status still
reported Uncompiled, so the opaque fallback covered the glass. The fallback now
responds to actual shader failure instead. A captured host render confirmed
that the blurred backdrop is visible; software rendering still uses the solid
fallback. Original files are
backed up under `~/dock-config-backup/dynamic-notch-material-20261102-203037/`.
The glass correction is backed up under
`~/dock-config-backup/dynamic-notch-glass-fix-20261102-204319/`.

Seven idle renders were checked, covering normal eyes, both gaze directions,
blinking, bored and sleepy expressions, and floating mode. See the
[normal](ui-previews/dynamic-notch-idle/curious.png),
[bored](ui-previews/dynamic-notch-idle/bored.png) and
[sleepy](ui-previews/dynamic-notch-idle/sleepy.png) previews. These are offscreen
fixtures. The idle update is backed up under
`~/dock-config-backup/dynamic-notch-idle-20261102-205025/`.
The installed host auto-reloaded successfully at 2026-11-02 20:53:37.255,
with no related runtime errors in that reload.

The position picker uses `NotchPositionPicker.qml` and the shared notch path.
Its [attached](ui-previews/dynamic-notch-position/attached.png),
[floating](ui-previews/dynamic-notch-position/floating.png), and
[narrow dark](ui-previews/dynamic-notch-position/dark-narrow.png) renders were
visually checked. An offscreen click check selected both positions and verified
the selection markers (2 Qt Test passes, including lifecycle; 0 failures).
The Settings source was backed up under
`~/dock-config-backup/notch-position-preview-20261102-210319/`.

The tools update was checked with thirteen offscreen renders, including
[Pomodoro](ui-previews/dynamic-notch-tools/pomodoro.png),
[Water Reminder](ui-previews/dynamic-notch-tools/water.png),
[Shelf](ui-previews/dynamic-notch-tools/shelf.png),
[Todo List](ui-previews/dynamic-notch-tools/todo.png), Bluetooth and Charging,
empty/form states, floating mode and a narrower viewport. These use mock data.
Native desktop drag-and-drop and notification delivery were not exercised
through the host's inaccessible Wayland/session sockets; the shared drag/drop
pattern and notification integration reuse existing shell APIs, and the Shelf
backend and reminder scheduling were tested independently.
The installed host reloaded at 2026-11-02 22:04:19.624 without related runtime
errors, and its new data file was verified as valid JSON with seven enabled
pages. Existing edited files were backed up under
`~/dock-config-backup/notch-tools-20261102-213517/`.

Eight initial offscreen Qt renders were produced and visually checked, including both
shapes and expanded media, timer, recording, brightness and charging states.
See [the preview sheet](ui-previews/dynamic-notch/preview-sheet.png). These use
mock activity data, not a screenshot of the user's running desktop.

Live compositor stacking, monitor hotplug and fullscreen interaction could not
be exercised directly from the sandbox: the host Wayland/Hyprland sockets were
not reachable. Offscreen Quickshell cannot load PanelWindow's Wayland backend.
The host process's readable log was subsequently checked: after fixing an invalid
Region child separator and a duplicate OSD visibility assignment, auto-reload
reported **Configuration Loaded** at 2026-11-02 19:27:11.061. No DynamicNotch,
TypeError, ReferenceError or binding-loop diagnostics appeared in that reload.
The existing shell process was not restarted from this session.

The updated sources were also copied into `~/.config/quickshell/MacShell`.
Original installed and repository copies of the two edited files were saved
under `~/dock-config-backup/dynamic-notch-20261102-190809/` before editing.

The button-anchored settings portal update was backed up under
`~/dock-config-backup/notch-settings-anchor-20261103-123250/`.

The generic fallback panel is limited to real expanded activities. Closing to
idle never reveals the “Dynamic Notch” placeholder while the animated surface
shrinks; regression checks cover paused media and dismissing recording results
in attached/floating modes, while retaining brightness controls.

All notch surfaces and page contents now share a GPU alpha mask built from
`NotchShape.path`, which uses the same outline math as the painted surface.
The native vector mask tracks animated width, height, expansion progress and
mode, covering attached wings and curved corners rather than only a rectangular
clip. Popup tooltips/settings remain in their authorized window overlay. The
software renderer retains rectangular clipping. Four software-rendered mask
frames verify opaque centers and excluded exterior corners/wings; the QML
regression checks all page ancestry and live mask dimensions during recording
open/close animations in both modes.

The spectrum process now resolves its helper URL into a native absolute path;
QtCore StandardPaths returned a file URL that Python previously tried to open
as a literal filename. The config directory also uses a native XDG path.
Unexpected process exits retry with 0.5–10 second backoff while demand remains;
pause/hidden states cancel retries. A process integration fixture at a filename
with spaces fails once, then streams real JSON frames, verifying recovery and
that pausing stops frame delivery. The host log confirmed live nonzero output
spectrum after the correction. Capture-client cleanup tolerates service removal.


## Downloads activity

A single `NotchDownloads` service watches the XDG Downloads directory for all
applications. Additional destinations can be set in
`~/.config/macshell/notch-downloads.json` with
`{"directories":["/absolute/other/download/folder"]}`. Existing files form a
baseline and do not replay as new downloads. Local copies and file edits in
these destinations can also appear: filesystem metadata cannot identify the
application or prove a network transfer.

The compact view shows a blue download ring and the available status. Hover or
click opens a 520 × 120 file card. Known browser totals show a real percentage,
received/total bytes, rate and estimated remaining time. The read-only Chromium
History downloads table is supported for discoverable Chrome, Chromium, Edge,
Brave, Vivaldi and Codex profiles; unsupported/locked schemas fall back to folder
tracking. Firefox and other applications work through destination tracking.
There is no extension installation or browser-profile modification.

Unknown totals stay unknown. Folder tracking displays file size and activity,
not a fabricated percentage, transfer rate or ETA. A partial file renamed to its
final filename reports completion; a direct destination write that becomes
stable is labelled **File saved**, since stable size cannot prove completion.
Partial files that stop changing show **Waiting for changes**. Directory scans
are bounded, two levels deep, ignore symlinks/hidden files and aria2 sidecars,
and poll every 750 ms. Downloads saved elsewhere require configuring that path.

Multiple downloads are tracked together with an active count; dismissing one
reveals the next. Recording controls, alarms and device/hardware feedback keep
priority. Results open briefly for eight seconds and expire after 30 seconds.
Open file and Show in Files require an explicit click, and work only for saved
or completed files. The close button dismisses the activity without cancelling
or deleting the download. No universal pause/cancel control is shown because
folder observation cannot safely control arbitrary applications.


## Nested corner geometry

`NotchGeometry.js` defines shared dimensions for every notch page and reusable
control. Expanded surfaces use a 36 px corner radius. A 16 px frame inset gives
20 px inner corners (`outer = inner + padding`). Settings popovers use a 26 px
outer radius, 16 px padding and 10 px controls. Nested Todo controls derive a
7 px radius from their 10 px row and 3 px inset. Small controls clamp radii to
half their available size; circular playback/stop indicators stay circular.

The media rail uses a 36 px width and 4 px nested padding. At most four
28 px cells fit inside the 120 px rail, so adding pages does not shrink its
icons. Selection and rail end caps remain concentric; the rail's gap from the panel is
also derived from the outer radius. Attached side wings are excluded from the
body inset, and all dimensions scale together on narrow displays. Music,
lyrics, device summaries, timer/brightness, download and recording results,
Pomodoro/Focus, Water, Shelf, Todo and their settings use these shared values.
Surface painting, glass masks and transition clipping use the same cubic
quarter-circle outline through `NotchShape.js`; compact capsules keep their
existing size. Downloads retain the compact 120 px expanded panel height.


## Simple Pomodoro layout

Setup is a 520 × 216 surface: a grouped Focus/Break selector, a 44 px
warm-white duration at the upper right, a centered duration ruler, and a
filled amber Start Timer action along the bottom. Speaker/settings controls
are smaller secondary actions. The selector uses a 2 px inset between its
18 px outer radius and the 16 px inner selection. Ruler graduations are gray
with longer major ticks; only the chosen minute receives the strong orange
marker and larger white label. A subtle dark scrim beneath the setup content
keeps the glass theme readable over bright windows.
`NotchPomodoroButton` uses a solid fill with the edge lighting from the supplied
`work/liquid-glass-buttons.html`: a continuous 165-degree rim gradient with two
brighter arcs (0.65 strength). The edge is 0.8 px on 40 px buttons, scaling down
for smaller controls. The surface has no gradient or interior reflection.
The rim is painted inside the rounded outline. Start Timer keeps its amber base;
secondary controls keep their neutral fills. Keyboard focus remains visible;
press/hover effects honor Reduced Motion. Drawing uses a small per-button Canvas
without backdrop captures or shaders.

The ruler supports minute clicks, dragging, scrolling and keyboard adjustment;
Focus/Quick/Custom support 1–180 minutes, short breaks 1–60 and long breaks
1–120. Each mode retains its own saved duration. Adjusting a timer or its sound
preference does not postpone Water Reminder.

Running, paused and completed sessions use a 480 × 96 surface with 40 px
pause/resume and cancel controls on the left, and a 14 px status plus 36 px
countdown on the right. Cancel resets the selected phase without counting a
completion. Finishing shows Done; play starts the service's next phase, including
long-break cycles. Countdown formatting preserves minutes beyond an hour and
pads single-digit minutes. Both layouts scale to narrow screens and retain the
existing shape clip throughout size transitions. Circular controls have a
20 px radius and 16 px outer padding inside the notch's 36 px corners.

The collapsed bar keeps just pause/resume and hide on the left and status/time
on the right. Hide dismisses controls while the deadline continues. The speaker
button persists `settings.pomodoroSound`; completion plays the desktop theme's
`complete` event once through `canberra-gtk-play` (libcanberra, included in the
installer dependencies) when notifications and sound
are enabled. The completion notification suppresses a duplicate daemon sound;
muting does not suppress the visible completion notification. Local rounded
outline controls retain a consistent 2.6 px stroke.

## Readable live-tool pages

Focus Decision, Water Reminder, Shelf and Todo share `NotchToolButton` with
Pomodoro: 13 px button labels, 18 px icons and 2.6 px rounded outline strokes.
`NotchToolStyle.js` maps the same outline family into context selectors and the
media navigation rail. Focus selectors use 22 px icons and larger 48 × 44
buttons; Rotation uses the shared System Settings `GlassSlider` with a 3–30
second range. The 640 × 216 panel gives the slider and actions room to breathe.

Water, Shelf and Todo use a 560 × 232 surface with a 152 px body. Supporting
labels are 12–13 px, file/task labels 15 px, actions 32 px high and Todo rows
40 px high. Shelf previews are clipped at the thumbnail radius and retain
separate file/folder reference actions. Empty states, Todo editing/management,
water hourly labels and settings retain the same hierarchy on both notch
positions. Sizes are logical and scale with the notch. Data, reminder rules,
file actions and task completion behavior remain in their existing services.


## Calendar inside the notch

Calendar uses a 560 × 256 agenda/month layout with a 760 × 340 expanded layout
inside the same clipped notch. Agenda rows show color, title and local start/end
time; the Sunday-first month grid supports selecting dates, previous/next month,
and returning to today by clicking the month label. Today is red, the selected
other date uses a white glossy glass circle with a dark numeral, and adjacent-month dates are muted. ISO week
numbers appear beside the selected date. Layouts scale with both notch positions.

The + button opens an event/task form. Events save to the existing MacShell
local SQLite calendar via `bin/calendar.py`, including its recurrence-aware
reader; no new calendar backend or account connection is introduced. The form
adds timed events for the selected date and validates the title and 24-hour
start/end times. Date-only all-day events use an exclusive end date when shown.
Today includes pending local Todo tasks, with completion using the same Todo
service. Tasks added here are undated Todo tasks and appear in today's agenda.
Reading and writing are shared per MacBar, queries refresh every minute while
Calendar is selected, and obsolete month results are discarded. Errors remain
visible instead of being replaced by sample data.

If the loaded month contains no events and there are no Todo records, an
**Example agenda** label identifies three example events and one example task.
Examples are generated only for display, never saved, and cannot complete real
Todo records. Event clicks show details. Calendar is added once when notch data
migrates to version 3; subsequent Calendar opt-outs, task history, presets, page
selection and focus settings remain intact. Calendar is available in the media
rail, page indicators, Focus Decision and Settings → Dynamic Notch → Pages.
This uses the local MacShell calendar store; it does not automatically import
GNOME Calendar accounts or online calendars.

See [compact](ui-previews/notch-calendar/examples.png),
[expanded](ui-previews/notch-calendar/expanded.png) and
[actual agenda](ui-previews/notch-calendar/real-agenda.png) fixture renders.

## Weather inside the notch

Weather uses a 560 × 256 layout with a blue inset card, rounded corners and
a camera cutout at the top. The city and current temperature sit on the left;
the condition, high and low sit on the right. Six columns show the next hours,
weather symbols and temperatures. The card uses different blue tones for sunny,
overcast/rainy and night conditions, and scales for both notch positions.

Click the city to choose automatic IP-based location or a city, switch °C/°F,
or refresh. Cancel discards changes. These settings and the Open-Meteo forecast
are shared with the desktop Weather widget. The notch also requests weather
when no desktop Weather widget is installed; one shared service refreshes every
15 minutes while Weather is enabled. Changing settings during a request queues
the latest location/units and discards obsolete responses.

Loading and connection errors have their own states and a retry button. If an
earlier forecast is still available in memory after a failed update, the card
labels it as a saved forecast. It never substitutes example temperatures for
unavailable weather. Weather is added once during version 4 migration; existing
page selection, timers, tasks, Calendar opt-outs and focus contexts are retained.
Later Weather opt-outs remain disabled. Find it in the media rail, bottom page
indicators, Focus Decision or Settings → Dynamic Notch → Pages.

See [sunny](ui-previews/notch-weather/sunny.png),
[rain](ui-previews/notch-weather/rain.png) and
[narrow](ui-previews/notch-weather/narrow.png) fixture renders.


## System Stats inside the notch

System Stats uses a 560 × 256 panel with the same material, corner rules and
responsive scaling as the other notch pages. Open it through the page indicators,
media rail, or **Settings → Dynamic Notch → Pages → System Stats**.

A 17 px System Stats heading and labeled Overview / Compare control anchor the
header. Overview uses a 44 px main reading, separate 16 px units, a 60-second
graph, and six mini gauges with 18 px readings and 12 px metric labels. Clicking a mini
gauge promotes it. Compare shows two independently selectable metrics, including
GPU + Network or Temperature + CPU. Click a colored heading to choose a metric;
choosing the other column's metric swaps them. Compare aligns each column's
heading, reading, gauge, caption, graph and time labels on the same baselines.
Long readings fit their available width; missing readings use a brighter neutral
value and visible gauge track. Mode and metric choices persist. The panel remains
560 × 256; the content starts 24 px from the top with room for page indicators.

The reader samples once per second while at least one display has this page open.
It stops after the final display leaves the page or closes the notch. CPU and
network need a second sample to calculate a rate. Graphs retain at most 60 seconds
of real readings in memory, leave gaps when readings are missing, and dim stale
readings after 3.5 seconds. No history is written to disk.

Readings are local and read-only:

- CPU: aggregate usage from `/proc/stat`, excluding idle and I/O wait.
- RAM: used physical memory based on `MemAvailable`, with used/total GiB.
- Storage: occupied space on the root volume, refreshed every 15 seconds.
- Battery: system battery percentage, energy-weighted when multiple batteries
  expose comparable energy capacities, plus charging/discharging status.
- Network: received bytes per second and a pink upload series, displayed in
  decimal B/s, KB/s, MB/s or GB/s. Physical interfaces are preferred to avoid
  counting both physical and VPN traffic. Network rings show relative recent
  traffic, not a percentage of link capacity.
- GPU: exposed DRM `gpu_busy_percent`, or a bounded `nvidia-smi` query for an
  active NVIDIA driver. With multiple supported GPUs, the busiest is displayed.
  Unsupported counters and suspended GPUs remain unavailable.
- Temperature: CPU/package sensors, with firmware maximum/critical thresholds
  used for Normal, Warm and Hot status when available.

Unsupported or missing sensors show `—`; valid zero readings remain zero.
An exited reader retries while the page remains open. No elevated permissions
are required. Data sources follow the [Linux proc documentation](https://docs.kernel.org/filesystems/proc.html),
[AMDGPU utilization interface](https://kernel.org/doc/html/latest/gpu/amdgpu/thermal.html),
[hwmon sensor interface](https://kernel.org/doc/html/v5.12/hwmon/sysfs-interface.html),
and [NVIDIA SMI query interface](https://docs.nvidia.com/deploy/nvidia-smi/index.html).

State version 5 adds System Stats once during migration and preserves tasks,
timer deadlines, the selected page, and previous Calendar/Weather opt-outs.
Later System Stats opt-outs stay disabled.

Deterministic UI fixture previews (illustrative values with a native shader
backdrop, not hardware readings):
[Overview](ui-previews/notch-stats/overview.png),
[GPU + Network](ui-previews/notch-stats/gpu-network.png),
[Temperature + CPU](ui-previews/notch-stats/temperature-cpu.png).
The test suite covers counter deltas/resets, missing hardware, source expiry,
reader sharing and shutdown, metric selection, migration, and narrow layouts.


## Primary media tabs and frosted window backdrops

The music rail keeps Music, Pomodoro and System Stats when those pages are
enabled. More opens the remaining enabled pages as 40 px labeled rows with
20 px outline icons. Escape, an outside click, page selection or closing the
notch dismisses it. The popover keeps the notch open while it is being used,
clamps to the screen and scrolls when the available height is limited. It has
no reflected border or drop shadow. The music timeline leaves a separate
gutter beside the wider rail. Existing bottom indicators remain available on
other pages. No saved menu selection is changed by this layout.

Semi Liquid Glass uses the effective blur from Appearance → Liquid Glass
without a notch-specific minimum or extra blur. The body and bevel use the same
texture at the selected blur level; a zero value bypasses pre-blur. Floating
windows are softened according to that shared setting. The material contrast
floor keeps content readable, while the shared settings adjust density, liquid
strength and grain.
The removed white rim and inset dark contour remain disabled.

Fixture previews: [media rail](ui-previews/notch-navigation/rail.png),
[More pages](ui-previews/notch-navigation/more.png),
[narrow screen](ui-previews/notch-navigation/narrow.png),
and [floating-window frost](ui-previews/notch-navigation/frosted-window.png).


## Shared frosted dropdown material

More pages, the System Stats metric chooser and Weather location preferences
now inherit the same frosted surface as audio output, Pomodoro/Focus, Water
Reminder and Calendar menus. Their solid per-page backgrounds have been removed.
Dropdowns use the actual File/Edit LGlass renderer with the menu bar's 42 px
clear blur baseline and shared Liquid Glass intensity preset (up to 80 px);
this does not change the notch body's blur.
The crop and blur operate at matching texture resolutions, then upscale the
frosted result beneath the content. The visible notch is composited over the desktop before capture and blur.
The capture exists only while the dropdown is visible.

Dark and light appearances now use the same shader tint, saturation, rim,
refraction and shadow as File/Edit. The original MenuBorder component supplies
the same wallpaper-tinted edge. Secondary text stays brighter in dark mode. Software rendering and Reduce Transparency use an opaque
fallback. Menu anchoring, spring motion, scrolling, keyboard/outside dismissal
and saved settings retain their existing behavior.

Validation covers seven dropdown entry points, shared material identity, both
appearances, reduced transparency, the material preset endpoints and the
existing form/navigation tests.


## Dropdown blur includes the visible notch

The shared dropdown surface first composites two live captures: the desktop
backdrop, then the actual notch surface and its contents at the same coordinates.
Frosting samples that composite, so overlapping portions include the notch
instead of showing the desktop through it. Areas outside the notch still show
the desktop. The notch remains visible while being sampled.

The dropdown is a window-overlay portal outside the sampled notch subtree,
which prevents recursive capture of the dropdown itself. Capture bounds track
its anchor, spring scale, size and dragged position, including the blur margin.
Both capture layers use the same bounds and are released when the dropdown
closes or Reduce Transparency disables frosting. This correction changes the
blur source, retaining the existing body and dropdown material settings.

An offscreen Qt capture verified both the notch and exterior backdrop in one
image, with the open dropdown excluded. QML checks cover attached/floating modes,
opening scale, drag offsets, coordinate alignment and cleanup.


## Exact File/Edit dropdown glass renderer

`NotchMenuBarGlass.qml` retains the self-contained LGlass material pipeline from
`UpstreamBar/MacBar.qml`, with a portal contour adapter for the anchored tail. `NotchSettingsPopup.qml` now uses that renderer instead
of its separate frosted tint overlay. It reads the menu bar's effective opacity, liquid, rim, grain and border color.
The contour-aware shader copies the File/Edit optical material and adapts its
distance field for the tail. The menu border colors follow that same contour.
All notch dropdowns inherit it.

The optical material parameters match File/Edit and Bluetooth: clear blur 42 px,
thickness 22, strength `0.55 × effGlassLiquid`, saturation 1.25, shader tint
`effGlassOpacity × 0.55`, `rimTint = 1`, `ringW = 1.4`, and the same shadow.
Popup sizing, inner padding, anchoring and the notch-over-desktop composite
remain local to the notch. The body glass is unchanged. A shader failure or
reduced transparency retains the fallback and usable controls.

Validation checks the renderer's portal shader, settings, border color and capture
origin. The copied shader was rendered with native GLES in dark and light
appearances using the Qt-captured notch/desktop composite.


## Restored glass dropdown tail

Dropdowns retain the original 9 px anchored tail in the liquid renderer as well
as the opaque fallback. `notch-menu-tail.frag` copies the File/Edit shader's
optical material; its contour adapter combines the rounded body with the
original two cubic tail curves. Refraction, coverage, edge light and shadow
therefore follow the tail without a line across its base. The border also uses
the existing portal outline instead of a rectangular frame.

Pointer position and the drag-driven tail amount remain live QML inputs.
The notch/desktop composite and material settings remain unchanged. Native
GLES renders checked dark and light tails, a shifted pointer, and a retracted
tail, including alpha coverage at the tip and transparent areas beside it.
