# Golden Gate 27 — GG-08 report (screen recording + audio)

Date: 2026-10-31
Scope: GG-08
Status: implemented, deployed to the active shell, all four audio modes verified
end-to-end on the 1280×800 session

## Result

The screen recorder keeps its existing region/screen capture and lifecycle, and now
records the audio source chosen in Control Center → Screen Recording:

| Option | Source handed to `wf-recorder` |
| --- | --- |
| None | no `--audio` argument (video only) |
| System | the default sink's `.monitor` source |
| Mic | the default source |
| Both | a private `module-null-sink` fed by two `module-loopback` modules (system + mic), recorded from its monitor |

## What changed

`MacShell/UpstreamBar/MacBar.qml`

- New persisted setting `recordAudio` (`none | system | mic | both`) in
  `~/.config/macbar/settings.json`, part of `settingKeys` (saved automatically on
  change, applied on load, reset to `none` by *Reset Settings*).
- `startRecording()` snapshots the choice into `recordAudioActive`, so changing the
  setting cannot re-route a recorder that is already running.
- The recorder shell script (`recordProc`) gained the audio stage:
  - validates `pactl get-default-sink` / `get-default-source` against
    `pactl list short sources` before using them;
  - in *Both* mode loads `module-null-sink` + two `module-loopback` modules with a
    per-run name (`macshell-record-<pid>`), records the mix monitor, and writes the
    module ids to `${XDG_RUNTIME_DIR}/macbar-recorder-mix` for cleanup;
  - missing sources degrade gracefully: *Both* falls back to the available source,
    an unavailable source records video only, and a notification says
    "Recording Without Audio";
  - a `trap` unloads the mix modules if the wrapper is interrupted before it
    replaces itself with `wf-recorder`.
- Cleanup paths (recorder exit, `recKill` force-stop, next start, shell start-up)
  unload the recorded mix modules from the state file and remove it; start-up also
  sweeps any leftover `macshell-record-*` modules and finishes orphaned recorders,
  as before.
- Control Center → Screen Recording page gained an **Audio** row: a segmented glass
  control (None / System / Mic / Both) with a live status text ("Applies to the
  next recording", red "Recording: …" while active). The control is disabled while
  a recording runs. The Record tile in the Control Center grid shows the timer plus
  the active audio mode (e.g. `0:12 · System + Mic`).
- Accessibility: the four segments are `Accessible.RadioButton`s with names and
  press actions, matching the existing CC control pattern.

## wf-recorder argument gotcha (fixed by testing)

`wf-recorder` 0.6.0 accepts `-a` and `--audio[=DEVICE]`, but **`-a DEVICE` with a
separate argument is silently ignored** and the recorder falls back to the *default
source*. The first end-to-end run proved it: in "System" mode PipeWire linked the
recorder to the microphone (`alsa_input…`) instead of the sink monitor, and the log
said `Using PulseAudio device: default`. The script therefore always uses the
attached form `--audio=DEV`, which routes correctly.

## Verification

Recordings were started and stopped through a temporary IPC hook
(`qs -c MacShell ipc call recordtest start <mode>`), which was removed afterwards.
For every run the PipeWire graph was inspected with `pw-dump` to confirm which node
`wf-recorder` actually captured, and the output file was checked with `ffprobe`:

| Mode | Capture node observed | Streams in file |
| --- | --- | --- |
| none | — | video only (h264) |
| system | `alsa_output…analog-stereo` (sink monitor ports) | video + AAC 48 kHz stereo |
| mic | `alsa_input…analog-stereo` | video + AAC 48 kHz stereo |
| both | `macshell-record-<pid>` (mix null sink monitor) | video + AAC 48 kHz stereo |

- During a *Both* recording, `pactl list short modules` showed exactly the expected
  null sink + two loopbacks; after Stop everything was unloaded, the pidfile was
  removed and no `wf-recorder` process remained.
- Crash recovery: with the shell reloaded while stale `macshell-record-*` modules
  and a leftover state file existed, the start-up sweep unloaded both and deleted
  the file.
- Persistence: the last test run left `"recordAudio": "both"` in
  `~/.config/macbar/settings.json`; it was set back to `"none"` (the default)
  through the same path.
- UI: the record page renders the Audio row and segmented control with the persisted
  segment selected; while recording the control is dimmed and the status text turns
  red ("Recording: System + Mic"). Screenshots in
  `docs/ui-previews/golden-gate-gg08/`.
- Shell reload after every change: `Configuration Loaded`, no new QML errors.
- The temporary IPC hook was removed; `qs ipc show` no longer lists `recordtest`,
  and the deployed file matches the repository byte-for-byte.

## Notes / limitations

- The audio snapshot happens at start; changing the default sink/source during a
  recording does not re-route it.
- *System + Mic* mixes through a null sink inside PipeWire; there are no extra
  processes to leak, only modules, and those are covered by all four cleanup paths.
- No pointer/key injector is available, so the segmented control was exercised
  through its persisted state, its accessibility actions and a temporary IPC hook
  rather than a real click.

## Deployment

`MacShell/UpstreamBar/MacBar.qml` was copied to `~/.config/quickshell/...` and
verified with `cmp` (identical). Nothing was installed and no model was downloaded.
