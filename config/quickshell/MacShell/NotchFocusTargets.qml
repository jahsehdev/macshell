pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: targets
    required property var host
    required property var tools
    readonly property var tasks:tools.state.tasks.filter(t=>!t.done || t.id===tools.pomodoro.targetId)
    Text { text:"Focus Target";color:"#F4F2EE";font.family:targets.host.family;font.pixelSize:15;font.weight:Font.Bold }
    Text { y:20;text:"Attach this session to a task.";color:"#92918F";font.family:targets.host.family;font.pixelSize:12 }
    ListView {
        objectName:"notchFocusTargetList"
        y:44;width:parent.width;height:parent.height-y-22
        clip:true;spacing:4;model:targets.tasks;boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:ScrollBar { policy:ScrollBar.AsNeeded }
        delegate:Item {
            id:task
            required property var modelData
            width:ListView.view.width-8;height:40
            readonly property bool selected:targets.tools.pomodoro.targetId===modelData.id
            NotchIcon { x:0;y:8;width:18;height:18;strokeWidth:2.6;kind:task.modelData.done?"check":"todo";ink:task.selected?"#C9AF91":"#B4B3B0" }
            Column { x:28;y:2;width:parent.width-x-70;spacing:3
                Text { width:parent.width;text:task.modelData.text;textFormat:Text.PlainText;elide:Text.ElideRight;color:"#F0EFEC";font.family:targets.host.family;font.pixelSize:14;font.weight:Font.Medium }
                Text { text:(task.modelData.done?"Completed":"Todo")+" · "+(targets.tools.pomodoro.sessions || []).filter(e=>e.targetId===task.modelData.id).length+" focus sessions";color:"#878786";font.family:targets.host.family;font.pixelSize:11 }
            }
            NotchPomodoroButton { reducedMotion: targets.host.reducedMotion; objectName:"notchSelectTarget"+task.modelData.id;anchors.right:parent.right;y:1;implicitWidth:64;implicitHeight:30;font.pixelSize:12;text:task.selected?"Clear":"Select";family:targets.host.family;ink:task.selected?"#C9AF91":"#232327";fill:task.selected?"#22C9AF91":"#E8E8EF";Accessible.name:(task.selected?"Clear target: ":"Focus on: ")+task.modelData.text;onClicked:targets.tools.selectTarget(task.selected?"":task.modelData.id) }
        }
        Text { visible:targets.tasks.length===0;anchors.centerIn:parent;width:parent.width-8;text:"No tasks yet. Add one in Todo to give this session a target.";wrapMode:Text.WordWrap;color:"#959490";font.family:targets.host.family;font.pixelSize:14 }
    }
    Text { anchors.bottom:parent.bottom;text:"Calendar agenda is not connected";color:"#777774";font.family:targets.host.family;font.pixelSize:11 }
}
