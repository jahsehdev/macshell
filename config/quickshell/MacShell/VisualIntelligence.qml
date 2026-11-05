pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Common" as Common

Scope {
    id: root
    property var hub: null
    property bool opened: false
    property bool selecting: false
    property bool busy: false
    property bool cancelled: false
    property bool capturing: false
    property string activeScreen: ""
    property rect selection: Qt.rect(0,0,0,0)
    property var clients: []
    property string geometry: ""
    property string imagePath: ""
    property string extractedText: ""
    property string error: ""
    Binding { target: root.hub; property: "visualCaptureActive"; value: root.opened || root.busy; when: root.hub !== null }
    function open() {
        if (busy) return;
        const mon=Hyprland.focusedMonitor;
        activeScreen=mon ? mon.name : (Quickshell.screens.length ? Quickshell.screens[0].name : "");
        selection=Qt.rect(0,0,0,0); extractedText=""; imagePath=""; error="";
        cancelled=false;selecting=true;capturing=false;opened=true;
        if (!windows.running) windows.running=true;
    }
    function close() { cancelled=true;opened=false;selecting=false;captureDelay.stop();worker.running=false;busy=false; }
    IpcHandler { target: "visual"; function open(): void { root.open(); } function close(): void { root.close(); } }
    Process {
        id: windows
        command:["hyprctl","-j","clients"]
        stdout: StdioCollector { onStreamFinished: { try { root.clients=JSON.parse(text); } catch(e) { root.clients=[]; } } }
    }
    Timer { id: captureDelay; interval: 120; onTriggered: { root.busy=true; worker.running=true; } }
    Process {
        id: worker
        command:["python3","-B",Quickshell.shellPath("bin/visual_intelligence.py"),"--geometry",root.geometry]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r=JSON.parse(text);root.imagePath=r.image || "";root.extractedText=r.text || "";root.error=r.error || ""; }
                catch(e) { root.error="Could not read the local OCR response."; }
            }
        }
        onExited: { root.busy=false;root.capturing=false;if(!root.cancelled)root.opened=true; }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            screen:modelData
            visible:root.opened && !root.capturing && root.activeScreen===modelData.name
            anchors { top:true;bottom:true;left:true;right:true }
            color:"transparent"
            exclusionMode:ExclusionMode.Ignore
            WlrLayershell.namespace:"macvisualintelligence"
            WlrLayershell.layer:WlrLayer.Overlay
            WlrLayershell.keyboardFocus:visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Item {
                id: area;anchors.fill:parent;focus:true
                Keys.onEscapePressed:root.close()
                Rectangle { anchors.fill:parent;color:root.selecting ? "#35000000" : "#99000000" }
                MouseArea {
                    anchors.fill:parent;enabled:root.selecting
                    property point start
                    onPressed: mouse => { start=Qt.point(mouse.x,mouse.y);root.selection=Qt.rect(mouse.x,mouse.y,0,0); }
                    onPositionChanged: mouse => {
                        if (pressed) root.selection=Qt.rect(Math.min(start.x,mouse.x),Math.min(start.y,mouse.y),Math.abs(mouse.x-start.x),Math.abs(mouse.y-start.y));
                    }
                    onReleased: mouse => {
                        if (root.selection.width<8 || root.selection.height<8) {
                            // A click selects the topmost window under the pointer on the active workspace.
                            const mon=Hyprland.focusedMonitor;
                            for(let i=root.clients.length-1;i>=0;i--) {
                                const c=root.clients[i],x=mouse.x+panel.modelData.x,y=mouse.y+panel.modelData.y;
                                if(c.hidden || !c.mapped || !c.workspace || (mon && mon.activeWorkspace && c.workspace.id!==mon.activeWorkspace.id)) continue;
                                if(x>=c.at[0] && y>=c.at[1] && x<c.at[0]+c.size[0] && y<c.at[1]+c.size[1]) {
                                    root.selection=Qt.rect(c.at[0]-panel.modelData.x,c.at[1]-panel.modelData.y,c.size[0],c.size[1]);break;
                                }
                            }
                        }
                        if(root.selection.width<8 || root.selection.height<8) return;
                        root.selecting=false;revealDelay.restart();
                    }
                }
                IntelligenceGlow {
                    x:root.selection.x-10;y:root.selection.y-10
                    width:root.selection.width+20;height:root.selection.height+20
                    visible:root.selection.width>0 && root.imagePath===""
                }
                Timer {
                    id:revealDelay;interval:Common.DesktopPreferences.reduceMotion ? 0 : 480
                    onTriggered: {
                        root.geometry=Math.round(panel.modelData.x+root.selection.x)+","+Math.round(panel.modelData.y+root.selection.y)+" "+Math.round(root.selection.width)+"x"+Math.round(root.selection.height);
                        root.capturing=true;captureDelay.restart();
                    }
                }
                Text { anchors.horizontalCenter:parent.horizontalCenter;y:48;text:"Visual Intelligence · Drag a region or click a window · Esc to cancel";color:"white";font.pixelSize:16;visible:root.selecting }
                Rectangle {
                    anchors.centerIn:parent;width:Math.min(680,parent.width-48);height:Math.min(580,parent.height-90)
                    radius:22;color:Common.IconStyle.dark ? "#f028282d" : "#faf5f5f7"
                    visible:!root.selecting && !revealDelay.running
                    border.width:Common.DesktopPreferences.showBorders ? 2 : 1;border.color:"#887e9cff"
                    Column {
                        anchors.fill:parent;anchors.margins:22;spacing:12
                        Row { spacing:12;Text { text:"Visual Intelligence";font.pixelSize:20;color:Common.IconStyle.dark ? "white" : "#202024" }
                            Button { text:"Close";onClicked:root.close() } }
                        Image { width:parent.width;height:140;fillMode:Image.PreserveAspectFit;source:root.imagePath ? "file://"+root.imagePath : "" }
                        Text { width:parent.width;text:root.error || (root.extractedText ? "Text extracted locally · OCR" : "No readable text found. General image understanding needs a local vision model.");wrapMode:Text.WordWrap;color:Common.IconStyle.dark ? "#c9c9d0" : "#55555c" }
                        ScrollView { width:parent.width;height:Math.max(70,parent.parent.height-300)
                            TextArea { text:root.extractedText;readOnly:true;selectByMouse:true;wrapMode:TextEdit.Wrap;textFormat:TextEdit.PlainText;color:Common.IconStyle.dark ? "white" : "#202024" } }
                        Button { text:"Ask Luma about this text";enabled:root.extractedText!=="";onClicked:{ if(root.hub) root.hub.luma.open("Explain this screen text:\n"+root.extractedText.slice(0,3000));root.close(); } }
                    }
                }
            }
        }
    }
}
