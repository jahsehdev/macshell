pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import Quickshell

Item {
    id: pages
    required property var host
    required property var tools
    readonly property bool summary: host.activity === "bluetooth" || host.activity === "charging"
    readonly property bool calendarPage:host.activity==="calendar"
    readonly property bool weatherPage:host.activity==="weather"
    readonly property bool statsPage:host.activity==="stats"
    readonly property bool bluetoothPage:host.activity==="bluetooth"
    readonly property bool pomodoroPage:host.activity==="pomodoro"
    readonly property real layoutScale: Math.min(host.uiScale, host.fullMetrics.width / (calendarPage ? (host.calendarExpanded?760:560) : bluetoothPage ? 520 : summary ? 440 : pomodoroPage ? host.pomodoroWidth : 560))
    readonly property real inset:(Geometry.inset(host.mode,!summary || bluetoothPage)+(summary || pomodoroPage || calendarPage || weatherPage || statsPage?0:Geometry.navigationGutter))*layoutScale
    readonly property bool interacting: !!body.item && body.item.interacting
    readonly property string heading: ({pomodoro:"Pomodoro",water:"Water <font color='#52CBF7'>Reminder</font>",shelf:"Shelf",todo:"Todo <font color='#37D67D'>List</font>"})[host.activity] || ""
    SystemClock { id:wallClock; precision:SystemClock.Minutes }
    Timer {
        interval:1000; repeat:true
        running:pages.host.available && pages.host.expanded && !pages.summary && !!pages.host.player && pages.host.player.isPlaying && pages.host.player.positionSupported
        onTriggered:pages.host.player.positionChanged()
    }
    Item {
        id:layout
        x:(pages.width-pages.host.fullMetrics.width)/2+pages.inset
        y:((pages.statsPage ? 24 : pages.calendarPage || pages.weatherPage ? 32 : pages.bluetoothPage ? 48 : pages.summary ? 15 : pages.pomodoroPage ? (pages.host.focusDecisionOpen?12:32) : 16)-6*(1-pages.host.revealProgress))*pages.layoutScale
        width:(pages.host.fullMetrics.width-pages.inset*2)/pages.layoutScale
        height:pages.statsPage ? 216 : pages.weatherPage ? 208 : pages.calendarPage ? (pages.host.calendarExpanded?292:208) : pages.bluetoothPage ? 72 : pages.summary ? 74 : pages.pomodoroPage ? (pages.host.focusDecisionOpen?188:pages.host.pomodoroLayout==="active"?48:168) : 196
        scale:pages.layoutScale; transformOrigin:Item.TopLeft
        opacity:pages.host.revealProgress
        visible:opacity>0.001; enabled:pages.host.expanded
        Item {
            width:parent.width; height:32; visible:!pages.summary && !pages.pomodoroPage && !pages.calendarPage && !pages.weatherPage && !pages.statsPage
            Text { text:pages.heading; color:"white"; font.family:pages.host.family; font.pixelSize:17; font.weight:Font.Bold; textFormat:Text.RichText }
            Row {
                x:162; spacing:7; height:23
                NotchRing { anchors.verticalCenter:parent.verticalCenter; width:15; height:15; line:2.5; value:pages.host.player && pages.host.player.length>0 ? pages.host.player.position/pages.host.player.length : 0.12; track:"#163F2B" }
                Text { anchors.verticalCenter:parent.verticalCenter; text:Qt.formatDateTime(wallClock.date,"ddd d MMM yyyy"); color:"#EBEBF0"; font.family:pages.host.family; font.pixelSize:12 }
                Text { anchors.verticalCenter:parent.verticalCenter; text:Qt.formatDateTime(wallClock.date,"HH:mm"); color:"white"; font.family:pages.host.family; font.pixelSize:12; font.weight:Font.Bold }
            }
            Row {
                anchors.right:parent.right; y:3; spacing:2; height:18
                Repeater {
                    model:5
                    Rectangle {
                        id:wave
                        required property int index
                        width:2.2; height:pages.host.player && pages.host.player.isPlaying ? [10,15,18,13,8][index] : 4
                        anchors.verticalCenter:parent.verticalCenter; radius:1.1; color:"#EFEFF5"
                        SequentialAnimation on height {
                            running:pages.visible && pages.host.expanded && !pages.host.reducedMotion && !!pages.host.player && pages.host.player.isPlaying
                            loops:Animation.Infinite
                            NumberAnimation { to:5+wave.index; duration:240+wave.index*27; easing.type:Easing.InOutSine }
                            NumberAnimation { to:18-wave.index%3*4; duration:310+wave.index*31; easing.type:Easing.InOutSine }
                        }
                    }
                }
            }
        }
        Loader {
            id:body
            x:0
            y:pages.summary || pages.pomodoroPage || pages.calendarPage || pages.weatherPage || pages.statsPage ? 0 : 44
            width:parent.width-x*2; height:pages.statsPage ? 216 : pages.weatherPage ? 208 : pages.calendarPage ? (pages.host.calendarExpanded?292:208) : pages.bluetoothPage ? 72 : pages.summary ? 74 : pages.pomodoroPage || pages.calendarPage ? layout.height : 152
            sourceComponent:({pomodoro:pomodoro,water:water,shelf:shelf,todo:todo,calendar:calendar,weather:weather,stats:stats,bluetooth:device,charging:device})[pages.host.activity] || null
        }
        Component { id:pomodoro; NotchPomodoro { host:pages.host; tools:pages.tools } }
        Component { id:water; NotchWater { host:pages.host; tools:pages.tools } }
        Component { id:shelf; NotchShelf { host:pages.host; tools:pages.tools } }
        Component { id:todo; NotchTodo { host:pages.host; tools:pages.tools } }
        Component { id:stats; NotchStatsPage { host:pages.host; tools:pages.tools } }
        Component { id:weather; NotchWeather { host:pages.host } }
        Component { id:calendar; NotchCalendarPage { host:pages.host; tools:pages.tools } }
        Component { id:device; NotchDevice { host:pages.host; tools:pages.tools } }
    }
    Rectangle {
        x:45; width:parent.width-90; height:32; y:parent.height-49
        visible:!pages.summary && pages.tools.error!=="" && pages.host.expanded
        radius:Geometry.controlRadius; color:"#EF352327"; border.width:1; border.color:"#654437"
        Text { x:9; anchors.verticalCenter:parent.verticalCenter; width:parent.width-50; text:pages.tools.error; textFormat:Text.PlainText; elide:Text.ElideRight; color:"#FFD7C2"; font.family:pages.host.family; font.pixelSize:12 }
        NotchToolButton { anchors.right:parent.right; implicitWidth:32; implicitHeight:32;iconSize:16; fill:"transparent"; symbol:"close"; Accessible.name:"Dismiss message"; onClicked:pages.tools.error="" }
    }
}
