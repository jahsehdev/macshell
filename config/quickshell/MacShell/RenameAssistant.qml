pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "Common" as Common
Scope {
    id:root
    property var hub:null
    property string path:""
    property string oldName:""
    property string error:""
    property string action:""
    function open(){picker.open();}
    FileDialog { id:picker;title:"Choose a file to rename";onAccepted:{root.path=decodeURIComponent(selectedFile.toString().replace(/^file:\/\//,""));root.action="files.suggest";worker.command=["python3","-B",Quickshell.shellPath("bin/studio.py"),root.action,"--json",JSON.stringify({path:root.path})];worker.running=true;win.visible=true;} }
    Process {
        id:worker
        stdout:StdioCollector {onStreamFinished:{try{const r=JSON.parse(text);root.error=r.error || "";if(r.suggested){root.oldName=r.old;nameField.text=r.suggested;}if(r.renamed){root.path=r.renamed;root.oldName=nameField.text;root.error="Renamed successfully.";}}catch(e){root.error="Could not rename the file.";}}}
    }
    Window {
        id:win;title:"MacShell Rename Assistant";width:570;height:310;visible:false;color:Common.IconStyle.dark ? "#242429" : "#f5f5f7"
        ColumnLayout { anchors.fill:parent;anchors.margins:24;spacing:14
            Label {text:"Filename suggestion";font.pixelSize:22;color:Common.IconStyle.dark ? "white" : "#22222a"}
            Label {text:"Current name: "+root.oldName;Layout.fillWidth:true;elide:Text.ElideMiddle;color:Common.IconStyle.dark ? "#bbbbc7" : "#555560"}
            TextField {id:nameField;Layout.fillWidth:true;placeholderText:"New filename"}
            Label {text:root.error || "Local title-based suggestion. Review the name before applying.";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Common.IconStyle.dark ? "#bbbbc7" : "#555560"}
            RowLayout {
                Button {text:"Ask Luma for a name";enabled:!!root.hub;onClicked:root.hub.luma.open("Suggest a concise filename preserving the extension for: "+root.oldName+". Current local title suggestion: "+nameField.text)}
                Button {text:"Apply rename";enabled:!worker.running;onClicked:{root.action="files.rename";worker.command=["python3","-B",Quickshell.shellPath("bin/studio.py"),root.action,"--json",JSON.stringify({path:root.path,name:nameField.text})];worker.running=true;}}
            }
        }
    }
}
