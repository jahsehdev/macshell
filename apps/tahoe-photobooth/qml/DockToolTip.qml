import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

ToolTip {
    id: tip
    required property Item target
    required property bool dark
    readonly property Item windowContent: target.Window.window ? target.Window.window.contentItem : null
    readonly property point targetPosition: {
        target.x; target.y;
        if (!windowContent) return Qt.point(0, 0);
        windowContent.width; windowContent.height;
        return target.mapToItem(windowContent, 0, 0);
    }
    readonly property bool above: targetPosition.y >= height + 6
    readonly property real tailX: Math.max(25, Math.min(width - 25, target.width / 2 - x))
    parent: target
    popupType: Popup.Item
    x: Math.max(8 - targetPosition.x,
        Math.min((windowContent ? windowContent.width : 800) - width - 8 - targetPosition.x,
                 (target.width - width) / 2))
    y: above ? -height - 6 : target.height + 6
    width: Math.min(implicitWidth, (windowContent ? windowContent.width : 800) - 16)
    implicitWidth: Math.max(60, label.implicitWidth + 32)
    implicitHeight: 39
    margins: 8
    padding: 0
    leftPadding: 16
    rightPadding: 16
    topPadding: above ? 0 : 7
    bottomPadding: above ? 7 : 0
    delay: 600
    timeout: -1
    modal: false
    dim: false
    focus: false
    font.family: booth.fontFamily
    font.pixelSize: 13
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 90 } }

    // Same 32px capsule and 7px curved tail as the Dock, drawn as one outline
    // so the translucent fill and highlight have no seam at the pointer.
    function outline(inset) {
        const r = 16 - inset;
        const right = width - inset;
        const bottom = 32 - inset;
        const tail = 39 - inset;
        const t = tailX;
        return `M 16 ${inset} L ${width - 16} ${inset}
            A ${r} ${r} 0 0 1 ${right} 16 A ${r} ${r} 0 0 1 ${width - 16} ${bottom}
            L ${t + 9} ${bottom} C ${t + 4.95} ${bottom} ${t + 2} ${tail} ${t} ${tail}
            C ${t - 2} ${tail} ${t - 4.95} ${bottom} ${t - 9} ${bottom}
            L 16 ${bottom} A ${r} ${r} 0 0 1 ${inset} 16 A ${r} ${r} 0 0 1 16 ${inset} Z`;
    }
    background: Shape {
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.y: 19.5; yScale: tip.above ? 1 : -1 }
        ShapePath {
            strokeWidth: 1
            strokeColor: tip.dark ? "#99000000" : "#40000000"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: 39
                GradientStop { position: 0; color: tip.dark ? "#f255555a" : "#f2f7f7fa" }
                GradientStop { position: 1; color: tip.dark ? "#ee343439" : "#eee0e0e4" }
            }
            PathSvg { path: tip.outline(0.5) }
        }
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: tip.dark ? "#38ffffff" : "#a0ffffff"
            PathSvg { path: tip.outline(1.5) }
        }
    }
    contentItem: Text {
        id: label
        text: tip.text
        font: tip.font
        color: tip.dark ? "#f5f5f7" : "#1d1d1f"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
