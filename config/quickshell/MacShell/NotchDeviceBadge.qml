pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: badge
    property int percent: -1
    property bool compact: false
    property string family: "sans-serif"
    readonly property color tint: percent<0?"#A7AFBB":percent<=10?"#FF5A5A":percent<=20?"#FFAE32":"#30D85C"
    Accessible.name: percent<0?"Battery unavailable":"Battery "+percent+" percent"
    NotchRing { anchors.fill: parent; value: badge.percent<0?0:badge.percent/100; line: badge.compact?2:5; ink: badge.tint; track: Qt.rgba(badge.tint.r,badge.tint.g,badge.tint.b,.18) }
    Text {
        objectName: "notchDeviceBatteryPercent"
        anchors.centerIn: parent; visible: !badge.compact || badge.percent<0
        text: badge.percent<0?"—":String(badge.percent); color: badge.tint
        font.family: badge.family; font.pixelSize: badge.compact?11:26; font.weight: Font.Bold; font.features: ({"tnum":1})
    }
}
