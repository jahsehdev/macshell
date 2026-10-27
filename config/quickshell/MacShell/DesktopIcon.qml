pragma ComponentBehavior: Bound
import "Common" as Corners
import QtQuick
import Quickshell

Item {
    id: icon
    required property var file
    required property var desktop
    required property var controller
    property string fontFamily: "SF Pro Text"
    readonly property bool selected: desktop.selected.indexOf(file.name) >= 0
    property real dragX: 0
    property real dragY: 0
    width: desktop.iconWidth
    height: desktop.iconHeight
    z: pointer.pressed ? 5 : 1

    Item {
        x: icon.dragX; y: icon.dragY
        width: icon.width; height: icon.height
        Corners.ContinuousRectangle {
            x: 13; y: 0; width: parent.width - 26; height: 76; radius: 9
            color: "#35FFFFFF"
            border.color: "#75FFFFFF"
            border.width: 1
            visible: icon.selected
        }
        Image {
            id: image
            x: 20; y: 6; width: 64; height: 64
            source: icon.file.directory && Corners.IconStyle.folderSource("folder") !== "" ? Corners.IconStyle.folderSource("folder")
                : icon.file.image ? icon.file.url : (Quickshell.iconPath(icon.file.icon, true)
                || Quickshell.iconPath(icon.file.fallback, true) || Quickshell.iconPath("text-x-generic"))
            layer.enabled: !icon.file.image && !icon.file.directory && Corners.IconStyle.effectMode !== 0
            layer.effect: Corners.IconStyleEffect {}
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
            onStatusChanged: if (status === Image.Error) source = Quickshell.iconPath(icon.file.fallback || "text-x-generic", true)
        }
        Corners.ContinuousRectangle {
            x: 2; y: 79; width: parent.width - 4; height: label.implicitHeight + 4
            radius: 4
            color: icon.selected ? "#2673DB" : "transparent"
            Text {
                id: label
                x: 3; y: 2; width: parent.width - 6
                text: icon.file.name
                color: "white"
                font.family: icon.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideMiddle
                style: icon.selected ? Text.Normal : Text.Outline
                styleColor: "#70000000"
            }
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point start: Qt.point(0, 0)
        property bool moved: false
        onPressed: mouse => {
            icon.controller.forceActiveFocus();
            icon.controller.closeMenu();
            start = mapToItem(icon.controller, mouse.x, mouse.y);
            moved = false;
            if (mouse.button === Qt.RightButton) {
                if (!icon.selected) icon.desktop.select(icon.file.name, false);
                icon.controller.openFileMenu(start.x, start.y);
            } else {
                const additive = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) !== 0;
                if (!icon.selected || additive) icon.desktop.select(icon.file.name, additive);
            }
        }
        onPositionChanged: mouse => {
            if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
            var at = mapToItem(icon.controller, mouse.x, mouse.y);
            if (Math.abs(at.x - start.x) + Math.abs(at.y - start.y) > 6) moved = true;
            if (moved) {
                icon.dragX = at.x - start.x;
                icon.dragY = at.y - start.y;
            }
        }
        onReleased: mouse => {
            var x = icon.file.x + icon.dragX, y = icon.file.y + icon.dragY;
            icon.dragX = 0; icon.dragY = 0;
            if (moved) icon.desktop.move(icon.file.name, x, y);
        }
        onCanceled: { icon.dragX = 0; icon.dragY = 0; }
        onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton && !moved) icon.desktop.open(icon.file.name); }
    }
}
