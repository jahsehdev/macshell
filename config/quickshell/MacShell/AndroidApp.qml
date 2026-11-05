pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "Common" as Common
Scope {
    id:root
    property var devices:[]
    property string message:"Connect your Android phone using USB, enable USB debugging, and approve this computer on the phone."
    property string serial:""
    function open(){win.visible=true;win.raise();win.requestActivate();refresh();}
    function refresh(){if(!status.running)status.running=true;}
    Process {
        id:status;command:["python3","-B",Quickshell.shellPath("bin/studio.py"),"android.status"]
        stdout:StdioCollector{onStreamFinished:{try{const r=JSON.parse(text);root.devices=r.devices || [];if(r.error)root.message=r.error;}catch(e){root.message="Unable to query Android devices.";}}}
    }
    Process {
        id:mirror
        command:["scrcpy","--serial",root.serial,"--window-title","MacShell Android","--max-size","1600","--max-fps","60"]
        stderr:StdioCollector{onStreamFinished:if(text.trim())root.message=text.trim().slice(-700)}
        onExited:root.message="Android mirroring stopped."
    }
    Window {
        id:win;title:"MacShell Android";width:590;height:420;visible:false;color:Common.IconStyle.dark ? "#242429" : "#f5f5f7"
        ColumnLayout{
            anchors.fill:parent;anchors.margins:24;spacing:14
            Label{text:"Android Mirroring";font.pixelSize:24;font.bold:true;color:Common.IconStyle.dark ? "white" : "#202024"}
            Label{text:root.message;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Common.IconStyle.dark ? "#ccccd3" : "#555560"}
            Repeater{model:root.devices
                RowLayout{
                    required property var modelData
                    Label{text:modelData.serial+" · "+modelData.state;color:Common.IconStyle.dark ? "white" : "#202024";Layout.fillWidth:true}
                    Button{text:"Connect";enabled:modelData.state==="device" && !mirror.running;onClicked:{root.serial=modelData.serial;mirror.running=true;}}
                }
            }
            Item{Layout.fillHeight:true}
            RowLayout{
                Button{text:"Refresh devices";onClicked:root.refresh()}
                Button{text:"Disconnect";enabled:mirror.running;onClicked:mirror.running=false}
            }
            Label{text:"Mirroring scales the phone display; it does not make Android apps reflow. Audio support depends on the phone and scrcpy version.";wrapMode:Text.WordWrap;Layout.fillWidth:true;color:Common.IconStyle.dark ? "#a8a8b3" : "#666671"}
        }
    }
}
