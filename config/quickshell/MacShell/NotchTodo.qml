pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry
import QtQuick.Controls

Item {
    id: page
    required property var host
    required property var tools
    property bool editing: false
    property bool managing: false
    property string taskId: ""
    readonly property bool interacting: editing
    function edit(task) {
        taskId = task ? task.id : ""; editor.text = task ? task.text : ""; editing = true;
        editor.forceActiveFocus();
    }
    function saveTask() {
        const ok = taskId ? tools.editTask(taskId,editor.text) : tools.addTask(editor.text);
        if (ok) { editing=false; taskId=""; editor.text=""; }
    }
    Item {
        anchors.fill:parent; visible:!page.editing
        Column {
            y:0; width:164; spacing:5
            Text { text:page.tools.doneToday + "/" + (page.tools.doneToday+page.tools.pendingTasks); color:"white"; font.family:page.host.family; font.pixelSize:40; font.weight:Font.Bold }
            Text { text:"Tasks done today"; color:"#B1B7C2"; font.family:page.host.family; font.pixelSize:13 }
            Row { topPadding:18; spacing:8
                NotchToolButton { objectName:"notchTodoAdd"; text:"Add task"; symbol:"plus"; family:page.host.family; onClicked:page.edit(null) }
                NotchToolButton { symbol:"edit"; fill:page.managing ? "#243E2D" : "#12FFFFFF"; family:page.host.family; Accessible.name:"Edit tasks"; onClicked:page.managing=!page.managing }
            }
        }
        ListView {
            objectName:"notchTodoList"
            x:180; width:parent.width-x; height:parent.height
            model:page.tools.state.tasks
            spacing:8; clip:true; boundsBehavior:Flickable.StopAtBounds
            ScrollBar.vertical:ScrollBar { policy:ScrollBar.AsNeeded }
            delegate: Rectangle {
                id:task
                required property var modelData
                width:ListView.view.width-9; height:40; radius:Geometry.controlRadius
                color:modelData.done ? "#183B25" : "#171C24"
                NotchToolButton {
                    cornerRadius:Geometry.innerRadius(task.radius,4,width,height)
                    x:4; y:4; implicitWidth:32; implicitHeight:32; symbol:task.modelData.done ? "toolCheck" : "circle"; fill:"transparent"
                    ink:task.modelData.done ? "#5CDF97" : "#AFB7C3"
                    Accessible.name:(task.modelData.done ? "Mark incomplete: " : "Complete task: ")+task.modelData.text
                    onClicked:page.tools.toggleTask(task.modelData.id)
                }
                Text {
                    x:44; anchors.verticalCenter:parent.verticalCenter; width:parent.width-x-(page.managing ? 74 : 12)
                    text:task.modelData.text; textFormat:Text.PlainText; elide:Text.ElideRight
                    color:task.modelData.done ? "#B5C8BB" : "#F2F3F8"; font.family:page.host.family; font.pixelSize:15; font.strikeout:task.modelData.done
                }
                Row { visible:page.managing; anchors.right:parent.right; anchors.rightMargin:4; y:4; spacing:2
                    NotchToolButton { cornerRadius:Geometry.innerRadius(task.radius,4,width,height);implicitWidth:30; implicitHeight:32; symbol:"edit"; fill:"transparent"; Accessible.name:"Edit "+task.modelData.text; onClicked:page.edit(task.modelData) }
                    NotchToolButton { cornerRadius:Geometry.innerRadius(task.radius,4,width,height);implicitWidth:30; implicitHeight:32; symbol:"close"; fill:"transparent"; ink:"#E9A5AC"; Accessible.name:"Delete "+task.modelData.text; onClicked:page.tools.removeTask(task.modelData.id) }
                }
            }
            Text { anchors.centerIn:parent; width:parent.width-12; visible:page.tools.state.tasks.length===0; text:"A little space for your next task."; wrapMode:Text.WordWrap; horizontalAlignment:Text.AlignHCenter; color:"#B1B7C2"; font.family:page.host.family; font.pixelSize:15 }
        }
    }
    Item {
        anchors.fill:parent; visible:page.editing
        Text { text:page.taskId ? "Edit task" : "What would you like to do?"; color:"#B9BDC8"; font.family:page.host.family; font.pixelSize:15 }
        NotchInput {
            id:editor; objectName:"notchTodoEditor"; y:32; width:parent.width; height:40;font.pixelSize:15
            maximumLength:300; placeholderText:"Task name"; family:page.host.family
            onAccepted:if(text.trim())page.saveTask()
            Keys.onEscapePressed:page.editing=false
        }
        Row { anchors.right:parent.right; y:108; spacing:7
            NotchToolButton { text:"Cancel"; family:page.host.family; onClicked:page.editing=false }
            NotchToolButton { objectName:"notchTodoSave"; text:page.taskId ? "Save" : "Add task"; family:page.host.family; fill:"#205A38"; enabled:editor.text.trim().length>0; onClicked:page.saveTask() }
        }
    }
}
