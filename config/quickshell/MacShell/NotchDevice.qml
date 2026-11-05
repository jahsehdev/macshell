pragma ComponentBehavior: Bound
import QtQuick
import "NotchDeviceState.js" as Devices

Item {
    id: page
    required property var host
    required property var tools
    readonly property bool bluetooth: host.activity === "bluetooth"
    readonly property var device: bluetooth ? tools.feedbackDevice : null
    readonly property bool batteryKnown: bluetooth ? Devices.battery(device)>=0 : !!host.bar && host.bar.hasBattery
    readonly property real percent: batteryKnown ? Math.max(0,Math.min(100,bluetooth ? Number(device.bat) : host.bar.batPct)) : 0
    readonly property color tint: bluetooth ? "#5CCCFB" : "#2CDD7F"
    readonly property string symbol: bluetooth ? (device ? (device.icon || Devices.kind(device)) : "bluetooth") : "charging"
    readonly property bool lowBattery: bluetooth && tools.deviceEventReason==="low" && batteryKnown && percent<=20
    readonly property bool interacting: false
    Item {
        anchors.fill: parent; visible: page.bluetooth
        NotchDeviceArt { objectName:"notchDeviceArt"; width:72; height:72; kind:Devices.kind(page.device) }
        Text { objectName:"notchDeviceStatus"; x:92; y:6; width:parent.width-x-84; text:page.lowBattery?"Battery low":"Connected"; color:page.lowBattery?badge.tint:"#BDC3CC"; font.family:page.host.family; font.pixelSize:17; font.weight:Font.Medium; elide:Text.ElideRight }
        Text { objectName:"notchDeviceName"; x:92; y:31; width:parent.width-x-84; text:page.device?page.device.name:"Bluetooth device"; textFormat:Text.PlainText; color:"#F8FAFD"; font.family:page.host.family; font.pixelSize:23; font.weight:Font.Bold; elide:Text.ElideRight }
        Text { x:92; y:59; width:parent.width-x-84; visible:!page.batteryKnown; text:"Battery unavailable"; color:"#A7AFBB"; font.family:page.host.family; font.pixelSize:12; elide:Text.ElideRight }
        NotchDeviceBadge { id:badge; objectName:"notchDeviceBattery"; anchors.right:parent.right; y:4; width:64; height:64; percent:Devices.battery(page.device); family:page.host.family }
    }
    Item {
        anchors.fill: parent; visible: !page.bluetooth
        NotchRing {
            x:0; y:16; width:42; height:42; line:5; ink:page.tint; track:"#26343E"
            value:page.batteryKnown ? page.percent/100 : 0
            NotchIcon { anchors.centerIn:parent; width:21; height:21; kind:page.bluetooth ? "bluetooth" : "charging" }
        }
        Column {
            x:57; y:14; width:parent.width-x-96; spacing:6
            Text { width:parent.width; text:page.bluetooth ? (page.device ? page.device.name : "Bluetooth") : page.host.bar && page.host.bar.hasBattery ? (page.host.bar.charging ? "Charging" : "Battery") : "Power"; textFormat:Text.PlainText; color:"white"; font.family:page.host.family; font.pixelSize:18; font.weight:Font.Bold; elide:Text.ElideRight }
            Text { width:parent.width; text:page.bluetooth ? (page.device ? "Connected"+(page.batteryKnown ? " · "+page.percent+"%" : " · Battery unavailable") : page.host.bar && page.host.bar.btOn ? "No connected devices" : "Bluetooth is off") : !page.host.bar || !page.host.bar.hasBattery ? "No battery detected" : page.host.bar.charging ? "Charger connected" : "Running on battery"; color:"#9299A5"; font.family:page.host.family; font.pixelSize:12; elide:Text.ElideRight }
        }
        Item {
            anchors.right:parent.right; y:12; width:77; height:51
            NotchIcon { visible:page.bluetooth; anchors.centerIn:parent; width:34; height:34; kind:page.symbol; ink:page.tint }
            Text { visible:!page.bluetooth; anchors.centerIn:parent; text:page.batteryKnown ? page.percent+"%" : "—"; color:"#F5F7FA"; font.family:page.host.family; font.pixelSize:29; font.weight:Font.Medium }
        }
    }
}
