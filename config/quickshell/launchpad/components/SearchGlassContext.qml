import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import "../Common" as Common

// One frozen backdrop shared by the search capsule and Settings disc.
// Capture before revealing the controls, so they never refract their own pixels.
Item {
    id: root
    property var captureScreen: null
    property Item backdrop: null
    property point screenPosition: Qt.point(0, 0)
    property bool active: false
    readonly property real downsample: Common.GlassMaterial.surfaceBlur >= 8 ? 0.5 : 1
    readonly property real blurAmount: Common.DesktopPreferences.reduceTransparency ? 0 : Math.min(1, Common.GlassMaterial.surfaceBlur * downsample * 1.4 / 64)
    property bool captureTimedOut: false
    readonly property bool ready: material.item !== null && material.item.ready && !captureTimedOut
    readonly property var texture: material.item ? material.item.texture : null
    readonly property vector2d textureSize: material.item ? material.item.textureSize : Qt.vector2d(1, 1)
    readonly property vector2d sourceOffset: material.item ? material.item.sourceOffset : Qt.vector2d(0, 0)
    readonly property bool waiting: material.active && !ready && !captureTimedOut
    onActiveChanged: captureTimedOut = false
    Timer {
        id: deadline
        interval: 200
        running: root.waiting
        onTriggered: root.captureTimedOut = true
    }
    Loader {
        id: material
        anchors.fill: parent
        active: root.active && (root.captureScreen !== null || root.backdrop !== null)
        sourceComponent: Item {
            id: glass
            readonly property bool ready: root.backdrop !== null || snapshot.hasContent
            readonly property var texture: frosted
            readonly property vector2d textureSize: Qt.vector2d(crop.sourceRect.width, crop.sourceRect.height)
            readonly property vector2d sourceOffset: Qt.vector2d(root.screenPosition.x - crop.sourceRect.x,
                                                                  root.screenPosition.y - crop.sourceRect.y)
            ScreencopyView {
                id: snapshot
                width: root.captureScreen ? root.captureScreen.width : 1
                height: root.captureScreen ? root.captureScreen.height : 1
                opacity: 0
                captureSource: root.backdrop !== null || root.captureTimedOut ? null : root.captureScreen
                live: root.backdrop === null && !hasContent && !root.captureTimedOut
                paintCursor: false
            }
            ShaderEffectSource {
                id: crop
                visible: false
                sourceItem: root.backdrop ? root.backdrop : snapshot
                readonly property real margin: 128
                readonly property real cropX: Math.max(0, root.screenPosition.x - margin)
                readonly property real cropY: Math.max(0, root.screenPosition.y - margin)
                sourceRect: Qt.rect(cropX, cropY,
                    Math.max(1, Math.min(sourceItem.width, root.screenPosition.x + root.width + margin) - cropX),
                    Math.max(1, Math.min(sourceItem.height, root.screenPosition.y + root.height + margin) - cropY))
                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * root.downsample)),
                                     Math.max(1, Math.round(sourceRect.height * root.downsample)))
                live: true
                smooth: true
            }
            MultiEffect {
                id: frost
                visible: false
                source: crop
                width: crop.sourceRect.width * root.downsample
                height: crop.sourceRect.height * root.downsample
                blurEnabled: true
                blurMax: 64
                blur: root.blurAmount
                autoPaddingEnabled: false
            }
            ShaderEffectSource {
                id: frosted
                sourceItem: frost
                visible: false
                live: true
                mipmap: true
                smooth: true
            }
        }
    }
}
