import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Decode at the screen's physical resolution, preserving HiDPI detail without
// retaining the original 4K/5K pixels in every process. Static blur stays cached on disk.
Item {
    id: background
    property string screenName: ""
    property url imageSource: LaunchpadGlassState.imageFor(screenName)
    property real backgroundBlur: LaunchpadGlassState.preferences.backgroundBlur !== undefined ? LaunchpadGlassState.preferences.backgroundBlur : 0.35
    property real dimming: LaunchpadGlassState.preferences.backgroundOpacity !== undefined ? LaunchpadGlassState.preferences.backgroundOpacity : 0.04
    readonly property real renderScale: Math.max(1, Screen.devicePixelRatio)
    readonly property int pixelWidth: Math.max(1, Math.round(width * renderScale))
    readonly property int pixelHeight: Math.max(1, Math.round(height * renderScale))
    readonly property real blurRadius: Math.max(0, Math.min(1, backgroundBlur)) * 64 * renderScale
    readonly property string signature: JSON.stringify([imageSource.toString(), pixelWidth, pixelHeight, blurRadius])
    property string requestedSignature: ""
    property url cachedSource: ""
    property string cachedSignature: ""
    readonly property bool ready: wallpaper.status === Image.Ready || blurredWallpaper.status === Image.Ready
    clip: true

    onSignatureChanged: renderDelay.restart()
    Component.onCompleted: renderDelay.restart()
    Timer {
        id: renderDelay
        interval: 90
        onTriggered: {
            if (!background.imageSource.toString() || background.width < 1 || background.height < 1 || background.blurRadius <= 0) return;
            if (renderer.running) return;
            background.requestedSignature = background.signature;
            renderer.command = ["python3", (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                + "/quickshell/Common/render_launchpad_background.py", background.imageSource.toString(),
                String(background.pixelWidth), String(background.pixelHeight), String(background.blurRadius)];
            renderer.running = true;
        }
    }
    Process {
        id: renderer
        stdout: StdioCollector {
            onStreamFinished: {
                if (background.requestedSignature !== background.signature) return;
                try {
                    const result = JSON.parse(text);
                    if (typeof result.url === "string") {
                        background.cachedSignature = background.requestedSignature;
                        background.cachedSource = result.url;
                    }
                } catch (error) { /* Keep the last complete wallpaper on failure. */ }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn(text.trim())
        }
        onExited: (exitCode, exitStatus) => {
            if (background.requestedSignature !== background.signature) renderDelay.restart();
        }
    }
    Rectangle { anchors.fill: parent; color: "#17191c" }
    Image {
        id: wallpaper
        anchors.fill: parent
        // The original is a fallback only. Drop it once the prepared blur is ready.
        source: background.blurRadius <= 0 || blurredWallpaper.status !== Image.Ready ? background.imageSource : ""
        sourceSize: Qt.size(background.pixelWidth, background.pixelHeight)
        fillMode: Image.PreserveAspectCrop
        visible: background.blurRadius <= 0 || blurredWallpaper.status !== Image.Ready
        smooth: true
        mipmap: true
        cache: false
    }
    Image {
        id: blurredWallpaper
        anchors.fill: parent
        source: background.blurRadius > 0 && background.cachedSignature === background.signature ? background.cachedSource : ""
        sourceSize: Qt.size(background.pixelWidth, background.pixelHeight)
        fillMode: Image.PreserveAspectCrop
        visible: background.blurRadius > 0 && status === Image.Ready
        smooth: true
        mipmap: true
        asynchronous: true
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Math.max(0, Math.min(1, background.dimming)))
    }
}
