pragma ComponentBehavior: Bound
import QtQuick
import "NotchPomodoroStyle.js" as Style

Item {
    id: page
    required property var host
    required property var tools
    readonly property bool active: tools.pomodoro.state !== "idle"
    readonly property bool resting: ["short", "long"].indexOf(tools.pomodoro.mode) >= 0
    readonly property bool configuring: settingsMenu.visible
    readonly property bool interacting: configuring || ruler.pressed || (!!decision.item && decision.item.interacting)
    readonly property color tint: "#FF9F0A"
    function saveSettings() {
        if (![focusInput,shortInput,longInput,quickInput,customInput,cyclesInput].every(f=>f.acceptableInput)) return;
        tools.updateSettings({focus:Number(focusInput.text),short:Number(shortInput.text),long:Number(longInput.text),quick:Number(quickInput.text),custom:Number(customInput.text),cycles:Number(cyclesInput.text)});
        settingsMenu.close();
    }
    Item {
        anchors.fill: parent
        visible: !page.host.focusDecisionOpen
        Item {
            anchors.fill: parent; visible: !page.active
            Rectangle {
                width: 160; height: 36; radius: 18
                color: "#202329"; border.width: 0.8; border.color: "#323A44"
                NotchPomodoroButton {
                    reducedMotion: page.host.reducedMotion
                    objectName: "notchPresetfocus"
                    x: 2; y: 2; text: "Focus"; implicitWidth: 78; implicitHeight: 32; round: true
                    ink: !page.resting ? "#FFD394" : "#A9B0BB"
                    fill: !page.resting ? "#44321A" : "transparent"; family: page.host.family
                    font.pixelSize: 14; font.weight: !page.resting ? Font.DemiBold : Font.Medium
                    Accessible.name: "Focus timer"; Accessible.role: Accessible.PageTab; Accessible.selected: !page.resting
                    onClicked: page.tools.setPhase("focus")
                }
                NotchPomodoroButton {
                    reducedMotion: page.host.reducedMotion
                    objectName: "notchPresetshort"
                    x: 80; y: 2; text: "Break"; implicitWidth: 78; implicitHeight: 32; round: true
                    ink: page.resting ? "#FFD394" : "#A9B0BB"
                    fill: page.resting ? "#44321A" : "transparent"; family: page.host.family
                    font.pixelSize: 14; font.weight: page.resting ? Font.DemiBold : Font.Medium
                    Accessible.name: "Break timer"; Accessible.role: Accessible.PageTab; Accessible.selected: page.resting
                    onClicked: page.tools.setPhase("short")
                }
            }
            NotchPomodoroRuler {
                id: ruler
                objectName: "notchPomodoroRuler"
                y: 52; width: parent.width
                value: Math.round(page.tools.pomodoro.total / 60000)
                maximum: page.tools.pomodoro.mode === "short" ? 60 : page.tools.pomodoro.mode === "long" ? 120 : 180
                family: page.host.family; accent: page.tint
                onMoved: minutes => {
                    const change = {}; change[page.tools.pomodoro.mode] = minutes;
                    page.tools.updateSettings(change);
                }
            }
        }
        NotchPomodoroButton {
            reducedMotion: page.host.reducedMotion
            objectName: "notchPomodoroToggle"
            y: page.active ? 8 : 128
            implicitWidth: page.active ? 40 : parent.width - 112; implicitHeight: 40; round: true
            symbol: page.active ? (page.tools.pomodoro.state === "running" ? "pomoPause" : "pomoPlay") : "pomoPlay"
            text: page.active ? "" : "Start Timer"
            iconSize: page.active ? 20 : 18; ink: page.active ? page.tint : "#241700"; fill: page.active ? "#382506" : "#FFAD32"; family: page.host.family
            font.pixelSize: 17; font.weight: Font.DemiBold
            Accessible.name: page.tools.pomodoro.state === "running" ? "Pause timer" : page.tools.pomodoro.state === "paused" ? "Resume timer" : page.tools.pomodoro.state === "finished" ? "Start next session" : "Start timer"
            onClicked: page.tools.togglePomodoro()
        }
        NotchPomodoroButton {
            reducedMotion: page.host.reducedMotion
            objectName: "notchPomodoroStop"
            visible: page.active; x: 52; y: 8
            implicitWidth: 40; implicitHeight: 40; round: true
            symbol: "close"; iconSize: 21; ink: "#BCBCC5"; fill: "#252528"; family: page.host.family
            Accessible.name: "Cancel timer"
            onClicked: page.tools.resetPomodoro()
        }
        NotchPomodoroButton {
            reducedMotion: page.host.reducedMotion
            objectName: "notchPomodoroSound"
            visible: !page.active; x: parent.width - 92; y: 128
            implicitWidth: 40; implicitHeight: 40; round: true
            symbol: page.tools.settings.pomodoroSound ? "volume" : "volumeOff"
            iconSize: 20; ink: page.tools.settings.pomodoroSound ? "#E6C18D" : "#A9B0BB"
            fill: "#252A32"; family: page.host.family
            checkable: true; checked: page.tools.settings.pomodoroSound
            Accessible.name: page.tools.settings.pomodoroSound ? "Mute timer completion sound" : "Enable timer completion sound"
            onClicked: page.tools.updateSettings({pomodoroSound: !page.tools.settings.pomodoroSound})
        }
        NotchPomodoroButton {
            reducedMotion: page.host.reducedMotion
            id: settingsButton
            objectName: "notchPomodoroSettings"
            visible: !page.active; x: parent.width - 40; y: 128
            implicitWidth: 40; implicitHeight: 40; round: true
            symbol: "timer"; iconSize: 20; ink: "#BFC6D0"; fill: "#252A32"; family: page.host.family
            Accessible.name: "Timer settings"
            onClicked: settingsMenu.open()
        }
        Row {
            anchors.right: parent.right; y: page.active ? 4 : -8; height: 44; spacing: 8
            Text {
                objectName: "notchPomodoroPhaseLabel"
                visible: page.active; anchors.baseline: timeText.baseline
                text: page.tools.pomodoro.state === "paused" ? "Paused" : page.tools.pomodoro.state === "finished" ? "Done" : Style.phaseName(page.tools.pomodoro.mode)
                color: page.tint; font.family: page.host.family; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                id: timeText
                objectName: "notchPomodoroTime"
                text: Style.time(page.tools.pomodoroLeft)
                color: page.active ? page.tint : "#FFF3DE"; font.family: page.host.family; font.pixelSize: page.active ? 36 : 44; font.weight: Font.DemiBold
                font.features: ({"tnum": 1})
            }
        }
    }
    Loader {
        id: decision; anchors.fill: parent; active: page.host.focusDecisionOpen
        sourceComponent: NotchFocusDecision { host: page.host; tools: page.tools; onDismissed: page.host.transitionAction(function(){page.host.focusDecisionOpen=false;}) }
    }
    NotchSettingsPopup {
        id: settingsMenu; objectName: "notchPomodoro"; host: page.host; control: settingsButton
        property bool advanced: false
        title: "Timer settings"; subtitle: "Durations in minutes"
        acceptable: [focusInput,shortInput,longInput,quickInput,customInput,cyclesInput].every(f=>f.acceptableInput)
        onAboutToShow: {advanced=false;focusInput.text=String(page.tools.settings.focus);shortInput.text=String(page.tools.settings.short);longInput.text=String(page.tools.settings.long);quickInput.text=String(page.tools.settings.quick);customInput.text=String(page.tools.settings.custom);cyclesInput.text=String(page.tools.settings.cycles);}
        onSaveRequested: page.saveSettings()
        NotchSettingsField { id:focusInput;fieldName:"notchFocusMinutes";menu:settingsMenu;label:"Focus";validator:IntValidator {bottom:1;top:180} }
        NotchSettingsField { id:shortInput;menu:settingsMenu;label:"Break";validator:IntValidator {bottom:1;top:60} }
        NotchSettingsField { id:cyclesInput;menu:settingsMenu;label:"Sessions per cycle";validator:IntValidator {bottom:2;top:12} }
        NotchPomodoroButton {
            reducedMotion: page.host.reducedMotion
            objectName: "notchPomodoroAdvanced"; text: settingsMenu.advanced ? "Fewer options" : "More options"; symbol: "settings"; family: page.host.family
            onClicked: settingsMenu.advanced = !settingsMenu.advanced
        }
        Column {
            width: parent.width; spacing: 8; visible: settingsMenu.advanced
            NotchSettingsField { id:longInput;menu:settingsMenu;label:"Long break";validator:IntValidator {bottom:1;top:120} }
            NotchSettingsField { id:quickInput;fieldName:"notchQuickMinutes";menu:settingsMenu;label:"Quick Timer";validator:IntValidator {bottom:1;top:180} }
            NotchSettingsField { id:customInput;fieldName:"notchCustomMinutes";menu:settingsMenu;label:"Custom";validator:IntValidator {bottom:1;top:180} }
            Flow {
                width: parent.width; spacing: 6
                Repeater {
                    model: ["long", "quick", "custom"]
                    NotchPomodoroButton {
                        reducedMotion: page.host.reducedMotion
                        required property string modelData
                        objectName: "notchPreset" + modelData
                        text: Style.name(modelData); symbol: Style.icon(modelData); family: page.host.family
                        onClicked: { page.tools.setPhase(modelData); settingsMenu.close(); }
                    }
                }
            }
            NotchPomodoroButton {
                reducedMotion: page.host.reducedMotion
                objectName: "notchFocusDecision"; text: "Focus activities"; symbol: "pomoCustom"; family: page.host.family
                onClicked: {settingsMenu.close(); page.host.transitionAction(function(){page.host.focusDecisionOpen=true;});}
            }
            NotchPomodoroButton {
                reducedMotion: page.host.reducedMotion
                objectName: "notchPomodoroLayout"; text: page.tools.pomodoro.targetsOpen ? "Hide focus targets" : "Choose focus target"; symbol: "toolTodo"; family: page.host.family
                onClicked: page.tools.setPomodoroLayout(!page.tools.pomodoro.targetsOpen)
            }
            NotchFocusTargets { width: parent.width; height: 178; visible: page.tools.pomodoro.targetsOpen; host: page.host; tools: page.tools }
        }
    }
}
