# Photo Booth for MacShell

A native Qt 6 camera application for this Hyprland desktop. Its layout follows
the supplied Photo Booth reference: a camera stage, compact title bar with the
existing MacTahoe controls, three capture modes on the left, a red shutter in
the center, and Effects on the right. This is an independent Linux application.

## Open

Choose **Photo Booth** in Launchpad, or run:

```sh
~/.local/bin/tahoe-photobooth
```

- **Single photo:** take one JPEG, with a three-second countdown.
- **Four photos:** capture four poses, one second apart, and save a 2 × 2 JPEG.
- **Video:** record MP4/H.264 with AAC audio from the selected microphone.
- **Effects:** nine live previews including Normal, Black & White, Sepia,
  Mirror, Fish Eye, Squeeze, Stretch, Twirl, and Thermal. Distortion intensity
  can be adjusted. The chosen effect is applied to saved photos and videos.
- **Gallery:** select a thumbnail to view a photo or play a video; copy,
  export, or move it to Trash. Settings → Open Photo Booth folder opens the
  library in Files.
- **Settings:** a compact dropdown below the title-bar settings button;
  dismiss it with Escape, an outside click, or the same settings button.
  Choose camera and microphone, enable microphone audio,
  mirror preview and output, toggle screen flash, or hide the gallery strip.
- **Window controls:** close; minimize through MacShell's existing Dock IPC;
  maximize/restore. The title bar supports native Wayland movement and the
  window edges support resize.

The app follows `appearanceMode` in `~/.config/macbar/settings.json`. Explicit
Light/Dark modes take precedence; Auto uses the resolved `darkMode` value.
Settings changes, including atomic replacements, update an open window.
`macdock/settings.json` is a compatibility fallback. Camera preview remains
black behind its image in both themes.

Controls follow macOS Tahoe's rounded shapes: capsule action buttons, circular
icon buttons, a sliding capsule mode selector, and switches in Settings. Shared
layered surfaces provide subtle highlights, shadows, hover feedback, and press
animations in both themes, including software rendering. Focus rings appear
for keyboard navigation. The toolbar keeps all gallery actions accessible at
the minimum window size.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Capture or stop recording | Space |
| Skip countdown | Alt-click shutter |
| Skip screen flash | Shift-click shutter |
| Skip both | Alt+Shift-click shutter |
| Cancel countdown, close effects, or return to camera | Escape |
| Camera settings | Ctrl+, |
| Export selected capture | Ctrl+E |
| Quit (finishes active recording first) | Ctrl+Q |

## Files and privacy

Captures are stored locally in the XDG Pictures folder under `Photo Booth`
(normally `~/Pictures/Photo Booth`). Photos are JPEG; videos are MP4.
Video poster images are in `.thumbnails`. Camera/effect preferences are in
`~/.config/MacShell/PhotoBooth.conf` through QSettings. No network service or
upload is used. Camera access begins on launch, and microphone capture begins
only when recording with audio enabled. If there is no microphone, recording
proceeds without audio. Camera failures display a retry
state and disable capture. Closing during recording waits for the video to save.

Camera frames are processed at up to 1280 × 960 and around 30 fps. Actual frame
rate and resolution depend on the webcam and available CPU. Effects previews
use smaller frames to reduce load. Four-photo composites retain four tiles.
Files are saved atomically where supported; deleting uses the system Trash.

## Build and install

Requires C++20, CMake, Ninja, Qt 6.9+ Core/Gui/Quick/QuickControls2/Multimedia,
ShaderTools, Qt DBus, and Qt's FFmpeg multimedia backend. On Linux, desktop
integration also requires the matching Qt Multimedia and Gui private development
headers; rebuild the application when upgrading these Qt modules. Tests also use QtTest, `ffmpeg`, and
`ffprobe`. The root MacShell installer installs these dependencies on Arch Linux.

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DBUILD_TESTING=ON
cmake --build build -j 3
cmake --install build
update-desktop-database "$HOME/.local/share/applications"
```

The application identifies itself as `org.macshell.PhotoBooth`. Once its custom
controls are ready, it adds the existing `macshell-native-controls` window tag
to its own PID's window, so Hyprbars does not add a second title bar.

## Validation

```sh
env -u DBUS_SESSION_BUS_ADDRESS QT_QPA_PLATFORM=offscreen \
  QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE= \
  ctest --test-dir build --output-on-failure
```

Tests isolate configuration and media in temporary directories. They verify
effect output, mirroring, four-photo placement, actual JPEG capture/export,
countdown/cancellation, stale-timer cancellation, unavailable-camera handling,
live theme changes, a real encoded/decoded video containing an audio stream,
and UI clicks for modes, effects, capture, and settings. UI tests save previews
in the build directory. Demo mode uses a labelled synthetic image and test tone:

```sh
~/.local/bin/tahoe-photobooth --demo --library /tmp/photo-booth-demo
```

Synthetic tests do not validate this computer's physical camera, microphone,
Wayland window movement, or Dock animation. Those require opening the installed
application in a desktop session.

The interaction reference is [Apple's Photo Booth guide](https://support.apple.com/en-euro/guide/photo-booth/welcome/13.1/mac/26).
Capture/encoding uses [Qt Multimedia](https://doc.qt.io/qt-6/qvideoframeinput.html).

Live camera previews, saved-photo previews, and video playback fill their
available area with a centred crop, preserving the media's aspect ratio.
Saved captures retain the camera's original size.
For DroidCam, connect the phone and press Start in the Linux client. Photo Booth
refreshes virtual-camera capabilities while waiting for frames, including when
DroidCam connects after the application was opened. Settings provides Open
DroidCam and Refresh controls.

Export uses Nautilus's native SaveFile chooser over the session bus, the same
backend used by GNOME's file chooser portal. It requires Nautilus 47 or later
. The chooser receives the suggested filename,
JPG/MP4 filters, and the parent window's Wayland/X11 identifier. Cancelling never
writes a file; accepting exports the original capture atomically. The last export
folder is remembered. No desktop-wide portal or Qt theme changes are required.
