pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// One completion/result and one file-action process shared across all screens.
Scope {
    id: recording
    required property var bar
    property var result: null
    property string error: ""
    property string message: ""
    property bool inspecting: false
    readonly property bool busy: actionProcess.running
    property string requestPath: ""
    property string actionKind: ""
    property int generation: 0
    property string queuedPath: ""
    signal dismissed()
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/notch_recording.py").toString().replace(/^file:\/\//,""))
    signal completed()

    function dismiss() { result=null;error="";message="";dismissed(); }
    function reset() {
        generation++;queuedPath="";inspecting=false;dismiss();
    }
    function finish(path) {
        if(!path || bar.recording)return;
        inspecting=true;error="";message="";
        if(inspectProcess.running){queuedPath=path;return;}
        requestPath=path;inspectProcess.token=generation;
        inspectProcess.command=["python3",helper,"inspect",path];inspectProcess.running=true;
    }
    function acceptInspection(data, token) {
        if(token!==generation || bar.recording)return;
        inspecting=false;
        if(data && data.ok && data.path && data.duration>0) {result=data;error="";completed();}
        else {result=null;error=data && data.error?data.error:"The recording could not be saved.";completed();}
    }
    function act(kind) {
        if(!result || busy || bar.recording || inspecting || ["watch","reveal","copy","trash"].indexOf(kind)<0)return;
        actionKind=kind;actionProcess.token=generation;error="";message="";
        actionProcess.command=["python3",helper,kind,result.path];actionProcess.running=true;
    }
    Connections {
        target:recording.bar;ignoreUnknownSignals:true
        function onRecordingChanged(){if(recording.bar.recording)recording.reset();}
    }
    Process {
        id:inspectProcess
        property int token:0
        onExited:Qt.callLater(function(){if(recording.queuedPath && !recording.bar.recording){const path=recording.queuedPath;recording.queuedPath="";recording.finish(path);}})
        stdout:StdioCollector {
            onStreamFinished: {
                let data;
                try {data=JSON.parse(text);}catch(e){data={ok:false,error:"Unable to inspect the saved recording."};}
                recording.acceptInspection(data,inspectProcess.token);
            }
        }
    }
    Process {
        id:actionProcess
        property int token:0
        stdout:StdioCollector {
            onStreamFinished: {
                if(actionProcess.token!==recording.generation)return;
                let data;
                try {data=JSON.parse(text);}catch(e){data={ok:false,error:"Recording action failed."};}
                if(!data.ok)recording.error=data.error||"Recording action failed.";
                else if(recording.actionKind==="trash")recording.dismiss();
                else if(recording.actionKind==="copy")recording.message="Copied";
            }
        }
    }
}
