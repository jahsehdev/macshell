pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "Common" as Common

Window {
    id: win
    required property var controller
    required property var hub
    readonly property bool dark: hub && hub.dock ? hub.dock.darkMode : true
    readonly property string family: hub && hub.dock ? hub.dock.fontFamily : "sans-serif"
    property string deleting: ""
    title: "Luma AI"
    width: 820; height: 610
    minimumWidth: 600; minimumHeight: 440
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    visible: false
    property int floatTries: 0
    onVisibleChanged: if (visible) { floatTries = 0; floatTimer.restart(); }
    Timer {
        id: floatTimer; interval: 140; repeat: true
        onTriggered: {
            if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
                const selector = 'window = "title:^(Luma AI)$"';
                Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + selector + ' })');
                if (win.floatTries === 1) Hyprland.dispatch('hl.dsp.window.center({ ' + selector + ' })');
            }
            if (++win.floatTries >= 4) stop();
        }
    }

    function open() {
        if (!visible && screen) {
            x = screen.virtualX + (screen.width - width) / 2;
            y = screen.virtualY + (screen.height - height) / 2;
        }
        show(); raise(); requestActivate();
        Qt.callLater(function() { input.forceActiveFocus(); });
    }
    function bottom() { Qt.callLater(function() { scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height); }); }
    Shortcut { sequences: ["Escape", "Ctrl+W"]; enabled: win.visible; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+N"; enabled: win.visible && !win.controller.busy; onActivated: win.controller.send({action: "new"}) }
    Connections {
        target: win.controller
        function onMessagesChanged() { win.bottom(); }
        function onResponseChanged() { win.bottom(); }
    }
    QtObject {
        id: lumaPalette
        readonly property string fam: win.family
        readonly property color text: win.dark ? "#F5F5F7" : "#1D1D1F"
        readonly property color text2: win.dark ? "#a8a8ad" : "#69696f"
        readonly property color accent: win.hub && win.hub.dock ? win.hub.dock.accent : "#007aff"
        readonly property color button: win.dark ? "#424246" : "#ffffff"
        readonly property color buttonPressed: win.dark ? "#55555a" : "#e4e4e7"
        readonly property color buttonBorder: win.dark ? "#555559" : "#d4d4d8"
    }
    Common.ContinuousRectangle {
        anchors.fill: parent; radius: 18; cornerSmoothing: 0
        color: win.dark ? "#252527" : "#f4f4f6"
        border.width: 1; border.color: lumaPalette.buttonBorder
        Item {
            id: titlebar; width: parent.width; height: 51
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            WindowControls {
                x: 15; anchors.verticalCenter: parent.verticalCenter
                dark: win.dark; windowActive: win.active
                onCloseClicked: win.close()
                onMinimizeClicked: {
                    if (win.hub && win.hub.dock && win.hub.dock.minimize)
                        win.hub.dock.minimize.minimizeFocused();
                    else win.showMinimized();
                }
                onZoomClicked: if (win.visibility === Window.Maximized) win.showNormal(); else win.showMaximized()
            }
            Row {
                anchors.centerIn: parent
                spacing: 6
                Image { width: 26; height: 26; source: Qt.resolvedUrl("assets/luma-ai.png"); sourceSize: Qt.size(78, 78); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Luma AI"; color: lumaPalette.text; font.family: win.family; font.pixelSize: 14; font.weight: Font.DemiBold }
            }
            LumaButton { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; t: lumaPalette; text: "Settings"; onClicked: win.controller.settings() }
        }
        Rectangle {
            id: sidebar; x: 10; y: titlebar.height; width: win.width >= 760 ? 194 : 150
            height: parent.height - y - 10; radius: 12
            color: win.dark ? "#1f1f21" : "#e8e8ed"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 10
                LumaButton { t: lumaPalette; text: "+  New conversation"; enabled: !win.controller.busy; Layout.fillWidth: true; onClicked: win.controller.send({action: "new"}) }
                Text { text: "ON THIS DEVICE"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 10; font.letterSpacing: 1 }
                ListView {
                    id: historyList
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 5; model: win.controller.conversations
                    delegate: Rectangle {
                        id: conversationRow
                        required property var modelData
                        width: historyList.width; height: 56; radius: 8
                        color: win.controller.currentConversation === conversationRow.modelData.id ? (win.dark ? "#404046" : "#d5d5df") : "transparent"
                        Text { x: 9; y: 7; width: parent.width - 18; text: conversationRow.modelData.title; color: lumaPalette.text; font.family: win.family; font.pixelSize: 12; elide: Text.ElideRight }
                        Text { x: 9; y: 31; text: win.deleting === conversationRow.modelData.id ? "Delete? Click again" : "Delete"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 10
                            MouseArea { anchors.fill: parent; enabled: !win.controller.busy; cursorShape: Qt.PointingHandCursor; onClicked: { if (win.deleting === conversationRow.modelData.id) { win.controller.send({action: "delete", id: conversationRow.modelData.id}); win.deleting = ""; } else win.deleting = conversationRow.modelData.id; } }
                        }
                        MouseArea { x: 0; y: 0; width: parent.width; height: 29; enabled: !win.controller.busy; cursorShape: Qt.PointingHandCursor; onClicked: { win.deleting = ""; win.controller.send({action: "conversation", id: conversationRow.modelData.id}); } }
                    }
                    ScrollBar.vertical: ScrollBar {}
                }
                Text { text: win.controller.loaded ? "● Model in memory" : "○ Model unloaded"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 10 }
                Text { text: "Private · Local · Offline"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 10 }
            }
        }
        ColumnLayout {
            x: sidebar.x + sidebar.width + 18; y: titlebar.height + 8
            width: parent.width - x - 20; height: parent.height - y - 16; spacing: 10
            Flickable {
                id: scroll
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: conversationColumn.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Column {
                    id: conversationColumn
                    width: scroll.width - 12; spacing: 20
                    Column {
                        width: parent.width; spacing: 14
                        visible: win.controller.messages.length === 0 && win.controller.response === ""
                        Item { width: 1; height: 28 }
                        Image { width: 88; height: 88; source: Qt.resolvedUrl("assets/luma-ai.png"); sourceSize: Qt.size(264, 264); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.horizontalCenter: parent.horizontalCenter }
                        Text { width: parent.width; text: win.controller.ready ? "What can I help you with?" : "Meet Luma AI"; horizontalAlignment: Text.AlignHCenter; color: lumaPalette.text; font.family: win.family; font.pixelSize: 25; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                        Text { width: parent.width; text: win.controller.ready ? "Ask a question, shape an idea, or get a little help with your day." : "Your local assistant for MacShell. Install a model in Settings to start chatting."; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 13 }
                        LumaButton { anchors.horizontalCenter: parent.horizontalCenter; t: lumaPalette; text: "Install in Settings"; primary: true; visible: !win.controller.ready; onClicked: win.controller.settings() }
                        Repeater {
                            model: win.controller.ready ? ["Bantu saya menulis email singkat", "Jelaskan sesuatu dengan sederhana", "Buka terminal"] : []
                            delegate: LumaButton { id: suggestion; required property string modelData; t: lumaPalette; text: suggestion.modelData; anchors.horizontalCenter: parent.horizontalCenter; onClicked: { win.controller.draft = suggestion.modelData; input.forceActiveFocus(); } }
                        }
                    }
                    Repeater {
                        model: win.controller.messages
                        delegate: Column {
                            id: message
                            required property var modelData
                            width: parent.width; spacing: 6
                            Text { text: message.modelData.role === "user" ? "YOU" : "LUMA AI"; color: message.modelData.role === "user" ? lumaPalette.text2 : lumaPalette.accent; font.family: win.family; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1 }
                            TextEdit { width: parent.width; height: contentHeight; text: message.modelData.content; color: lumaPalette.text; font.family: win.family; font.pixelSize: 14; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText; selectionColor: lumaPalette.accent }
                            LumaButton { t: lumaPalette; text: "Copy"; visible: message.modelData.role === "assistant"; onClicked: { copyBuffer.text = message.modelData.content; copyBuffer.selectAll(); copyBuffer.copy(); } }
                        }
                    }
                    Column {
                        visible: win.controller.response !== ""; width: parent.width; spacing: 6
                        Text { text: "LUMA AI"; color: lumaPalette.accent; font.family: win.family; font.pixelSize: 10; font.weight: Font.DemiBold }
                        TextEdit { width: parent.width; height: contentHeight; text: win.controller.response; color: lumaPalette.text; font.family: win.family; font.pixelSize: 14; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText }
                    }
                    Item { width: 1; height: 12 }
                }
            }
            Text { visible: win.controller.error !== ""; text: win.controller.error; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: win.dark ? "#ff9696" : "#b62626"; font.family: win.family; font.pixelSize: 12 }
            Text { visible: win.controller.busy !== ""; text: win.controller.stage || "Working…"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: Math.min(128, Math.max(58, input.contentHeight + 24)); radius: 14
                color: win.dark ? "#343437" : "#ffffff"; border.width: input.activeFocus ? 2 : 1; border.color: input.activeFocus ? lumaPalette.accent : lumaPalette.buttonBorder
                ScrollView {
                    anchors.fill: parent; anchors.margins: 10; contentWidth: availableWidth
                    TextArea {
                        id: input; text: win.controller.draft; onTextChanged: win.controller.draft = text
                        enabled: win.controller.ready && !win.controller.busy
                        placeholderText: win.controller.ready ? "Message Luma AI…" : "Install a model to get started"
                        placeholderTextColor: lumaPalette.text2; color: lumaPalette.text
                        font.family: win.family; font.pixelSize: 14
                        wrapMode: TextEdit.Wrap; selectByMouse: true; background: null
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                win.controller.submit(); event.accepted = true;
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Enter to send · Shift+Enter for a new line"; color: lumaPalette.text2; font.family: win.family; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                LumaButton { t: lumaPalette; text: win.controller.busy ? "Stop" : "Send ↑"; primary: true; enabled: win.controller.busy !== "" || (win.controller.ready && win.controller.draft.trim() !== ""); onClicked: win.controller.busy ? win.controller.send({action: "stop"}) : win.controller.submit() }
            }
        }
        TextEdit { id: copyBuffer; visible: false }
        MouseArea { x: parent.width - 12; y: parent.height - 12; width: 12; height: 12; cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }
    }
}
