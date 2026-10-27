import "Common" as Common
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// A window card. Source stays attached through the switcher's closing fade;
// the Loader destroys the card only after it is no longer visible.
Item {
    id: card
    required property var entry
    property var hub: null
    property url iconSource: ""
    property bool selected: false
    property bool dark: false
    property bool captureActive: false
    property bool inView: true
    property string fontFamily: "SF Pro Text"
    readonly property string address: String(entry.addr || "").replace(/^0x/, "")
    readonly property bool closing: !!(hub && address && hub.closingWins[address])
    readonly property bool quiet: !!(hub && (hub.captureQuiet || hub.glassHold))
    readonly property var captureWindow: {
        if (closing) return null;
        if (hub && address) {
            var tick = hub.tlTick;
            return hub.tlFor(address);
        }
        return entry.win || null;
    }
    readonly property var minimizedRecord: hub && hub.dock && hub.dock.minimize
        ? hub.dock.minimize.records[address] : null
    readonly property bool frameReady: capture.hasContent
    readonly property bool snapshotReady: !frameReady && saved.status === Image.Ready
    readonly property color ink: dark ? "#F5F5F7" : "#25252B"

    Common.ContinuousRectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 13
        color: card.selected ? (card.dark ? "#304C8FFF" : "#183D83EB")
                             : (card.dark ? "#301B1B20" : "#24FFFFFF")
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? "#2689FF" : (card.dark ? "#28FFFFFF" : "#20000000")
    }
    Image {
        id: appIcon
        x: 14; y: 12; width: 19; height: 19
        source: card.iconSource
        sourceSize: Qt.size(40,40)
        fillMode: Image.PreserveAspectFit; smooth: true
        layer.enabled: Common.IconStyle.effectMode !== 0
        layer.effect: Common.IconStyleEffect {}
    }
    Text {
        x: 40; y: 12; width: parent.width - x - 14; height: 20
        text: card.entry.title || card.entry.name || ""
        elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
        color: card.ink; font.family: card.fontFamily; font.pixelSize: 12
        font.weight: card.selected ? Font.DemiBold : Font.Normal
    }
    Item {
        id: content
        x: 13; y: 39; width: parent.width - 26; height: parent.height - y - 13
        ScreencopyView {
            id: capture
            readonly property real aspect: sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16/10
            anchors.centerIn: parent
            width: Math.min(content.width, content.height * aspect)
            height: width / aspect
            constraintSize: Qt.size(Math.ceil(content.width * 1.5), Math.ceil(content.height * 1.5))
            captureSource: card.captureWindow
            live: card.captureActive && card.inView && !card.quiet && !card.closing
            opacity: hasContent ? 1 : 0.01
            onCaptureSourceChanged: if (captureSource && card.captureActive && !card.quiet) firstFrame.restart()
            Timer {
                id: firstFrame; interval: 120
                onTriggered: if (capture.captureSource && card.captureActive && !card.quiet && !card.closing) capture.captureFrame()
            }
            onStopped: if (card.captureActive && !card.quiet && !card.closing) retryFrame.restart()
            Timer {
                id: retryFrame; interval: 800
                onTriggered: if (capture.captureSource && card.captureActive && !card.quiet && !card.closing) capture.captureFrame()
            }
        }
        Image {
            id: saved
            anchors.fill: parent
            visible: card.snapshotReady
            source: card.minimizedRecord && card.minimizedRecord.shot ? "file://" + card.minimizedRecord.shot : ""
            fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false
        }
        Image {
            anchors.centerIn: parent; width: 48; height: 48
            visible: !card.frameReady && !card.snapshotReady
            source: card.iconSource; sourceSize: Qt.size(96,96)
            fillMode: Image.PreserveAspectFit
            layer.enabled: Common.IconStyle.effectMode !== 0
            layer.effect: Common.IconStyleEffect {}
        }
    }
}
