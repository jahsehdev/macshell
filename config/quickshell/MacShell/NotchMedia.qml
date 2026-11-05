pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// One shared player choice and output-monitor process for every notch display.
Scope {
    id: media
    required property var bar
    property var availablePlayers: Mpris.players.values
    property string selectedId: ""
    readonly property var player: {
        const players = availablePlayers;
        const selected = players.find(p => key(p) === selectedId);
        return selected || players.find(p => p.isPlaying) || players[0] || null;
    }
    function key(p) { return p ? String(p.dbusName || p.identity || "") : ""; }
    function selectPlayer(p) { selectedId = p ? key(p) : ""; }
    property bool persistence: true
    property bool ready: !persistence
    property bool visualizer: true
    property bool captureEnabled: true
    property int spectrumClients: 0
    property var bands: Array(24).fill(0)
    property string spectrumError: ""
    readonly property string monitor: bar && bar.sink ? String(bar.sink.name || "") : ""
    readonly property bool spectrumWanted: captureEnabled && spectrumClients > 0 && !!player && player.isPlaying
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME")+"/.config")+"/macshell"
    property string spectrumHelperPath:decodeURIComponent(Qt.resolvedUrl("bin/notch_spectrum.py").toString().replace(/^file:\/\//,""))
    property int captureFailures:0
    property int spectrumFrames:0
    property bool captureVerified:false
    function receiveSpectrum(data) {
        try {
            const message=JSON.parse(data);
            if(Array.isArray(message.bands)&&message.bands.length===24) {
                bands=message.bands;spectrumFrames++;
                if(!captureVerified && Math.max.apply(null,bands)>0.01){captureVerified=true;console.log("[notch-audio] Live output spectrum active");}
            }
            spectrumError=message.error||"";
            if(message.error)console.warn("[notch-audio]",message.error);
            else captureFailures=0;
        } catch(e) {}
    }
    onVisualizerChanged: saveSoon()
    onMonitorChanged: { captureFailures=0;spectrumProcess.running=false;if(spectrumWanted){restartCapture.interval=350;restartCapture.restart();} }
    onSpectrumWantedChanged: {
        restartCapture.stop();captureFailures=0;spectrumProcess.running=spectrumWanted;
        if (!spectrumWanted) { bands = Array(24).fill(0); spectrumError = "";captureVerified=false; }
    }
    function saveSoon() { if (persistence && ready) saveTimer.restart(); }
    FileView {
        id: store
        path: media.persistence ? media.configDir + "/notch-media.json" : ""
        preload: media.persistence
        printErrors: false; atomicWrites: true
        onLoaded: {
            try { const data=JSON.parse(text()); media.visualizer=data.visualizer!==false; } catch(e) {}
            media.ready=true;
        }
        onLoadFailed: cause => {media.ready=true;if(cause===FileViewError.FileNotFound)ensureDirectory.running=true;}
    }
    Process {id:ensureDirectory;command:["mkdir","-p",media.configDir];onExited:(code,status)=>{if(code===0)media.saveSoon();}}
    Timer { id:saveTimer;interval:300;onTriggered:store.setText(JSON.stringify({version:2,visualizer:media.visualizer})) }
    Timer { id:restartCapture;interval:350;onTriggered:if(media.spectrumWanted)spectrumProcess.running=true }
    Process {
        id: spectrumProcess
        objectName:"notchSpectrumProcess"
        command:["python3","-B",media.spectrumHelperPath,"--monitor",media.monitor]
        stdout:SplitParser {onRead:data=>media.receiveSpectrum(data)}
        onExited: (code,status) => {
            media.bands=Array(24).fill(0);
            if(media.spectrumWanted) {
                media.spectrumError=media.spectrumError||"Audio output unavailable";
                media.captureFailures++;
                restartCapture.interval=Math.min(10000,500*Math.pow(2,Math.min(media.captureFailures-1,5)));
                restartCapture.restart();
            }
        }
    }
}
