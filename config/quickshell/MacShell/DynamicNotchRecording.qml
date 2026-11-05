pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Item {
    id: view
    required property var host
    readonly property var service:host.recordingService
    readonly property var result:host.recordingResult
    readonly property bool live:!!host.bar && host.bar.recording
    readonly property bool saving:host.recordingPending
    readonly property bool failed:!live && !saving && !result
    readonly property real layoutWidth:result?580:520
    readonly property real contentInset:Geometry.inset(host.mode,true)
    readonly property real layoutScale:Math.min(host.uiScale,host.fullMetrics.width/layoutWidth)
    readonly property string elapsed:live || saving ? host.bar.recTime() : format(result?result.duration:0)
    readonly property color red:"#FF5759"
    objectName:"notchRecording"
    function format(seconds) {
        const value=Math.max(0,Math.floor(seconds));
        return Math.floor(value/60)+":"+(value%60<10?"0":"")+value%60;
    }
    function dismiss(){if(service)service.dismiss();host.close();}
    function act(kind){if(service)service.act(kind);}
    function directoryLabel(path){return String(path||"").replace(/^\/home\/[^/]+(?=\/|$)/,"~");}

    Item {
        visible:!view.host.expanded
        anchors.fill:parent
        Rectangle {x:30*view.host.uiScale;anchors.verticalCenter:parent.verticalCenter;width:9*view.host.uiScale;height:width;radius:width/2;color:view.red}
        Text {
            objectName:"notchRecordingCompactTime"
            anchors.right:parent.right;anchors.rightMargin:28*view.host.uiScale;anchors.verticalCenter:parent.verticalCenter
            text:view.saving?"Saving…":view.elapsed;color:view.red
            font.family:view.host.family;font.pixelSize:15*view.host.uiScale;font.weight:Font.DemiBold;font.features:({"tnum":1})
        }
    }
    Item {
        id:expanded
        visible:view.host.expanded
        x:(view.width-view.host.fullMetrics.width)/2+view.contentInset*view.layoutScale
        y:(Geometry.header+Geometry.padding-6*(1-view.host.revealProgress))*view.layoutScale
        width:view.layoutWidth-2*view.contentInset;height:view.result?144:view.failed?112:72
        scale:view.layoutScale;transformOrigin:Item.TopLeft
        opacity:view.host.revealProgress

        Item {
            visible:!view.result
            anchors.fill:parent
            Row {
                x:0;y:view.failed?35:7;spacing:10
                Rectangle {
                    id:liveDot
                    width:11;height:11;radius:width/2;color:view.red;anchors.verticalCenter:parent.verticalCenter
                    SequentialAnimation on opacity {
                        running:view.visible && view.live && view.host.expanded && !view.host.reducedMotion;loops:Animation.Infinite
                        NumberAnimation {to:0.45;duration:800;easing.type:Easing.InOutSine}
                        NumberAnimation {to:1;duration:800;easing.type:Easing.InOutSine}
                        onRunningChanged:if(!running)liveDot.opacity=1
                    }
                }
                Text {objectName:"notchRecordingElapsed";text:view.live?view.elapsed:view.saving?"Saving…":"Recording failed";color:view.red;font.family:view.host.family;font.pixelSize:22;font.weight:Font.DemiBold;font.features:({"tnum":1})}
            }
            Text {x:0;y:view.failed?69:41;width:parent.width-90;text:view.failed?"The video could not be saved":view.saving?"Finishing your video":"Screen Recording";color:"#FAFAFC";font.family:view.host.family;font.pixelSize:20;font.weight:Font.Bold;elide:Text.ElideRight}
            Text {x:0;y:99;width:parent.width-24;visible:view.failed;text:view.service?view.service.error:"";color:"#BEBEC6";font.family:view.host.family;font.pixelSize:11;elide:Text.ElideRight}
            Button {
                id:stop;objectName:"notchRecordingStop"
                anchors.right:parent.right;y:2;width:68;height:68
                visible:!view.failed;enabled:view.live
                Accessible.name:view.saving?"Saving recording":"Stop recording"
                background:Rectangle {color:stop.down?"#22FFFFFF":stop.hovered?"#10FFFFFF":"transparent";radius:width/2;border.width:3;border.color:stop.enabled?"#F5F5F7":"#5C5C65"}
                contentItem:Item {Rectangle {anchors.centerIn:parent;width:25;height:25;radius:6;color:view.red}}
                HoverHandler {cursorShape:stop.enabled?Qt.PointingHandCursor:Qt.ArrowCursor}
                NotchToolTip {control:stop;text:stop.Accessible.name}
                onClicked:if(view.host.bar.recording)view.host.bar.toggleRecording()
            }
            NotchMediaButton {objectName:"notchRecordingErrorClose";host:view.host;visible:view.failed;anchors.right:parent.right;y:0;symbol:"close";Accessible.name:"Dismiss recording error";onClicked:view.dismiss()}
        }

        Item {
            visible:!!view.result
            anchors.fill:parent
            NotchMediaArt {objectName:"notchRecordingThumbnail";x:0;y:0;width:72;height:72;source:view.result?view.result.thumbnail:""}
            Button {
                x:0;y:0;width:72;height:72;enabled:!!view.result && (!view.service || !view.service.busy)
                background:null
                contentItem:Item {
                    Rectangle {anchors.centerIn:parent;width:31;height:31;radius:width/2;color:"#EFFFFFFF"}
                    NotchIcon {anchors.centerIn:parent;width:17;height:17;kind:"play";ink:"#303039"}
                }
                Accessible.name:"Watch recording";HoverHandler {cursorShape:Qt.PointingHandCursor}
                onClicked:view.act("watch")
            }
            Column {
                x:88;y:0;width:parent.width-x-34;spacing:4
                Text {objectName:"notchRecordingDuration";text:view.elapsed;color:view.red;font.family:view.host.family;font.pixelSize:16;font.weight:Font.DemiBold;font.features:({"tnum":1})}
                Text {objectName:"notchRecordingFilename";width:parent.width;text:view.result?view.result.name:"";color:"#FFFFFF";font.family:view.host.family;font.pixelSize:20;font.weight:Font.Bold;elide:Text.ElideMiddle}
                Text {objectName:"notchRecordingDirectory";width:parent.width;text:view.directoryLabel(view.result?view.result.directory:"");color:"#A7A7B0";font.family:view.host.family;font.pixelSize:14;elide:Text.ElideMiddle}
            }
            NotchMediaButton {objectName:"notchRecordingDismiss";host:view.host;anchors.right:parent.right;y:25;symbol:"close";iconSize:20;ink:"#9E9EA7";Accessible.name:"Dismiss recording result";onClicked:view.dismiss()}
            Row {
                x:0;y:96;spacing:10
                component ResultButton:Button {
                    id:button
                    property string symbol:""
                    property color ink:"#F5F5F7"
                    implicitHeight:40;implicitWidth:text?Math.max(94,words.implicitWidth+32):42
                    enabled:!!view.result && (!view.service || !view.service.busy)
                    background:Rectangle {radius:Geometry.contentRadius;color:button.down?"#40FFFFFF":button.hovered?"#30FFFFFF":"#20FFFFFF"}
                    contentItem:Item {
                        Text {id:words;anchors.centerIn:parent;visible:button.text!=="";text:button.text;color:button.ink;font.family:view.host.family;font.pixelSize:14;font.weight:Font.DemiBold}
                        NotchIcon {anchors.centerIn:parent;visible:button.symbol!=="";kind:button.symbol;width:19;height:19;ink:button.ink;strokeWidth:2.4}
                    }
                    HoverHandler {cursorShape:button.enabled?Qt.PointingHandCursor:Qt.ArrowCursor}
                    NotchToolTip {control:button;text:button.Accessible.name}
                }
                ResultButton {objectName:"notchRecordingWatch";text:"Watch";Accessible.name:"Watch recording";onClicked:view.act("watch")}
                ResultButton {objectName:"notchRecordingReveal";text:"Show in Files";Accessible.name:"Show recording in file manager";onClicked:view.act("reveal")}
                ResultButton {objectName:"notchRecordingCopy";symbol:"copy";Accessible.name:"Copy recording file";onClicked:view.act("copy")}
                ResultButton {objectName:"notchRecordingTrash";symbol:"trash";ink:view.red;Accessible.name:"Move recording to Trash";onClicked:view.act("trash")}
            }
            Text {x:0;y:82;width:parent.width;text:view.service?(view.service.error||view.service.message):"";color:view.service&&view.service.error?view.red:"#B7E6C9";font.family:view.host.family;font.pixelSize:11;elide:Text.ElideRight}
        }
    }
}
