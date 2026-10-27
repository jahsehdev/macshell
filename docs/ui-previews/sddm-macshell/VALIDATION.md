# SDDM MacShell preview validation

- Idle: 1920×1080, actual theme.conf, selected user icentry.
- Typing: 1920×1080, password masked, backdrop blur, glass pill expands.
- Failed login: 1366×768, stub SDDM receives the selected user/session, password clears, busy state resets, error appears.
- Reset: 1366×768, password/error clear, engagement resets.
- Shader rendering: Qt Quick RenderControl + Mesa llvmpipe, desktop OpenGL 3.3, actual bundled QSB files.
- Real SDDM greeter: theme loads in --test-mode with offscreen software backend; terminated by timeout. Test-mode socket warning is expected without a daemon socket.
- Shell syntax and Python compilation: passed.

SF Pro is absent in the rendering environment. Screenshots use Qt font fallback. The installer syncs current MacShell settings and bundles exact SF font matches from the desktop user before sudo when they are available.

System installation was not performed: /usr/share/sddm and /etc/sddm are outside the writable roots of this session. Run `bash ~/.local/bin/install-macshell-sddm` in the desktop terminal to install with sudo, keeping the current session running.

Original files are saved in ~/dock-config-backup/sddm-ui-fix-20261026/.
