# Validation on this desktop

Validated on 26 October 2026 using the installed Qt 6.12/FFmpeg multimedia backend.

- C++ release build completed without compiler warnings.
- `capture-effects-library-recording`: passed (10 QtTest checks including setup/cleanup).
- `desktop-ui-interactions`: passed (4 QtTest checks including setup/cleanup).
- Tested UI actions: effects selector, effect selection, mode switches,
  Alt+Shift shutter capture, camera settings, live Light appearance, video
  start/stop, and disabled capture without a camera.
- The saved video fixture was inspected with ffprobe: H.264 video, 960 × 640,
  duration 1.433333 s; AAC audio, 48000 Hz mono, duration 1.36 s.
- ffmpeg decoded the complete fixture with no decoding errors. A decoded
  frame was checked for the selected black-and-white effect.
- Desktop entry validated. Quickshell DesktopEntries detected one visible
  `org.macshell.PhotoBooth` entry named `Photo Booth`.
- The installed SVG icon successfully rendered through QIcon. The desktop
  entry uses its absolute installation path so it is also found when a
  platform theme does not expose user icon search paths.
- Installed executable reports `Photo Booth 1.0.0` in an offscreen CLI check.

Artifacts in `build/`:

- `photobooth-dark.png`
- `photobooth-light.png`
- `photobooth-effects.png`
- `photobooth-no-camera.png`
- `recording-fixture.mp4` (labelled synthetic image and test tone)
- `Testing/Temporary/LastTest.log`

Settings now uses a nonmodal dropdown anchored below the settings button.
The updated UI test passed for toggle-open/close, outside-click dismissal,
Escape dismissal, microphone checkbox interaction, and Light/Dark rendering.
Previews: `build/photobooth-settings-light.png` and
`build/photobooth-settings-dark.png`.

The test environment isolated configuration and media in temporary directories.
Physical webcam/microphone access, native Wayland movement/resize, and MacShell
minimize/restore animation could not be exercised from the Codex sandbox.
Open Photo Booth from Launchpad in the desktop session to check those devices.

## Tahoe button redesign, 26 October 2026

The release build and all three CTest suites passed (22.50 s): native Nautilus
export, capture/effects/library/recording, and desktop UI interactions. UI tests
reported no QML warnings. The installed executable was updated atomically so an
existing window can finish normally before reopening the new version.

Additional UI coverage checks gallery navigation, image copying, keyboard focus
after Tab versus mouse clicks, and selection from a synthetic two-camera device
dropdown in Light and Dark appearances. At both 800 × 640 and 560 × 450, all
gallery action buttons remain inside the window without overlap. Existing tests
also cover the redesigned switches, mode control, shutter, effects, and delete
confirmation. Tests use isolated settings and demo captures.

Reviewed previews in `build/`:

- `photobooth-gallery-light-560.png` and `photobooth-gallery-dark-560.png`
- `photobooth-gallery-light-800.png` and `photobooth-gallery-dark-800.png`
- `photobooth-devices-light.png` and `photobooth-devices-dark.png`
- `photobooth-settings-light.png` and `photobooth-settings-dark.png`
- `photobooth-delete-light.png` and `photobooth-delete-dark.png`
- `photobooth-effects.png`

These previews use Qt's offscreen software renderer. Desktop-session and physical
camera validation have the same limitations described above.
