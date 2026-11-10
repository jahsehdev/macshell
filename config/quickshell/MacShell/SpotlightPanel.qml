import QtQuick

// A search capsule unfolds into a panel without stretching its text or icons.
Item {
    id: panel
    default property alias contentData: viewport.data
    property bool active: false
    property bool reduceMotion: false
    property bool animateEntrance: true
    property real capsuleWidth: width
    property real reveal: active ? 1 : 0
    readonly property real surfaceRadius: 24 + 8 * reveal
    readonly property real revealedWidth: viewport.width
    readonly property real revealedHeight: viewport.height
    opacity: Math.min(1, reveal * 5)
    visible: reveal > 0.001
    enabled: active

    Behavior on reveal {
        enabled: panel.animateEntrance
        NumberAnimation {
            duration: panel.reduceMotion ? 100 : (panel.active ? 380 : 180)
            easing.type: Easing.OutExpo
        }
    }

    Item {
        id: viewport
        width: panel.reduceMotion ? panel.width : panel.capsuleWidth + (panel.width - panel.capsuleWidth) * panel.reveal
        height: panel.reduceMotion ? panel.height : 48 + (panel.height - 48) * panel.reveal
        clip: true
    }
}
