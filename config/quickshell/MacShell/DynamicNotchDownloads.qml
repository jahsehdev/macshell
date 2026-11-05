pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Item {
    id:view
    objectName:"notchDownloads"
    required property var host
    readonly property var service:host.downloadsService
    readonly property var job:service?service.current:null
    readonly property bool done:!!job && (job.state==="complete" || job.state==="saved")
    readonly property bool complete:!!job && job.state==="complete"
    readonly property bool transferring:!!job && job.state==="active"
    readonly property real progress:job && job.progress>=0?job.progress:-1
    readonly property real contentInset:Geometry.inset(host.mode,true)
    readonly property real layoutScale:Math.min(host.uiScale,host.fullMetrics.width/520)
    readonly property color blue:"#159AFF"
    readonly property string compactLabel:!job?"":job.state==="complete"?"Done":job.state==="saved"?"Saved":job.state==="paused"?"Paused":job.state==="waiting"?"Waiting…":job.state==="interrupted"?"Interrupted":job.eta>=0?eta(job.eta):progress>=0?Math.round(progress*100)+"%":bytes(job.received)
    function bytes(value) {
        if(!(value>=0))return "";
        const units=["B","KB","MB","GB","TB"];let n=value,i=0;
        while(n>=1024 && i<4){n/=1024;i++;}
        return (i===0?Math.round(n):n.toFixed(n<10?2:1))+" "+units[i];
    }
    function eta(seconds) {const s=Math.max(1,Math.ceil(seconds));return s<60?s+" sec":s<3600?Math.ceil(s/60)+" min":Math.ceil(s/3600)+" hr";}
    readonly property string subtitle: {
        if(!job)return "";
        const folder=String(job.directory||"").split("/").pop();
        if(done)return bytes(job.received)+" · "+folder+(complete?"":" · File saved");
        if(job.state==="interrupted")return "Download interrupted";
        if(job.source==="folder")return bytes(job.received)+" · "+folder+(job.state==="waiting"?" · Waiting for changes":" · Download activity");
        let text=bytes(job.received)+(job.total>0?" / "+bytes(job.total):" received");
        if(job.state==="paused")return text+" · Paused";
        if(job.state==="waiting")return text+" · Waiting for data";
        if(job.speed>0)text+=" · "+bytes(job.speed)+"/s";
        return text;
    }
    component ProgressMark:Item {
        id:mark
        property bool compact:false
        readonly property real size:Math.min(width,height)
        NotchRing {
            anchors.fill:parent;line:mark.compact?2.3:3
            ink:view.done?"#F6F6FA":view.job && view.job.state==="interrupted"?"#FF6769":view.blue
            track:view.done?"#F6F6FA":"#243447"
            value:view.done?0:view.progress>=0?view.progress:0.24
            RotationAnimator on rotation {from:0;to:360;duration:1400;loops:Animation.Infinite;running:view.visible && view.transferring && view.progress<0 && !view.host.reducedMotion}
        }
        NotchIcon {anchors.centerIn:parent;width:mark.size*.53;height:width;kind:view.complete?"tick":view.done?"file":view.job && view.job.state==="paused"?"pause":view.job && view.job.state==="interrupted"?"close":"download";ink:view.done?"#F6F6FA":view.blue;strokeWidth:2.5}
    }
    Item {
        anchors.fill:parent;visible:!view.host.expanded
        ProgressMark {compact:true;x:29*view.host.uiScale;anchors.verticalCenter:parent.verticalCenter;width:23*view.host.uiScale;height:width}
        Text {objectName:"notchDownloadCompactStatus";anchors.right:parent.right;anchors.rightMargin:28*view.host.uiScale;anchors.verticalCenter:parent.verticalCenter;text:view.compactLabel;textFormat:Text.PlainText;color:view.done?"#F7F7F9":view.blue;font.family:view.host.family;font.pixelSize:15*view.host.uiScale;font.weight:Font.DemiBold;font.features:({"tnum":1})}
    }
    Item {
        id:expanded
        // Header + 16 px inset + 72 px tile + 16 px inset = 120 px.
        x:(view.width-view.host.fullMetrics.width)/2+view.contentInset*view.layoutScale;y:(Geometry.header+Geometry.padding)*view.layoutScale
        width:520-2*view.contentInset;height:80;scale:view.layoutScale;transformOrigin:Item.TopLeft
        visible:view.host.expanded;opacity:view.host.revealProgress
        Rectangle {objectName:"notchDownloadTile";x:0;y:0;width:64;height:72;radius:Geometry.contentRadius;color:"#12FFFFFF";border.width:1;border.color:"#18FFFFFF"
            NotchIcon {anchors.centerIn:parent;width:45;height:49;kind:"file";ink:"#F6F6FA";strokeWidth:1.6}
        }
        Text {objectName:"notchDownloadName";x:80;y:2;width:parent.width-x-70;text:view.job?view.job.name:"";textFormat:Text.PlainText;elide:Text.ElideMiddle;color:"#FFFFFF";font.family:view.host.family;font.pixelSize:21;font.weight:Font.Bold}
        Text {objectName:"notchDownloadDetail";x:80;y:32;width:parent.width-x-70;text:view.service&&view.service.error?view.service.error:view.subtitle;textFormat:Text.PlainText;elide:Text.ElideRight;color:view.service&&view.service.error?"#FF8183":"#AAAAB5";font.family:view.host.family;font.pixelSize:13}
        Rectangle {
            x:80;y:62;width:parent.width-x-73;height:4;radius:2;color:"#30313A";visible:!view.done
            Rectangle {height:parent.height;radius:2;color:view.blue;width:parent.width*Math.max(0,view.progress);visible:view.progress>=0}
        }
        Text {x:80;y:57;width:parent.width-x-72;visible:view.done;text:"Show in Files ↗";color:"#B9DFFF";font.family:view.host.family;font.pixelSize:12}
        // Explicit file actions; completed downloads never launch automatically.
        Button {objectName:"notchDownloadOpen";x:0;y:0;width:parent.width-72;height:54;background:null;enabled:view.done && (!view.service || !view.service.busy);Accessible.name:"Open downloaded file";HoverHandler{cursorShape:parent.enabled?Qt.PointingHandCursor:Qt.ArrowCursor}onClicked:view.service.act("open")}
        Button {objectName:"notchDownloadReveal";x:80;y:54;width:parent.width-x-72;height:24;background:null;enabled:view.done && (!view.service || !view.service.busy);Accessible.name:"Show download in Files";HoverHandler{cursorShape:parent.enabled?Qt.PointingHandCursor:Qt.ArrowCursor}onClicked:view.service.act("reveal")}
        ProgressMark {anchors.right:parent.right;y:10;width:54;height:54}
        NotchMediaButton {objectName:"notchDownloadDismiss";host:view.host;anchors.right:parent.right;anchors.rightMargin:0;y:-20;width:24;height:24;symbol:"close";iconSize:14;ink:"#92929D";Accessible.name:"Dismiss download activity";onClicked:{if(view.service)view.service.dismiss();view.host.close();}}
        Text {anchors.right:parent.right;y:68;visible:!!view.service && view.service.count>1;text:view.service?view.service.count+" downloads":"";color:"#AAAAB5";font.family:view.host.family;font.pixelSize:10}
    }
}
