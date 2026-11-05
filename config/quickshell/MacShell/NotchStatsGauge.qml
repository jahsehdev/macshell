pragma ComponentBehavior: Bound
import QtQuick

Item {
    id:gauge
    required property var reading
    property bool network:false
    property bool reducedMotion:false
    readonly property real stroke:width>=70?6:width>=56?5:4
    NotchRing {
        anchors.fill:parent;line:gauge.network?gauge.stroke-1:gauge.stroke
        value:gauge.reading.ratio;ink:gauge.reading.ink
        track:gauge.reading.available?Qt.rgba(ink.r,ink.g,ink.b,0.28):"#38BEC4CF"
        Behavior on value {enabled:!gauge.reducedMotion;NumberAnimation {duration:220;easing.type:Easing.OutCubic}}
    }
    NotchRing {
        anchors.fill:parent;anchors.margins:gauge.stroke+2;visible:gauge.network
        line:gauge.stroke-1.5;value:gauge.reading.secondary;ink:"#F2AAB9";track:"#28F2AAB9"
        Behavior on value {enabled:!gauge.reducedMotion;NumberAnimation {duration:220;easing.type:Easing.OutCubic}}
    }
    NotchIcon {
        anchors.centerIn:parent;width:gauge.width>=56?26:gauge.network?14:18;height:width
        kind:gauge.reading.symbol;ink:gauge.reading.available?gauge.reading.ink:"#ADB4C1";strokeWidth:2.4
    }
}
