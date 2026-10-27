import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"

// ─────────────────────────────────────────────────────────────────────────────
//  Quickshell Launchpad — a macOS-style fullscreen app launcher for Hyprland.
//
//      qs -c launchpad
//      qs -c launchpad ipc call launchpad toggle
//
//  Everything visual lives in components/; Theme.qml and LaunchpadState.qml are
//  singletons next to this file.
//  Dark glass shares Common/DarkGlass.glsl: clear coat and a fine luminous rim.
// ─────────────────────────────────────────────────────────────────────────────
ShellRoot {
    id: shell

    // Full-screen blurred wallpaper window. It is a normal window, so the
    // layer-shell top bar and dock are always rendered above it.
    Variants {
        model: Quickshell.screens

        LaunchpadBackdrop { }
    }

    // The interactive Launchpad content.
    Variants {
        model: Quickshell.screens

        LaunchpadWindow { }
    }

    IpcHandler {
        target: "launchpad"

        function toggle(): void {
            LaunchpadState.toggle();
        }

        function open(): void {
            LaunchpadState.open();
        }

        function close(): void {
            LaunchpadState.close();
        }

        function dismiss(): void {
            LaunchpadState.dismiss();
        }

        function search(q: string): void {
            LaunchpadState.open();
            Qt.callLater(function () { LaunchpadState.setQuery(q); });
        }

        function page(n: int): void {
            LaunchpadState.setPage(n);
        }

        function mock(on: bool): void {
            LaunchpadState.setMock(on);
        }

        function edit(on: bool): void {
            LaunchpadState.editMode = on;
        }

        function reset(): void {
            LaunchpadState.resetLayout();
        }
    }
}
