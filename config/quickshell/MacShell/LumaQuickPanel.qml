pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

FocusScope {
    id: root
    required property var controller
    property bool dark: true
    property string fontFamily: "SF Pro Text"
    property color accent: "#007aff"
    property bool externalSurface: false
    property real revealProgress: 1
    readonly property real inputReveal: reveal(0.06, 0.32)
    readonly property real contentReveal: reveal(0.45, 0.86)
    property real maxBodyHeight: 420
    readonly property real inputHeight: 44
    readonly property real bodyY: 52
    readonly property string lastPrompt: {
        for (let i = controller.messages.length - 1; i >= 0; i--)
            if (controller.messages[i].role === "user") return controller.messages[i].content;
        return "";
    }
    readonly property string answer: {
        if (controller.response) return controller.response;
        const messages = controller.messages;
        if (messages.length && messages[messages.length - 1].role === "assistant") return messages[messages.length - 1].content;
        return "";
    }
    readonly property string bodyText: {
        if (!controller.connected) return "Connecting to Luma AI…";
        if (!controller.ready) return "Install a local model to start chatting. Your conversations stay on this device.";
        if (answer) return answer;
        if (controller.busy) return controller.stage || "Thinking…";
        return "Ask a question, get help writing, or open an app.\n\nTry “Buka terminal” or “Bantu saya menulis email singkat”.";
    }
    readonly property color foreground: dark ? "#F5F5F7" : "#1D1D1F"
    readonly property color secondary: dark ? "#b4b4bc" : "#66666f"
    readonly property real bodyHeight: Math.min(maxBodyHeight, Math.max(174, bodyColumn.implicitHeight + footer.height + 36))
    width: 360
    height: bodyY + bodyHeight
    signal dismissed()
    signal fullRequested()
    signal settingsRequested()

    function reveal(start, end) {
        const t = Math.max(0, Math.min(1, (revealProgress - start) / (end - start)));
        return t * t * (3 - 2 * t);
    }

    component PanelButton: Button {
        id: button
        required property color foreground
        required property color hoverColor
        contentItem: Text { text: button.text; color: button.foreground; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 6; color: button.hovered || button.down ? button.hoverColor : "transparent" }
        leftPadding: 7; rightPadding: 7
    }

    function focusInput() { if (input.enabled) input.forceActiveFocus(); else forceActiveFocus(); }
    function submit() { controller.submit(); input.forceActiveFocus(); }
    Keys.onEscapePressed: event => { dismissed(); event.accepted = true; }

    Rectangle {
        width: parent.width; height: root.inputHeight; radius: 22
        visible: !root.externalSurface
        color: root.dark ? "#e6323239" : "#edf5f5fa"
        border.width: 1; border.color: root.dark ? "#515159" : "#ffffff"
    }
    Image {
        x: 12; y: 12; width: 20; height: 20
        opacity: root.inputReveal
        source: Qt.resolvedUrl("assets/luma-ai-circle.svg")
        sourceSize: Qt.size(80, 80)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
    TextField {
        id: input
        opacity: root.inputReveal
        x: 40; y: 1; width: parent.width - 82; height: root.inputHeight - 2
        text: root.controller.draft
        onTextChanged: root.controller.draft = text
        placeholderText: "Type to Luma AI"
        placeholderTextColor: root.secondary
        color: root.foreground
        selectionColor: root.accent
        font.family: root.fontFamily; font.pixelSize: 14
        background: null
        leftPadding: 0; rightPadding: 0
        enabled: root.controller.ready && !root.controller.busy
        selectByMouse: true
        maximumLength: 3500
        onAccepted: root.submit()
        Accessible.name: "Message Luma AI"
    }
    RoundButton {
        id: sendButton
        opacity: root.inputReveal
        x: parent.width - 37; y: 7; width: 30; height: 30
        text: root.controller.busy ? "■" : "↑"
        font.pixelSize: 17
        enabled: root.controller.busy !== "" || (root.controller.ready && root.controller.draft.trim() !== "")
        Accessible.name: root.controller.busy ? "Stop response" : "Send message"
        onClicked: root.controller.busy ? root.controller.send({action: "stop"}) : root.submit()
        contentItem: Text { text: sendButton.text; color: root.foreground; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 17 }
        background: Rectangle { radius: 15; color: root.dark ? "#255c5c65" : "#15000000" }
    }
    Rectangle {
        y: root.bodyY; width: parent.width; height: root.bodyHeight; radius: 18
        visible: !root.externalSurface
        color: root.dark ? "#ec303037" : "#f0f0f0f7"
        border.width: 1; border.color: root.dark ? "#515159" : "#ffffff"
    }
    Flickable {
        id: scroll
        x: 18; y: root.bodyY + 16 + 12 * (1 - root.contentReveal); width: parent.width - 36
        opacity: root.contentReveal
        height: root.bodyHeight - 32 - footer.height
        clip: true; contentWidth: width; contentHeight: bodyColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        Column {
            id: bodyColumn
            width: scroll.width; spacing: 10
            Text {
                visible: root.lastPrompt !== ""
                width: parent.width; text: root.lastPrompt
                color: root.secondary; font.family: root.fontFamily; font.pixelSize: 12
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            TextEdit {
                width: parent.width; height: contentHeight
                text: root.bodyText; color: root.foreground
                font.family: root.fontFamily; font.pixelSize: 14
                wrapMode: TextEdit.Wrap; readOnly: true; selectByMouse: true
                textFormat: TextEdit.PlainText
                selectionColor: root.accent
            }
            Text {
                visible: root.controller.error !== ""
                width: parent.width; text: root.controller.error
                color: root.dark ? "#ffabab" : "#a52d2d"
                font.family: root.fontFamily; font.pixelSize: 12; wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }
            PanelButton {
                visible: !root.controller.ready && root.controller.connected
                foreground: root.accent; hoverColor: root.dark ? "#20ffffff" : "#15000000"
                text: "Install in Settings"; onClicked: root.settingsRequested()
            }
        }
    }
    Row {
        id: footer
        opacity: root.contentReveal
        x: 16; y: root.bodyY + root.bodyHeight - height - 10
        width: parent.width - 32; height: 25; spacing: 8
        Text {
            width: Math.max(0, parent.width - fullButton.width - newButton.width - 16)
            anchors.verticalCenter: parent.verticalCenter
            text: "Luma AI · On device"; color: root.secondary
            font.family: root.fontFamily; font.pixelSize: 10; elide: Text.ElideRight
        }
        PanelButton {
            id: newButton
            foreground: root.secondary; hoverColor: root.dark ? "#20ffffff" : "#15000000"
            text: "+"; width: 27; height: 25
            enabled: !root.controller.busy
            Accessible.name: "New conversation"
            onClicked: { root.controller.send({action: "new"}); root.focusInput(); }
        }
        PanelButton { id: fullButton; foreground: root.secondary; hoverColor: root.dark ? "#20ffffff" : "#15000000"; text: "Open app ↗"; height: 25; onClicked: root.fullRequested() }
    }
    Connections {
        target: root.controller
        function onReadyChanged() { if (root.controller.ready) root.focusInput(); }
        function onBusyChanged() { if (!root.controller.busy) root.focusInput(); }
        function onMessagesChanged() { scroll.contentY = 0; }
        function onResponseChanged() { Qt.callLater(function() { scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height); }); }
    }
    Component.onCompleted: Qt.callLater(focusInput)
}
