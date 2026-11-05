pragma ComponentBehavior: Bound
import QtQuick
import "NotchDeviceState.js" as Devices

Item {
    id: compact
    required property var host
    readonly property var device: host.tools ? host.tools.feedbackDevice : null
    readonly property real factor: Math.min(host.uiScale,Math.max(.1,(height-2)/26))
    NotchDeviceArt { objectName:"notchDeviceCompactArt"; x:16*compact.host.uiScale; anchors.verticalCenter:parent.verticalCenter; width:26*compact.factor; height:width; compact:true; kind:Devices.kind(compact.device) }
    NotchDeviceBadge { objectName:"notchDeviceCompactBattery"; anchors.right:parent.right; anchors.rightMargin:16*compact.host.uiScale; anchors.verticalCenter:parent.verticalCenter; width:24*compact.factor; height:width; compact:true; percent:Devices.battery(compact.device); family:compact.host.family }
}
