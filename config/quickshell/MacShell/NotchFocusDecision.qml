pragma ComponentBehavior: Bound
import QtQuick
import "Common" as GlassCommon
import "NotchToolStyle.js" as ToolStyle
import "NotchToolsState.js" as Logic
import "NotchPomodoroStyle.js" as Style

Item {
    id: decision
    required property var host
    required property var tools
    property var draftContexts:tools.state.focus.contexts.slice()
    property var menusDraft:[]
    property bool rotateDraft:tools.state.focus.rotate
    property int secondsDraft:tools.state.focus.seconds
    readonly property bool interacting:managePopup.visible
    signal dismissed()
    function toggle(id) {
        draftContexts=draftContexts.indexOf(id)>=0?draftContexts.filter(v=>v!==id):draftContexts.concat([id]);
    }
    Text { text:"Focus Decision";color:"#F5F3EF";font.family:decision.host.family;font.pixelSize:15;font.weight:Font.Bold }
    Text { y:24;text:"Choose the live activities";color:"#B2ADA7";font.family:decision.host.family;font.pixelSize:12 }
    NotchToolButton {
        id:manageButton;objectName:"notchManageActivities"
        anchors.right:parent.right;y:0;implicitHeight:32;text:"Manage live activities";symbol:"settings";font.pixelSize:13;family:decision.host.family
        onClicked:managePopup.open()
    }
    Text { x:0;y:54;text:"SELECT CONTEXTS";color:"#A7A29B";font.family:decision.host.family;font.pixelSize:12;font.letterSpacing:1.4 }
    Grid {
        x:0;y:80;spacing:4;rowSpacing:6
        columns:decision.tools.state.menus.length>6?4:decision.tools.state.menus.length
        Repeater {
            model:decision.tools.state.menus
            Column {
                id:context
                required property string modelData
                readonly property bool selected:decision.draftContexts.indexOf(modelData)>=0
                width:decision.tools.state.menus.length>6?(decision.width-240)/4:Math.min(64,(decision.width-228)/decision.tools.state.menus.length-4);spacing:decision.tools.state.menus.length>6?3:8
                NotchToolButton {
                    objectName:"notchContext"+context.modelData
                    anchors.horizontalCenter:parent.horizontalCenter;implicitWidth:decision.tools.state.menus.length>6?32:48;implicitHeight:decision.tools.state.menus.length>6?32:44;iconSize:decision.tools.state.menus.length>6?20:22;round:true;family:decision.host.family
                    symbol:ToolStyle.icon(context.modelData)
                    ink:context.selected?"#E2C8A9":"#AFB4BC";fill:context.selected?"#32C9AF91":"#10FFFFFF"
                    Accessible.name:(context.selected?"Remove ":"Include ")+Style.activityName(context.modelData)
                    onClicked:decision.toggle(context.modelData)
                }
                Text { width:parent.width;text:Style.activityName(context.modelData);horizontalAlignment:Text.AlignHCenter;color:context.selected?"#ECE3D8":"#B7B9C1";font.family:decision.host.family;font.pixelSize:13 }
            }
        }
    }
    Rectangle { x:parent.width-216;y:54;width:1;height:146;color:"#20FFFFFF" }
    Column {
        x:parent.width-196;y:54;width:196;spacing:6
        Row { width:parent.width
            Text { width:parent.width-40;text:"ROTATION";color:"#A7A29B";font.family:decision.host.family;font.pixelSize:12;font.letterSpacing:1.2 }
            Text { width:40;text:decision.secondsDraft+"s";color:"#C6C2BA";horizontalAlignment:Text.AlignRight;font.family:decision.host.family;font.pixelSize:12 }
        }
        GlassCommon.GlassSlider {
            id:rotationSlider;objectName:"notchRotationSeconds";width:parent.width
            from:3;to:30;stepSize:1;value:decision.secondsDraft
            dark:managePopup.dark;accentColor:"#B7A186"
            onMoved:decision.secondsDraft=Math.round(value)
        }
        NotchToolButton { objectName:"notchRotationToggle";implicitHeight:32;text:decision.rotateDraft?"Auto rotation on":"Auto rotation off";symbol:decision.rotateDraft?"toolCheck":"circle";family:decision.host.family;font.pixelSize:13;fill:"transparent";onClicked:decision.rotateDraft=!decision.rotateDraft }
        Row { spacing:7
            NotchToolButton { objectName:"notchFocusDismiss";text:"Dismiss";implicitHeight:32;family:decision.host.family;font.pixelSize:13;onClicked:decision.dismissed() }
            NotchToolButton { objectName:"notchFocusAccept";text:"Accept Focus";implicitHeight:32;family:decision.host.family;font.pixelSize:13;fill:"#E8E8EF";ink:"#232327";enabled:decision.draftContexts.length>0;onClicked:if(decision.tools.configureFocus(decision.draftContexts,decision.rotateDraft,decision.secondsDraft))decision.dismissed() }
        }
    }
    NotchSettingsPopup {
        id:managePopup;objectName:"notchActivities";host:decision.host;control:manageButton
        title:"Live activities";subtitle:"Choose the pages available in your notch."
        acceptable:decision.menusDraft.length>0
        onAboutToShow:decision.menusDraft=decision.tools.state.menus.slice()
        onSaveRequested:{
            if(!decision.tools.updateMenus(decision.menusDraft))return;
            decision.draftContexts=decision.draftContexts.filter(id=>decision.menusDraft.indexOf(id)>=0);
            if(!decision.draftContexts.length)decision.draftContexts=[decision.menusDraft[0]];
            close();
        }
        Repeater {
            model:Logic.pageIds
            NotchToolButton {
                required property string modelData
                objectName:"notchManagePage"+modelData
                width:parent?parent.width:296;text:Style.activityName(modelData);family:decision.host.family
                symbol:decision.menusDraft.indexOf(modelData)>=0?"toolCheck":"circle"
                fill:"transparent";ink:managePopup.foreground
                onClicked:decision.menusDraft=decision.menusDraft.indexOf(modelData)>=0?decision.menusDraft.filter(id=>id!==modelData):decision.menusDraft.concat([modelData])
            }
        }
    }
}
