pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Item {
    id: page
    required property var host
    required property var tools
    readonly property bool interacting: tools.dialogOpen
    function sizeText(item) {
        if (item.folder) return "Folder";
        if (item.size >= 1048576) return (item.size/1048576).toFixed(1) + " MB";
        if (item.size >= 1024) return (item.size/1024).toFixed(0) + " KB";
        return item.size + " B";
    }
    Item {
        anchors.fill: parent
        visible: !page.tools.state.shelf.length || page.host.shelfDragging
        Canvas {
            anchors.fill: parent
            property bool dropping: page.host.shelfDragging
            onDroppingChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const c=getContext("2d"); c.reset(); c.lineWidth=1.5; c.strokeStyle=dropping ? "#FFC86C" : "#70818D9F";
                c.setLineDash([4,4]); c.fillStyle=dropping ? "#183C2B16" : "#101C2940";
                c.beginPath(); c.roundedRect(1,1,width-2,height-2,Geometry.contentRadius,Geometry.contentRadius); c.fill(); c.stroke();
            }
        }
        Column {
            anchors.centerIn: parent; spacing: 9
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.host.shelfDragging ? "Release to add to Shelf" : page.tools.shelfBusy ? "Adding shortcuts…" : "Drop files or folders here"
                color: "#EFEFF5"; font.family: page.host.family; font.pixelSize: 15; font.weight: Font.Medium
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                visible: !page.host.shelfDragging
                NotchToolButton { text: "Add files"; symbol: "plus"; family:page.host.family; onClicked:page.tools.pickFiles() }
                NotchToolButton { text: "Add folder"; symbol: "toolFolder"; family:page.host.family; onClicked:page.tools.pickFolder() }
            }
            Text { anchors.horizontalCenter:parent.horizontalCenter; text:"Shortcuts only · your files stay in place"; visible:!page.host.shelfDragging; color:"#AEB5C2"; font.family:page.host.family; font.pixelSize:12 }
        }
    }
    Item {
        anchors.fill: parent; visible: page.tools.state.shelf.length > 0 && !page.host.shelfDragging
        Row { spacing: 6
            NotchToolButton { text:"Files"; symbol:"plus"; implicitHeight:32; family:page.host.family; onClicked:page.tools.pickFiles() }
            NotchToolButton { symbol:"toolFolder"; implicitHeight:32; family:page.host.family; Accessible.name:"Add a folder"; onClicked:page.tools.pickFolder() }
        }
        NotchToolButton { anchors.right:parent.right; text:"Clear"; implicitHeight:32; family:page.host.family; Accessible.name:"Clear Shelf shortcuts"; onClicked:page.tools.clearShelf() }
        ListView {
            objectName: "notchShelfList"
            y: 40; width: parent.width; height: parent.height-y
            model: page.tools.state.shelf
            orientation: ListView.Horizontal; spacing: 10; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.horizontal: ScrollBar { policy:ScrollBar.AsNeeded }
            delegate: Item {
                id: entry
                required property var modelData
                width: 108; height: 108
                HoverHandler { id:entryHover }
                Rectangle { anchors.fill:parent; radius:Geometry.controlRadius; color:entryHover.hovered ? "#0CFFFFFF" : "transparent" }
                NotchMediaArt {
                    anchors.horizontalCenter:parent.horizontalCenter; y:0; width:56; height:56; radius:Geometry.controlRadius
                    color:entry.modelData.image?"#202735":"transparent"
                    source:entry.modelData.image?entry.modelData.url:"";imageFillMode:Image.PreserveAspectFit
                    fallbackKind:entry.modelData.folder?"toolFolder":"file";fallbackSize:40;fallbackStrokeWidth:2.6
                    fallbackInk:entry.modelData.folder?"#FFCA43":"#B9D7F2"
                }
                Text { y:64; width:parent.width-4; anchors.horizontalCenter:parent.horizontalCenter; text:entry.modelData.name; textFormat:Text.PlainText; elide:Text.ElideMiddle; horizontalAlignment:Text.AlignHCenter; color:"#F6F6FA"; font.family:page.host.family; font.pixelSize:15; font.weight:Font.Medium }
                Text { y:86; width:parent.width; text:page.sizeText(entry.modelData); horizontalAlignment:Text.AlignHCenter; color:"#AEB5C2"; font.family:page.host.family; font.pixelSize:12 }
                MouseArea {
                    id:fileMouse; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                    Accessible.role:Accessible.Button; Accessible.name:"Open " + entry.modelData.name
                    onClicked:page.tools.openShelf(entry.modelData.url)
                }
                NotchToolTip {
                    control: entry; wanted: entryHover.hovered
                    text: decodeURIComponent(entry.modelData.url)
                }
                NotchToolButton {
                    anchors.right:parent.right; y:0; implicitWidth:24; implicitHeight:24;iconSize:16; symbol:"close"; round:true; fill:"#802A2C35"
                    visible:entryHover.hovered || hovered || activeFocus
                    Accessible.name:"Remove shortcut to " + entry.modelData.name
                    onClicked:page.tools.removeShelf(entry.modelData.url)
                }
            }
        }
    }
}
