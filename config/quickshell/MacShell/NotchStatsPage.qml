pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "NotchStatsState.js" as Data

Item {
    id:page
    required property var host
    required property var tools
    readonly property var stats:tools.stats
    readonly property var prefs:tools.state.stats
    readonly property var primary:reading(prefs.primary)
    readonly property var miniIds:Data.ids.filter(id=>id!==prefs.primary)
    readonly property bool active:visible && host.available && host.expanded && host.activity==="stats"
    readonly property bool interacting:chooser.visible
    property var registered:null
    property string choiceSlot:"primary"
    property Item choiceControl:null
    function syncDemand(){
        const target=active?stats:null;
        if(target===registered)return;
        if(registered)registered.clients=Math.max(0,registered.clients-1);
        registered=target;if(registered)registered.clients++;
    }
    function reading(id){
        const r=Data.metric(stats.fresh?stats.snapshot:null,stats.history,id);
        if(!stats.fresh)r.caption=stats.error?"Reconnecting…":"Collecting data…";
        return r;
    }
    function choose(slot,control){choiceSlot=slot;choiceControl=control;chooser.open();}
    onActiveChanged:syncDemand()
    Component.onCompleted:syncDemand()
    Component.onDestruction:if(registered)registered.clients=Math.max(0,registered.clients-1)

    Text {
        objectName:"notchStatsTitle"
        y:5;text:"System Stats";color:"#F7F8FA"
        font.family:page.host.family;font.pixelSize:17;font.weight:Font.DemiBold
    }
    Rectangle {
        anchors.right:parent.right;y:0;width:184;height:32;radius:12;color:"#D522252B"
        Row {
            x:3;y:3;spacing:2
            Repeater {
                model:[{key:"overview",label:"Overview"},{key:"detail",label:"Compare"}]
                Button {
                    id:modeButton
                    required property var modelData
                    readonly property bool chosen:page.prefs.view===modelData.key
                    objectName:modelData.key==="overview"?"notchStatsOverview":"notchStatsDetail"
                    text:modelData.label
                    Accessible.name:modelData.key==="detail"?"Compare two statistics":text
                    onClicked:page.tools.setStatsView(modelData.key)
                    width:88;height:26;padding:0
                    Accessible.role:Accessible.RadioButton;Accessible.checked:chosen;Accessible.selected:chosen
                    background:Rectangle {radius:9;color:modeButton.down?"#626772":modeButton.chosen?"#4A505B":modeButton.hovered||modeButton.visualFocus?"#353A43":"transparent"}
                    contentItem:Text {text:modeButton.text;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;color:modeButton.chosen?"#FFFFFF":"#CBD0DA";font.family:page.host.family;font.pixelSize:13;font.weight:modeButton.chosen?Font.DemiBold:Font.Medium}
                    HoverHandler {cursorShape:Qt.PointingHandCursor}
                }
            }
        }
    }
    Item {
        anchors.fill:parent;visible:page.prefs.view==="overview"
        NotchStatsGauge {x:0;y:42;width:72;height:72;reading:page.primary;network:page.prefs.primary==="network";reducedMotion:page.host.reducedMotion}
        MetricHeading {id:overviewName;objectName:"notchStatsPrimaryChooser";x:86;y:35;metricId:page.prefs.primary;slot:"primary"}
        Reading {objectName:"notchStatsPrimaryValue";x:86;y:52;width:146;reading:page.primary}
        Text {x:86;y:110;width:146;text:page.primary.caption;textFormat:Text.PlainText;elide:Text.ElideRight;color:page.prefs.primary==="network"?"#F5B5C6":"#C5CAD5";font.family:page.host.family;font.pixelSize:13}
        Item {
            x:252;y:38;width:parent.width-x;height:20
            Text {visible:page.prefs.primary!=="network";text:"Last 60 seconds";color:"#C5CAD5";font.family:page.host.family;font.pixelSize:12}
            Row {
                visible:page.prefs.primary==="network";spacing:12
                Text {text:"↓ Download";color:Data.ink("network");font.family:page.host.family;font.pixelSize:12}
                Text {text:"↑ Upload";color:"#F5B5C6";font.family:page.host.family;font.pixelSize:12}
            }
        }
        NotchStatsGraph {objectName:"notchStatsOverviewGraph";x:252;y:64;width:parent.width-x;height:52;metricId:page.prefs.primary;history:page.stats.history;nowMs:page.stats.nowMs;fresh:page.stats.fresh;family:page.host.family}
        Row {
            x:0;y:134;width:parent.width;height:80
            Repeater {
                model:page.miniIds
                Button {
                    id:mini
                    required property string modelData
                    readonly property var reading:page.reading(modelData)
                    objectName:"notchStatsMini"+modelData
                    width:page.width/6;height:80;padding:0
                    Accessible.name:Data.name(modelData)+", "+reading.short;Accessible.description:reading.caption
                    background:Item {Rectangle {x:3;width:parent.width-6;height:parent.height;radius:10;color:mini.down?"#20FFFFFF":mini.hovered||mini.visualFocus?"#12FFFFFF":"transparent"}}
                    contentItem:Item {
                        Text {x:4;width:parent.width-8;height:22;horizontalAlignment:Text.AlignHCenter;text:mini.reading.short;color:mini.reading.available?"#FAFAFC":"#BDC3CE";font.family:page.host.family;font.pixelSize:18;minimumPixelSize:14;fontSizeMode:Text.Fit;font.weight:Font.DemiBold}
                        NotchStatsGauge {anchors.horizontalCenter:parent.horizontalCenter;y:24;width:36;height:36;reading:mini.reading;network:mini.modelData==="network";reducedMotion:page.host.reducedMotion}
                        Text {anchors.horizontalCenter:parent.horizontalCenter;y:63;text:mini.modelData==="temperature"?"Temp":Data.name(mini.modelData);color:"#C5CAD5";font.family:page.host.family;font.pixelSize:12;font.weight:Font.Medium}
                    }
                    HoverHandler {cursorShape:Qt.PointingHandCursor}
                    NotchToolTip {control:mini;text:Data.name(mini.modelData)+" · "+mini.reading.caption}
                    onClicked:page.tools.selectStatsMetric("primary",modelData)
                }
            }
        }
    }
    Item {
        anchors.fill:parent;visible:page.prefs.view==="detail"
        MetricCard {objectName:"notchStatsLeftCard";x:0;width:(parent.width-24)/2;height:parent.height;metricId:page.prefs.primary;slot:"primary"}
        MetricCard {objectName:"notchStatsRightCard";x:(parent.width+24)/2;width:(parent.width-24)/2;height:parent.height;metricId:page.prefs.secondary;slot:"secondary"}
    }

    component Reading:Item {
        id:readingRow
        required property var reading
        property real size:44
        readonly property bool network:reading.symbol==="statsNetwork"
        implicitWidth:prefix.width+digits.implicitWidth+units.implicitWidth+3;implicitHeight:54
        Text {id:prefix;anchors.baseline:digits.baseline;width:readingRow.network?18:0;text:readingRow.network?"↓":"";color:Data.ink("network");font.family:page.host.family;font.pixelSize:18;font.weight:Font.DemiBold}
        Text {id:digits;x:prefix.width;width:Math.max(0,Math.min(implicitWidth,readingRow.width-prefix.width-(units.visible?units.implicitWidth+3:0)));height:54;verticalAlignment:Text.AlignVCenter;text:readingRow.reading.value;color:readingRow.reading.available?"#FAFAFC":"#BEC4CF";font.family:page.host.family;font.pixelSize:readingRow.size;minimumPixelSize:26;fontSizeMode:Text.Fit;font.weight:Font.DemiBold;font.letterSpacing:-0.8}
        Text {id:units;x:digits.x+digits.width+3;anchors.baseline:digits.baseline;text:readingRow.reading.unit;visible:text!=="";color:"#CDD2DC";font.family:page.host.family;font.pixelSize:16;font.weight:Font.Medium}
    }
    component MetricHeading:Button {
        id:heading
        required property string metricId
        required property string slot
        implicitWidth:label.implicitWidth+20;implicitHeight:24;padding:0
        Accessible.name:"Choose "+(page.prefs.view==="overview"?"main":slot==="primary"?"left":"right")+" statistic"
        background:Rectangle {radius:6;color:heading.hovered||heading.visualFocus?"#18FFFFFF":"transparent"}
        contentItem:Item {
            Text {id:label;anchors.verticalCenter:parent.verticalCenter;text:Data.name(heading.metricId);color:Data.ink(heading.metricId);font.family:page.host.family;font.pixelSize:15;font.weight:Font.DemiBold}
            NotchIcon {anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:10;height:10;kind:"chevron";rotation:90;strokeWidth:2.4;ink:Data.ink(heading.metricId);opacity:0.85}
        }
        HoverHandler {cursorShape:Qt.PointingHandCursor}
        NotchToolTip {control:heading;text:Data.name(heading.metricId)+" · "+page.reading(heading.metricId).caption}
        onClicked:page.choose(slot,heading)
    }
    component MetricCard:Item {
        id:card
        required property string metricId
        required property string slot
        readonly property var reading:page.reading(metricId)
        MetricHeading {objectName:"notchStatsChoose"+card.slot;y:36;metricId:card.metricId;slot:card.slot}
        Reading {y:60;width:parent.width-76;reading:card.reading}
        NotchStatsGauge {anchors.right:parent.right;y:58;width:64;height:64;reading:card.reading;network:card.metricId==="network";reducedMotion:page.host.reducedMotion}
        Text {y:121;width:parent.width;text:card.reading.caption;textFormat:Text.PlainText;elide:Text.ElideRight;color:card.metricId==="network"?"#F5B5C6":"#C5CAD5";font.family:page.host.family;font.pixelSize:13}
        NotchStatsGraph {objectName:"notchStatsGraph"+card.slot;y:149;width:parent.width;height:44;metricId:card.metricId;history:page.stats.history;nowMs:page.stats.nowMs;fresh:page.stats.fresh;family:page.host.family}
        Text {y:199;text:"60s ago";color:"#BDC3CE";font.family:page.host.family;font.pixelSize:11}
        Text {anchors.right:parent.right;y:199;text:"Now";color:"#BDC3CE";font.family:page.host.family;font.pixelSize:11}
    }

    NotchSettingsPopup {
        id:chooser;objectName:"notchStatsChooser";host:page.host;control:page.choiceControl||overviewName
        width:Math.min(288,parent?parent.width-16:288)
        height:Math.min(options.implicitHeight+2*contentPadding+tailHeight,Math.max(140,screenBottomLimit-desiredY-8))
        contentItem:Flickable {
            contentHeight:options.implicitHeight+2*chooser.contentPadding+chooser.tailHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
            transform:Scale {origin.x:chooser.pointerX;origin.y:0;xScale:chooser.elasticScaleX;yScale:chooser.elasticScaleY}
            ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
            Column {
                id:options;x:chooser.contentPadding;y:chooser.contentPadding+chooser.tailHeight;width:parent.width-2*chooser.contentPadding;spacing:8
                Text {text:"Choose "+(page.prefs.view==="overview"?"main":page.choiceSlot==="primary"?"left":"right")+" statistic";color:chooser.secondary;font.family:page.host.family;font.pixelSize:12;font.weight:Font.Medium}
                Column {
                    width:parent.width;spacing:2
                    Repeater {
                        model:Data.ids
                        Button {
                            id:option
                            required property string modelData
                            readonly property bool chosen:page.prefs[page.choiceSlot]===modelData
                            objectName:"notchStatsOption"+modelData;width:parent.width;height:34;padding:0
                            Accessible.name:Data.name(modelData);Accessible.role:Accessible.RadioButton;Accessible.checked:chosen
                            background:Rectangle {radius:10;color:option.hovered||option.visualFocus?(chooser.dark?"#15FFFFFF":"#10000000"):"transparent"}
                            contentItem:Item {
                                NotchIcon {x:6;anchors.verticalCenter:parent.verticalCenter;width:18;height:18;kind:Data.icon(option.modelData);ink:Data.ink(option.modelData);strokeWidth:2.6}
                                Text {x:34;anchors.verticalCenter:parent.verticalCenter;text:Data.name(option.modelData);color:chooser.foreground;font.family:page.host.family;font.pixelSize:14}
                                NotchIcon {anchors.right:parent.right;anchors.rightMargin:6;anchors.verticalCenter:parent.verticalCenter;width:16;height:16;kind:"checkmark";ink:chooser.foreground;visible:option.chosen}
                            }
                            HoverHandler {cursorShape:Qt.PointingHandCursor}
                            onClicked:{page.tools.selectStatsMetric(page.choiceSlot,modelData);chooser.close();}
                        }
                    }
                }
            }
        }
    }
}
