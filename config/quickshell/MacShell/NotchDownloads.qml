pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// One watcher for all displays: browser transfers and download markers only.
// File copies/extraction do not start activity; browser completion is authoritative.
Scope {
    id: downloads
    property bool enabled: true
    property bool ready: false
    property var items: []
    property var dismissedStates: ({})
    property var seenStates: ({})
    property string feedbackKey: ""
    property string error: ""
    readonly property bool busy: actionProcess.running
    readonly property var current: {
        const visible=items.filter(j=>dismissedStates[j.id]!==phase(j.state));
        return visible.find(j=>["active","waiting","paused"].indexOf(j.state)>=0) || visible[0] || null;
    }
    readonly property bool active: !!current
    readonly property int count: items.filter(j=>["active","waiting","paused"].indexOf(j.state)>=0).length
    readonly property bool feedback: !!current && feedbackKey===current.id+":"+current.state
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bin/notch_downloads.py").toString().replace(/^file:\/\//,""))
    signal dismissed()
    function phase(state){return ["active","waiting","paused"].indexOf(state)>=0?"transfer":state;}
    function accept(data) {
        if(!data || !Array.isArray(data.items))return;
        if(!ready){ready=true;console.info("[notch-downloads] Download watcher connected");}
        items=data.items.filter(j=>j && typeof j.id==="string" && typeof j.path==="string" && typeof j.state==="string").slice(0,32);
        const seen={},hidden={};
        for(const job of items) {
            if(dismissedStates[job.id])hidden[job.id]=dismissedStates[job.id];
            seen[job.id]=job.state;
        }
        const job=current;
        if(job && ["complete","saved","interrupted"].indexOf(job.state)>=0 && seenStates[job.id]!==job.state && dismissedStates[job.id]!==phase(job.state)) {
            feedbackKey=job.id+":"+job.state; feedbackTimer.restart();
        }
        dismissedStates=hidden;seenStates=seen;
    }
    function dismiss() {
        if(current){const states=Object.assign({},dismissedStates);states[current.id]=phase(current.state);dismissedStates=states;}
        feedbackKey="";feedbackTimer.stop();error="";dismissed();
    }
    function reset() {ready=false;items=[];dismissedStates={};seenStates={};feedbackKey="";feedbackTimer.stop();error="";}
    function act(kind) {
        if(!current || busy || ["open","reveal"].indexOf(kind)<0 || ["complete","saved"].indexOf(current.state)<0)return;
        error="";actionProcess.jobId=current.id;
        actionProcess.command=["python3","-B",helper,kind,current.path];actionProcess.running=true;
    }
    Timer {id:feedbackTimer;interval:8000;onTriggered:downloads.feedbackKey=""}
    Timer {id:retry;interval:3000;onTriggered:if(downloads.enabled)watcher.running=true}
    onEnabledChanged: {retry.stop();watcher.running=enabled;if(!enabled)reset();}
    Process {
        id:watcher
        command:["python3","-B",downloads.helper,"watch"]
        running:downloads.enabled
        stdout:SplitParser {onRead:data=>{try{downloads.accept(JSON.parse(data));}catch(e){}}}
        onExited:{downloads.ready=false;downloads.items=[];downloads.feedbackKey="";if(downloads.enabled)retry.restart();}
    }
    Process {
        id:actionProcess
        property string jobId:""
        stdout:StdioCollector {onStreamFinished:{
            if(!downloads.current || downloads.current.id!==actionProcess.jobId)return;
            try{const data=JSON.parse(text);if(!data.ok)downloads.error=data.error||"Unable to open this file.";}
            catch(e){downloads.error="Unable to open this file.";}
        }}
    }
}
