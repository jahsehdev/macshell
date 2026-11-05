pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: page
    required property var host
    required property var tools
    readonly property bool configuring: settingsMenu.visible
    property bool remindDraft: true
    readonly property bool interacting: configuring
    readonly property real fraction: Math.min(1, tools.waterTotal / tools.settings.goal)
    readonly property int firstHour: Math.max(0, new Date(tools.nowMs).getHours() - 7)
    readonly property var hours: tools.waterHours.slice(firstHour, firstHour+8)
    readonly property real maxAmount: Math.max(250, Math.ceil(Math.max.apply(null, hours) / 250) * 250)
    function litres(ml) { return (ml / 1000).toFixed(ml % 1000 === 0 ? 0 : 1); }
    function saveSettings() {
        if (![goalInput,glassInput,reminderInput].every(f => f.acceptableInput)) return;
        tools.updateSettings({goal:Number(goalInput.text),glass:Number(glassInput.text),reminder:Number(reminderInput.text),remind:remindDraft});
        settingsMenu.close();
    }
    Item {
        anchors.fill: parent
        Item {
            width: 209; height: parent.height
            Row { y: 0; spacing: 4
                Text { text: page.litres(page.tools.waterTotal); color: "white"; font.family: page.host.family; font.pixelSize: 40; font.weight: Font.Bold }
                Text { text: "/ " + page.litres(page.tools.settings.goal) + " L"; anchors.baseline: parent.children[0].baseline; color: "#B9BCC5"; font.family: page.host.family; font.pixelSize: 15; font.weight: Font.Medium }
            }
            Text {
                y: 56; text: "Today · " + Math.round(page.fraction*100) + "%" + (page.fraction >= 1 ? " · Goal reached" : "")
                color: page.fraction >= 1 ? "#55CEF8" : "#B1B6C1"; font.family: page.host.family; font.pixelSize: 13
            }
            Rectangle { y: 84; width: parent.width-8; height: 6; radius: 3; color: "#253445"
                Rectangle { width: parent.width*page.fraction; height: parent.height; radius: 3; color: "#37BDF1" }
            }
            Row { y: 108; spacing: 8
                NotchToolButton { objectName: "notchDrink"; text: "Drink"; symbol: "toolWater"; fill: "#124E7E"; family: page.host.family; onClicked: page.tools.drink() }
                NotchToolButton { id:settingsButton; objectName:"notchWaterSettings"; symbol: "settings"; family: page.host.family; Accessible.name: "Water reminder settings"; onClicked: settingsMenu.open() }
                NotchToolButton { symbol: "undo"; family: page.host.family; enabled: page.tools.waterTotal > 0; Accessible.name: "Undo last drink"; onClicked: page.tools.undoDrink() }
            }
        }
        Rectangle { x: 222; y: 3; width: 1; height: 140; color: "#25FFFFFF" }
        Item {
            x: 236; y: 9; width: parent.width-x; height: 138
            Text { y: -6; text: "Today, by hour"; color: "#B1B6C1"; font.family: page.host.family; font.pixelSize: 12 }
            Row { x: 0; y: 17; height: 90; spacing: 5
                Repeater {
                    model: 8
                    Item {
                        required property int index
                        width: (page.width-236-42-35)/8; height: 90
                        Rectangle { anchors.fill: parent; radius: width/2; color: "#16191D" }
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width
                            height: Math.max(0, (page.hours[parent.index] || 0) / page.maxAmount * parent.height)
                            radius: width/2
                            gradient: Gradient { GradientStop { position:0; color:"#4DCEE5" } GradientStop { position:1; color:"#1262D6" } }
                        }
                        Text {
                            visible: parent.index === 0 || parent.index === 3 || parent.index === 7
                            anchors.horizontalCenter: parent.horizontalCenter; y: 98
                            text: String(page.firstHour + parent.index).padStart(2,"0")
                            color: "#A8AFBA"; font.family: page.host.family; font.pixelSize: 12
                        }
                    }
                }
            }
            Column { anchors.right: parent.right; y: 13; spacing: 29
                Text { text: page.maxAmount; color:"#A8AFBA"; font.family:page.host.family; font.pixelSize:12 }
                Text { text: page.maxAmount/2; color:"#A8AFBA"; font.family:page.host.family; font.pixelSize:12 }
                Text { text:"0 ml"; color:"#A8AFBA"; font.family:page.host.family; font.pixelSize:12 }
            }
        }
    }
    NotchSettingsPopup {
        id: settingsMenu
        objectName: "notchWater"
        host: page.host; control: settingsButton
        title: "Water reminder settings"
        subtitle: "Daily goal, drink size and reminders"
        acceptable: [goalInput, glassInput, reminderInput].every(f => f.acceptableInput)
        onAboutToShow: {
            goalInput.text = String(page.tools.settings.goal);
            glassInput.text = String(page.tools.settings.glass);
            reminderInput.text = String(page.tools.settings.reminder);
            page.remindDraft = page.tools.settings.remind;
        }
        onSaveRequested: page.saveSettings()
        NotchSettingsField { id: goalInput; fieldName: "notchWaterGoal"; menu: settingsMenu; label: "Daily goal · ml"; validator: IntValidator { bottom: 100; top: 10000 } }
        NotchSettingsField { id: glassInput; menu: settingsMenu; label: "Each drink · ml"; validator: IntValidator { bottom: 25; top: 2000 } }
        NotchSettingsField { id: reminderInput; menu: settingsMenu; label: "Remind every · min"; validator: IntValidator { bottom: 5; top: 240 } }
        NotchToolButton {
            objectName: "notchWaterReminders"
            symbol: page.remindDraft ? "bell" : "bellOff"; family: page.host.family
            text: "Reminders " + (page.remindDraft ? "on" : "off")
            ink: settingsMenu.foreground; fill: settingsMenu.dark ? "#15FFFFFF" : "#10000000"
            onClicked: page.remindDraft = !page.remindDraft
        }
    }
}
