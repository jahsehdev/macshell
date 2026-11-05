pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id:voice
    property bool active:false
    property string state:"idle"
    property string error:""
    signal transcript(string text)
    signal unavailable()
    onActiveChanged:{
        if(active){error="";state="starting";worker.running=true;}
        else if(worker.running && (state==="listening" || state==="starting"))worker.write("stop\n");
    }
    function cancel(){if(worker.running)worker.write("cancel\n");worker.running=false;state="idle";}
    Process {
        id:worker
        command:["python3","-B","-u",Quickshell.shellPath("bin/speech.py"),"record"]
        stdinEnabled:true
        stdout:SplitParser {
            onRead:data=>{
                try {
                    const event=JSON.parse(data);
                    if(event.event==="error"){voice.error=event.message;voice.state="error";voice.unavailable();}
                    else if(event.event==="transcript"){voice.transcript(event.text);voice.state="idle";}
                    else voice.state=event.event || "idle";
                } catch(e){voice.error="Invalid speech response.";voice.state="error";}
            }
        }
        onExited:{if(voice.state!=="error")voice.state="idle";}
    }
}
