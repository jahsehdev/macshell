pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "NotchGeometry.js" as Geometry
import "NotchToolStyle.js" as ToolStyle

Item {
    id:nav
    required property var host
    readonly property real layoutScale:Math.min(host.uiScale,host.fullMetrics.width/(host.dashboardPage && (host.activity==="bluetooth" || host.activity==="charging") ? 440 : host.activity==="music" ? (host.screenWidth<620*host.uiScale?440:host.mediaSideOpen?740:640) : host.lyricsOpen ? 740 : 560))
    readonly property var primaryPages:["music","pomodoro","stats"].filter(id=>host.navigationPages.indexOf(id)>=0)
    readonly property var otherPages:host.navigationPages.filter(id=>primaryPages.indexOf(id)<0)
    readonly property var railPages:primaryPages.concat(otherPages.length?["more"]:[])
    opacity:host.revealProgress
    visible:host.expanded && !host.deviceFeedbackActive && opacity>0.001 && host.navigationPages.length>1
    function name(page) { return ({music:"Music",pomodoro:"Pomodoro",water:"Water reminder",shelf:"Shelf",todo:"Todo list",calendar:"Calendar",weather:"Weather",stats:"System Stats",bluetooth:"Bluetooth",charging:"Charging",timer:"Timer",recording:"Recording"})[page] || page; }
    Row {
        id:tabRow
        visible:nav.host.activity!=="music"
        scale:nav.layoutScale; transformOrigin:Item.Bottom
        anchors.horizontalCenter:parent.horizontalCenter
        anchors.bottom:parent.bottom; anchors.bottomMargin:2*nav.layoutScale
        spacing:0; height:20
        Repeater {
            model:nav.host.navigationPages
            Item {
                id:tab
                required property string modelData
                readonly property bool active:nav.host.requestedActivity===modelData
                width:indicator.width+6; height:20
                Rectangle { id:indicator; anchors.centerIn:parent; width:tab.active ? 18 : 4; height:4; radius:2; color:tab.active ? "#F8F8FC" : "#71717B"
                    Behavior on width { enabled:!nav.host.reducedMotion; NumberAnimation { duration:180; easing.type:Easing.OutCubic } }
                }
                MouseArea {
                    objectName: "notchTab" + tab.modelData
                    anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                    Accessible.role:Accessible.PageTab; Accessible.name:nav.name(tab.modelData); Accessible.selected:tab.active
                    onClicked:nav.host.selectPage(tab.modelData)
                }
            }
        }
    }
    Item {
        id:mediaRail
        objectName:"notchMediaRail"
        visible:nav.host.activity==="music"
        readonly property var geometry:({width:36,cell:28,height:nav.railPages.length*28+8,radius:18,edge:18})
        readonly property real innerPadding:Geometry.railPadding
        readonly property real rightInset:Geometry.wing(nav.host.mode,1,true)+geometry.edge
        readonly property real cellHeight:geometry.cell
        x:nav.width-(width+rightInset)*nav.layoutScale
        y:(nav.height-height*nav.layoutScale)/2
        width:geometry.width;height:geometry.height
        scale:nav.layoutScale;transformOrigin:Item.TopLeft
        Rectangle {objectName:"notchMediaRailSurface";anchors.fill:parent;radius:mediaRail.geometry.radius;color:"#262729"}
        Column {
            anchors.fill:parent;anchors.topMargin:mediaRail.innerPadding;anchors.bottomMargin:mediaRail.innerPadding;spacing:0
            Repeater {
                model:nav.railPages
                NotchMediaButton {
                    id:mediaTab
                    required property string modelData
                    readonly property bool selected:nav.host.requestedActivity===modelData
                    host:nav.host;objectName:"notchMediaTab"+modelData
                    implicitWidth:mediaRail.width;implicitHeight:mediaRail.cellHeight
                    iconSize:20;strokeWidth:2.6
                    padding:4
                    symbol:modelData==="more"?"more":ToolStyle.icon(modelData)
                    ink:selected?"#FFFFFF":"#E5E5E7"
                    background:Item {
                        Rectangle {
                            anchors.centerIn:parent
                            objectName:"notchMediaSelection"
                            width:parent.width-2*mediaRail.innerPadding;height:parent.height;radius:Geometry.innerRadius(mediaRail.geometry.radius,mediaRail.innerPadding,width,height)
                            color:mediaTab.down?"#626365":mediaTab.selected?"#4D4E50":mediaTab.hovered?"#38393B":"transparent"
                            Behavior on color {ColorAnimation {duration:nav.host.reducedMotion?0:140}}
                        }
                    }
                    tooltipEnabled:!overflow.visible
                    Accessible.name:modelData==="more"?"More notch pages":nav.name(modelData);Accessible.selected:selected
                    onClicked:if(modelData==="more"){overflow.control=mediaTab;overflow.open();}else nav.host.selectPage(modelData)
                }
            }
        }
    }
    NotchSettingsPopup {
        id:overflow;objectName:"notchMorePages";host:nav.host;control:mediaRail
        width:Math.min(264,parent?parent.width-16:264)
        height:Math.min(options.implicitHeight+2*contentPadding+tailHeight,Math.max(140,screenBottomLimit-desiredY-8))
        contentItem:Flickable {
            contentHeight:options.implicitHeight+2*overflow.contentPadding+overflow.tailHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            transform:Scale {origin.x:overflow.pointerX;origin.y:0;xScale:overflow.elasticScaleX;yScale:overflow.elasticScaleY}
            ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
            Column {
                id:options;x:overflow.contentPadding;y:overflow.contentPadding+overflow.tailHeight;width:parent.width-2*overflow.contentPadding;spacing:8
                Text {text:"More pages";color:overflow.secondary;font.family:nav.host.family;font.pixelSize:12;font.weight:Font.Medium}
                Column {
                    width:parent.width;spacing:2
                    Repeater {
                        model:nav.otherPages
                        Button {
                            id:option
                            required property string modelData
                            objectName:"notchMorePage"+modelData;width:parent.width;height:40;padding:0
                            Accessible.name:nav.name(modelData)
                            background:Rectangle {radius:10;color:option.down?(overflow.dark?"#30FFFFFF":"#18000000"):option.hovered||option.visualFocus?(overflow.dark?"#16FFFFFF":"#10000000"):"transparent"}
                            contentItem:Item {
                                NotchIcon {x:6;anchors.verticalCenter:parent.verticalCenter;width:20;height:20;kind:ToolStyle.icon(option.modelData);ink:overflow.foreground;strokeWidth:2.6}
                                Text {x:38;anchors.verticalCenter:parent.verticalCenter;text:nav.name(option.modelData);color:overflow.foreground;font.family:nav.host.family;font.pixelSize:14;font.weight:Font.Medium}
                            }
                            HoverHandler {cursorShape:Qt.PointingHandCursor}
                            onClicked:{overflow.close();nav.host.selectPage(modelData);}
                        }
                    }
                }
            }
        }
    }
    NotchToolButton {
        iconSize:16;
        visible:nav.host.activity!=="music" && nav.host.activity!=="pomodoro" && nav.host.activity!=="calendar" && nav.host.activity!=="weather" && nav.host.activity!=="stats"
        opacity:nav.host.pageOpacity
        x:(Geometry.wing(nav.host.mode,1,nav.host.wideShape)+Geometry.padding/2)*nav.layoutScale
        y:parent.height/2-7*nav.layoutScale
        scale:nav.layoutScale; transformOrigin:Item.TopLeft
        implicitWidth:26; implicitHeight:26; round:true
        symbol:"chevronLeft"; fill:"#22FFFFFF"; family:nav.host.family; Accessible.name:"Previous notch page"
        onClicked:nav.host.stepPage(-1)
    }
    NotchToolButton {
        iconSize:16;
        visible:nav.host.activity!=="music" && nav.host.activity!=="pomodoro" && nav.host.activity!=="calendar" && nav.host.activity!=="weather" && nav.host.activity!=="stats"
        opacity:nav.host.pageOpacity
        x:nav.width-(Geometry.wing(nav.host.mode,1,nav.host.wideShape)+Geometry.padding/2+26)*nav.layoutScale
        y:parent.height/2-7*nav.layoutScale
        scale:nav.layoutScale; transformOrigin:Item.TopLeft
        implicitWidth:26; implicitHeight:26; round:true
        symbol:"chevron"; fill:"#22FFFFFF"; family:nav.host.family; Accessible.name:"Next notch page"
        onClicked:nav.host.stepPage(1)
    }
}
