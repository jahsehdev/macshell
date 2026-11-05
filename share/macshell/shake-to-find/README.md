# Shake to find

Move the mouse or a finger on the trackpad rapidly back and forth to enlarge the
actual MacTahoe/application cursor up to 4×. It smoothly returns to its original
size after shaking stops. The pointer's click position stays fixed at the image's
hotspot. Ordinary movement, tiny jitter, isolated corrections and large pointer
warps are rejected. Mouse-button presses, pointer constraints and the lock screen
cancel the effect. The animation timer runs only while magnification is active.

This is a MacShell native Hyprland plugin, built against the installed compositor
headers. It uses one checked software-cursor rendering hook and Hyprland's own
texture/rendering path, including client cursors and monitor scale selection.
Hardware cursors are temporarily locked to software only during the effect.
Textures are scaled without reloading the theme, so large raster cursors may look
softer. No extra overlay window, daemon or root input-device access is required.

`config/hypr/macshell_cursor.lua` is loaded by the main Hyprland configuration.
Defaults can be changed after loading the plugin:

```lua
hl.config({plugin = {macshell_shake = {enabled = 1, max_scale = 4.0}}})
```

Set `enabled = 0` to disable; `max_scale` accepts 1–8. The default theme and size
are not changed. The plugin requires x86_64 and the cursor API used by the
installed Hyprland 0.57 build. Complete API hash and function signatures are
validated at load. Do not combine it with another cursor rendering hook such as
`dynamic-cursors`.

After updating Hyprland, rebuild and reload from a desktop terminal:

```sh
sh ~/.local/share/macshell/shake-to-find/build.sh
~/.local/bin/macshell-cursor-reload
```

The reload helper checks the running compositor commit before changing plugins.
After loading, it reloads the configuration to clear an earlier plugin-load error.
It only reloads shake to find and leaves applications open. `--ensure` preserves
an already current instance. The main config also loads it on subsequent login
or config reload. Load status is written to `~/.cache/macshell/shake-to-find.status`.

To check the pure detector, easing and geometry without a desktop session:

```sh
c++ -std=c++20 -Wall -Wextra test_shake.cpp -o /tmp/macshell-test-shake
/tmp/macshell-test-shake
```

Desktop verification: try horizontal and vertical shakes on the wallpaper, a
text cursor, a link and an application cursor; then check ordinary fast movement,
dragging, a second monitor, screenshots and plugin unload during magnification.

Version 1.1 fixes runtime symbol lookup: Hyprland filters mangled linker names,
so method queries must omit the `CPointerManager::` prefix. Exact ABI signature
validation remains in place. The build now runs `test_symbols.py` against the
installed compositor to catch this initialization failure before installation.
