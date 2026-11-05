pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: art
    property string kind: "bluetooth"
    property bool compact: false
    readonly property bool illustrated: ["earbuds","headphones","keyboard","mouse","gamepad","speaker","phone"].indexOf(kind)>=0
    Image {
        id: picture; anchors.fill: parent
        source: art.illustrated ? Qt.resolvedUrl("assets/notch-devices/"+art.kind+(art.kind==="earbuds" && !art.compact?"-single":"")+".svg") : ""
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.ceil(width * 2); sourceSize.height: Math.ceil(height * 2)
        visible: status === Image.Ready
    }
    NotchIcon { anchors.centerIn: parent; width: parent.width*.72; height: width; kind: art.kind==="earbuds"?"headphones":art.kind; ink: "#EDF2F8"; strokeWidth: 2; visible: !picture.visible }
}
