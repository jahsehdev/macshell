pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id:root
    property string text:""
    property string error:""
    readonly property bool running:worker.running
    function start(value){text=value;error="";worker.stdinEnabled=true;worker.running=true;}
    function stop(){worker.running=false;}
    Process {
        id:worker
        command:["python3","-B",Quickshell.shellPath("bin/speech.py"),"speak"]
        stdinEnabled:true
        onStarted:{write(root.text);stdinEnabled=false;}
        stdout:StdioCollector {onStreamFinished:{try{const r=JSON.parse(text);root.error=r.error || "";}catch(e){}}}
    }
}
