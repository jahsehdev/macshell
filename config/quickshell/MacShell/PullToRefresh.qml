pragma ComponentBehavior: Bound
import QtQuick
import "Common" as Common
Item {
    id:root
    required property Flickable target
    property bool busy:false
    property real threshold:58
    readonly property real pull:Math.max(0,target.originY-target.contentY)
    signal refreshRequested()
    width:160;height:36
    opacity:busy ? 1 : Math.min(1,pull/threshold)
    visible:opacity>0.01
    y:Math.min(20,pull/3)
    Behavior on opacity {NumberAnimation {duration:Common.DesktopPreferences.anim(90)}}
    Connections {
        target:root.target
        function onDraggingChanged(){if(!root.target.dragging && root.pull>=root.threshold && !root.busy)root.refreshRequested();}
    }
    Rectangle {anchors.fill:parent;radius:18;color:Common.IconStyle.dark ? "#e83a3a44" : "#f5ffffff";border.width:Common.DesktopPreferences.showBorders ? 1.5 : 0.5;border.color:"#888890"
        Text{anchors.centerIn:parent;text:root.busy ? "Refreshing…" : root.pull>=root.threshold ? "Release to refresh" : "Pull to refresh";font.pixelSize:12;color:Common.IconStyle.dark ? "white" : "#27272d"}
    }
}
