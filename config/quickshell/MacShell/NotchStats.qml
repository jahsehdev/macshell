import QtQuick
import Quickshell
import Quickshell.Io
import "NotchStatsState.js" as Data

Scope {
    id:stats
    property bool enabled:false
    property bool ioEnabled:true
    property int clients:0
    property var snapshot:null
    property var history:[]
    property real nowMs:Date.now()
    property real receivedAt:0
    property string error:""
    property var commandOverride:[]
    readonly property bool wanted:enabled && ioEnabled && clients>0
    readonly property bool fresh:receivedAt>0 && Math.abs(nowMs-receivedAt)<3500
    readonly property bool running:reader.running
    readonly property string helper:decodeURIComponent(Qt.resolvedUrl("bin/notch_stats.py").toString().replace(/^file:\/\//,""))
    function ingest(line){
        if(typeof line!=="string"||line.length>16384)return;
        try{
            const now=Date.now(),value=Data.clean(JSON.parse(line),now);
            if(!value)return;
            const next=Data.history(history,value);
            if(next===history)return;
            snapshot=value;history=next;nowMs=now;receivedAt=now;error="";
        }catch(e){/* Ignore partial/malformed frames; existing readings expire. */}
    }
    onWantedChanged:{
        nowMs=Date.now();retry.stop();
        if(wanted)reader.running=true;else reader.running=false;
    }
    Timer {interval:1000;repeat:true;running:stats.clients>0;onTriggered:stats.nowMs=Date.now()}
    Timer {id:retry;interval:2000;onTriggered:if(stats.wanted)reader.running=true}
    Process {
        id:reader
        command:stats.commandOverride.length?stats.commandOverride:["python3","-u","-B",stats.helper]
        stdout:SplitParser {onRead:line=>stats.ingest(line)}
        onExited:(code,status)=>{
            if(stats.wanted){stats.receivedAt=0;stats.error="Statistics unavailable";retry.restart();}
        }
    }
}
