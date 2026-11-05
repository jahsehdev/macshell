pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property rect region
    property string statusText: "REC 0:00"
    property string fontFamily: "SF Pro Text"
    visible: region.width > 0 && region.height > 0
    clip: true

    // Place the frame just outside the crop; clamp at display edges so even
    // a selection touching an edge keeps a visible boundary.
    Rectangle {
        id: frame
        objectName: "recordingAreaFrame"
        x: Math.max(0, root.region.x - 3)
        y: Math.max(0, root.region.y - 3)
        width: Math.max(0, Math.min(root.width, root.region.x + root.region.width + 3) - x)
        height: Math.max(0, Math.min(root.height, root.region.y + root.region.height + 3) - y)
        radius: 3
        color: "transparent"
        border.width: 1
        border.color: "#cc000000"
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.width: 2
            border.color: "#ff453a"
        }
    }

    Rectangle {
        id: badge
        objectName: "recordingAreaBadge"
        x: Math.max(8, Math.min(root.width - width - 8, root.region.x))
        y: {
            if (root.region.y >= height + 10) return root.region.y - height - 7;
            const below = root.region.y + root.region.height + 7;
            if (below + height <= root.height - 8) return below;
            return Math.max(8, Math.min(root.height - height - 8, root.region.y + 8));
        }
        width: Math.min(root.width - 16, label.implicitWidth + 34)
        height: 28
        radius: 14
        color: "#ed202024"
        border.width: 1
        border.color: "#66ffffff"
        Rectangle {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 3.5; color: "#ff453a"
        }
        Text {
            id: label
            x: 23; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 31
            text: root.statusText + "  \u00b7  " + Math.round(root.region.width) + " \u00d7 " + Math.round(root.region.height)
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }
}
