# MacLock Hyprland IPC integration

MacLock has a dedicated Quickshell IPC endpoint, `lockscreen.lock`. The helper `lock-via-ipc.sh` makes the keybind self-starting: it starts an IPC-capable MacLock instance if needed, waits for it to become ready, then requests the lock. Each lock process exits after unlock; the helper starts a fresh one for the next lock because a Wayland session-lock object should not be reused.

## Install

Copy this `MacLock` directory to `~/.config/quickshell/MacLock/` so `shell.qml` is at `~/.config/quickshell/MacLock/shell.qml`.

In your Lua-driven Hyprland config, add:

```lua
hl.bind("SUPER + L", hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
```

This uses the `hl.bind` / `hl.dsp.exec_cmd` style. Change `SUPER + L` if that key is already used, and adjust the helper path if you installed MacLock elsewhere.

## Direct IPC

If an IPC-capable MacLock instance is currently running, the direct IPC command is:

```sh
qs -c MacLock ipc call lockscreen lock
```

The helper launches the IPC-capable process with `MACLOCK_DAEMON=1`. Existing setups that run `qs -c MacLock` directly (for example from `maclock.sh`/hypridle) keep the original one-shot behavior: the session locks immediately and MacLock exits after unlock.

Preview mode is unchanged: `MACLOCK_PREVIEW=1 qs -c MacLock` opens the visual preview and does not request a real lock.

## Now Playing and lyrics

The media card has a 32 px corner radius, larger controls and a bold title.
Lockscreen typography watches the font family and style selected in Settings,
including changes made while the lockscreen is open. Explicit title and clock
weights remain readable; italic selections apply throughout.

The lockscreen media card places album artwork across its left side, fading in
alpha into the Liquid Glass controls on the right. The title, artist, current
lyric, seek bar and playback controls remain visible in the compact card. Tap the
cover to enlarge it, or the lyrics button to open the scrolling lyrics view.
Existing top/bottom placement and drag behavior are preserved.

Four animated playback bars sit below the lyrics button and stop while paused,
hidden or Reduce Motion is enabled. A green system-volume slider sits below
the playback timestamps. It follows the default PipeWire output, unmutes on
adjustment and supports dragging and keyboard input; it is disabled when no
audio output is available. Previous/play/next and lyrics glyphs share a 40-unit
size, with compact spacing and separate hit areas.

Lyrics retain the original focus animation: the current line is sharp, nearby
lines blur and dim, and each line glides into place. Blur changes animate as the
focus moves. Plain lyrics use the same appearance while the reader scrolls;
only timestamped lyrics follow playback automatically. Desktop and notch use
the same blur, opacity and scale transitions. A shared playback clock advances
between MPRIS reports and reanchors after seeks and pause/resume. The inline lyric uses a
blur crossfade without stretching the words.

Every lockscreen slab, including the password pill, notifications, live activity,
avatar and media card, uses `Common/LiquidGlassSurface.qml`. Optical parameters
come from `Common/GlassMaterial.qml`, matching the Dock and Launchpad. One shared
backdrop blur feeds the slabs and clock; material intensity and Reduce
Transparency apply throughout. Clock glyphs keep their mask and chosen tint.

`Lyrics.qml` wraps `Common/LyricsService.qml`, also used by desktop and notch.
The shared service runs `Common/lyrics.py`, a Python standard-library client for the
[LRCLIB API](https://lrclib.net/docs.txt). It cleans presentation suffixes from
metadata, omits unknown duration, and falls back to searches ranked by title,
artist, album and duration. Synced and plain lyrics are supported. Responses for
an older track are discarded, and connection errors are shown separately from a
successful search with no matching lyrics. Reopen lyrics to retry; automatic
retries are bounded and respect server cooldowns.

A plain result from the signature endpoint does not stop the search for a
matching synchronized version. Recordings with different durations cannot win
solely because they include timestamps. Plain lyrics remain available if the
additional search fails or is throttled.

Only successful lyrics are cached, in `~/.cache/macshell/lyrics-v3`, for up to
30 days for synchronized lyrics, or one day for plain lyrics before checking
again for timestamps. Earlier plain-only cache entries are also rechecked while
remaining available as an offline fallback. The previous `lyrics` directory is ignored because its empty JSON
entries could preserve a temporary lookup failure indefinitely. Those old files
can remain on disk without affecting the new lookup.

Run the targeted checks without locking the session:

```sh
python3 config/quickshell/MacLock/tests/test_lyrics.py
bash config/quickshell/MacLock/tests/run-media-tests.sh
```

The UI tests use the production lockscreen component with a fake player and lock
state. They exercise seek/playback, lyrics and artwork modes, accessibility,
password input, and layouts at 1280×720, 1920×1080 and 2560×1440. The lyrics
tests exercise the real QML child-process lifecycle with offline API fixtures.
