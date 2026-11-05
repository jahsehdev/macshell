pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "NotchCalendarState.js" as Dates

Item {
    id:page
    required property var host
    required property var tools
    readonly property var calendar:tools.calendar
    readonly property bool large:host.calendarExpanded
    readonly property real agendaWidth:(width-24)/2
    readonly property var dayEvents:Dates.onDay(calendar.events,calendar.selectedDate)
    readonly property var dayTasks:Dates.key(calendar.selectedDate)===Dates.key(today)?tools.state.tasks.filter(t=>!t.done):[]
    readonly property bool demo:calendar.events.length===0 && tools.state.tasks.length===0 && calendar.error==="" && !calendar.busy
    readonly property var agenda:(demo?Dates.examples(calendar.selectedDate):dayEvents).map(e=>Object.assign({},e,{task:false})).concat(demo?[{id:"example-task",title:"Send presentation",task:true,example:true}]:dayTasks.map(t=>({id:t.id,title:t.text,task:true,example:false})))
    readonly property var days:Dates.cells(calendar.visibleMonth)
    readonly property bool interacting:editor.visible || details.visible || agendaList.dragging || agendaList.moving
    property date today:new Date()
    property bool creatingTask:false
    property var inspected:null
    function openEditor(task) {creatingTask=!!task;calendar.saveError="";titleField.text="";startField.text="10:00";endField.text="11:00";editor.open();}
    Timer {interval:30000;repeat:true;running:page.visible;onTriggered:page.today=new Date()}
    Connections {target:page.calendar;function onCreated(){editor.close();}}
    Text {text:Qt.formatDate(page.calendar.selectedDate,"ddd").toUpperCase()+" ";color:"#FF625F";font.family:page.host.family;font.pixelSize:13;font.weight:Font.Bold}
    Text {x:34;text:Qt.formatDate(page.calendar.selectedDate,"d")+"  W"+Dates.week(page.calendar.selectedDate);color:"#ECEFF4";font.family:page.host.family;font.pixelSize:13;font.weight:Font.DemiBold}
    Text {y:20;width:page.agendaWidth;text:page.demo?"Example agenda":page.calendar.busy?"Loading calendar…":page.calendar.error!==""?page.calendar.error:Qt.formatDate(page.calendar.selectedDate,"MMMM yyyy");color:page.demo?"#9BA3B2":"#AAB1BF";font.family:page.host.family;font.pixelSize:11;elide:Text.ElideRight}
    ListView {
        id:agendaList;objectName:"notchCalendarAgenda";x:0;y:40;width:page.agendaWidth;height:parent.height-y;clip:true;spacing:4;model:page.agenda;boundsBehavior:Flickable.StopAtBounds
        ScrollBar.vertical:ScrollBar {policy:ScrollBar.AsNeeded}
        delegate:Rectangle {
            id:event
            required property var modelData
            width:ListView.view.width-4;height:modelData.task?34:page.large?56:40;radius:8
            readonly property color tint:modelData.task?"#F4BA68":modelData.color||"#8B83FF"
            color:Qt.rgba(tint.r,tint.g,tint.b,modelData.task?.09:.13)
            Rectangle {x:3;y:5;width:3;height:parent.height-10;radius:1.5;color:event.tint;visible:!event.modelData.task}
            NotchToolButton {
                objectName:"notchCalendarTask"+event.modelData.id
                visible:event.modelData.task;x:3;y:2;implicitWidth:30;implicitHeight:30;round:true;fill:"transparent";symbol:"circle";iconSize:17;ink:event.tint
                Accessible.name:event.modelData.example?"Example task":("Complete task: "+event.modelData.title)
                onClicked:if(!event.modelData.example)page.tools.toggleTask(event.modelData.id)
            }
            Text {x:event.modelData.task?36:12;y:event.modelData.task?8:5;width:parent.width-x-8;text:event.modelData.title;textFormat:Text.PlainText;elide:Text.ElideRight;color:event.modelData.task?"#EDF0F5":event.tint;font.family:page.host.family;font.pixelSize:page.large?16:14;font.weight:Font.DemiBold}
            Text {x:12;y:page.large?29:22;width:parent.width-x-8;visible:!event.modelData.task;text:event.modelData.task?"":Dates.time(event.modelData);color:Qt.lighter(event.tint,1.15);font.family:page.host.family;font.pixelSize:page.large?13:11}
            MouseArea {anchors.fill:parent;visible:!event.modelData.task;cursorShape:Qt.PointingHandCursor;onClicked:{page.inspected=event.modelData;details.open();}}
        }
        Text {anchors.centerIn:parent;width:parent.width-20;visible:page.agenda.length===0;text:page.calendar.busy?"Loading…":page.calendar.error!==""?"Calendar unavailable\nUse + to add a task.":"No events for this day";wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter;color:"#ABB4C2";font.family:page.host.family;font.pixelSize:14}
    }
    Item {
        id:monthPane;x:page.agendaWidth+24;width:page.agendaWidth;height:parent.height
        NotchToolButton {objectName:"notchCalendarPrevious";implicitWidth:24;implicitHeight:24;iconSize:14;fill:"transparent";symbol:"chevronLeft";family:page.host.family;Accessible.name:"Previous month";onClicked:page.calendar.changeMonth(-1)}
        Text {x:28;y:4;width:parent.width-124;text:Qt.formatDate(page.calendar.visibleMonth,page.large?"MMMM yyyy":"MMM yyyy").toUpperCase();elide:Text.ElideRight;color:"#FF625F";font.family:page.host.family;font.pixelSize:12;font.weight:Font.Bold}
        NotchToolButton {objectName:"notchCalendarNext";x:parent.width-88;implicitWidth:24;implicitHeight:24;iconSize:14;fill:"transparent";symbol:"chevron";family:page.host.family;Accessible.name:"Next month";onClicked:page.calendar.changeMonth(1)}
        NotchToolButton {id:addButton;objectName:"notchCalendarAdd";x:parent.width-58;implicitWidth:24;implicitHeight:24;iconSize:16;round:true;fill:"#252A31";symbol:"plus";family:page.host.family;Accessible.name:"Add event or task";onClicked:page.openEditor(false)}
        NotchToolButton {objectName:"notchCalendarExpand";x:parent.width-28;implicitWidth:24;implicitHeight:24;iconSize:14;round:true;fill:"#252A31";symbol:page.large?"collapse":"expand";family:page.host.family;Accessible.name:page.large?"Compact calendar":"Expand calendar inside notch";onClicked:page.host.calendarExpanded=!page.host.calendarExpanded}
        Row {y:36;width:parent.width;Repeater {model:["S","M","T","W","T","F","S"];Text {required property string modelData;width:monthPane.width/7;text:modelData;horizontalAlignment:Text.AlignHCenter;color:"#939CAB";font.family:page.host.family;font.pixelSize:12;font.weight:Font.DemiBold}}}
        Grid {
            id:grid;objectName:"notchCalendarGrid";y:58;width:parent.width;columns:7
            readonly property real cell:Math.min(page.large?46:30,(page.height-y)/(page.days.length/7))
            Repeater {
                model:page.days
                NotchPomodoroButton {
                    id:day
                    required property var modelData
                    readonly property bool selected:modelData.key===Dates.key(page.calendar.selectedDate)
                    readonly property bool isToday:modelData.key===Dates.key(page.today)
                    objectName:"notchCalendarDay"+modelData.key
                    width:monthPane.width/7;height:grid.cell
                    Accessible.name:Qt.formatDate(Dates.date(modelData.key),"dddd, d MMMM yyyy");Accessible.selected:selected
                    text:String(modelData.day);padding:0;round:true;reducedMotion:page.host.reducedMotion
                    fill:isToday?"#FF5559":selected?"#F5F5F7":"transparent"
                    ink:isToday?"white":selected?"#20242B":modelData.current?"#F1F3F7":"#687180"
                    family:page.host.family;font.pixelSize:page.large?16:14;font.weight:Font.DemiBold
                    background.width:Math.min(28,day.height-2);background.height:background.width
                    background.x:(day.width-background.width)/2;background.y:(day.height-background.height)/2
                    onClicked:page.calendar.select(modelData.key)
                }
            }
        }
        MouseArea {x:28;y:0;width:Math.max(0,parent.width-124);height:28;cursorShape:Qt.PointingHandCursor;onClicked:page.calendar.today();Accessible.name:"Return to today"}
    }
    NotchSettingsPopup {
        id:editor;objectName:"notchCalendarEditor";host:page.host;control:addButton
        title:page.creatingTask?"New task":"New event";subtitle:Qt.formatDate(page.calendar.selectedDate,"dddd, d MMMM yyyy")
        acceptable:titleField.acceptableInput && titleField.text.trim()!=="" && !page.calendar.saving && (page.creatingTask || Dates.eventPayload(page.calendar.selectedDate,titleField.text,startField.text,endField.text)!==null)
        onSaveRequested:{if(page.creatingTask){if(page.tools.addTask(titleField.text)){page.calendar.today();close();}}else page.calendar.createEvent(titleField.text,startField.text,endField.text);}
        Row {
            spacing:8
            NotchToolButton {objectName:"notchCalendarEventMode";text:"Event";fill:!page.creatingTask?"#314057":"#16212E";family:page.host.family;onClicked:page.creatingTask=false}
            NotchToolButton {objectName:"notchCalendarTaskMode";text:"Task";fill:page.creatingTask?"#314057":"#16212E";family:page.host.family;onClicked:page.creatingTask=true}
        }
        Column {
            width:parent.width;spacing:6
            Text {text:"Title";color:editor.foreground;font.family:page.host.family;font.pixelSize:12;font.weight:Font.Medium}
            NotchInput {id:titleField;objectName:"notchCalendarTitle";width:parent.width;height:36;family:page.host.family;dark:editor.dark;placeholderText:page.creatingTask?"Task title":"Event title";validator:RegularExpressionValidator {regularExpression:/.{1,300}/} onAccepted:if(editor.acceptable)editor.saveRequested()}
        }
        NotchSettingsField {id:startField;fieldName:"notchCalendarStart";menu:editor;label:"Start (24h)";visible:!page.creatingTask;validator:RegularExpressionValidator {regularExpression:/([01]\d|2[0-3]):[0-5]\d/}}
        NotchSettingsField {id:endField;fieldName:"notchCalendarEnd";menu:editor;label:"End (24h)";visible:!page.creatingTask;validator:RegularExpressionValidator {regularExpression:/([01]\d|2[0-3]):[0-5]\d/}}
        Text {width:parent.width;visible:page.creatingTask;text:"Tasks are added to Todo and shown in today's agenda.";wrapMode:Text.WordWrap;color:editor.secondary;font.family:page.host.family;font.pixelSize:12}
        Text {width:parent.width;visible:page.calendar.saveError!=="";text:page.calendar.saveError;wrapMode:Text.WordWrap;color:"#FF9B90";font.family:page.host.family;font.pixelSize:12}
    }
    NotchSettingsPopup {
        id:details;objectName:"notchCalendarDetails";host:page.host;control:addButton
        title:page.inspected?page.inspected.title:"Event";subtitle:page.inspected && page.inspected.example?"Example event • preview only":"Local calendar event";acceptText:"Done";showCancel:false
        onSaveRequested:close()
        Text {width:parent.width;text:page.inspected?Qt.formatDate(page.calendar.selectedDate,"dddd, d MMMM yyyy")+"\n"+Dates.time(page.inspected):"";color:details.foreground;wrapMode:Text.WordWrap;font.family:page.host.family;font.pixelSize:14}
        Text {width:parent.width;visible:text!=="";text:page.inspected?page.inspected.location||"":"";color:details.secondary;wrapMode:Text.WordWrap;textFormat:Text.PlainText;font.family:page.host.family;font.pixelSize:12}
    }
}
