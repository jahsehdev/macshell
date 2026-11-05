pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

FocusScope {
    id: root
    required property var controller
    property bool dark: true
    property string fontFamily: "sans-serif"
    property color accent: "#007aff"
    property bool externalSurface: false
    property bool microphoneActive: false
    property bool responseVisible: false
    property var previousMessages: null
    property real revealProgress: 1
    // Personal-context results (bin/context.py): shown while the draft is
    // being typed, before any Luma answer. Every row keeps its provenance.
    property var localResults: []
    property bool localSearching: false
    property int localSelected: -1
    signal localResultActivated(var result)
    readonly property real inputReveal: reveal(0.06, 0.32)
    readonly property real contentReveal: reveal(0.45, 0.86)
    property real maxBodyHeight: 420
    readonly property real inputHeight: 60
    readonly property real bodyY: 72
    readonly property string lastPrompt: {
        if (controller.messages === previousMessages) return "";
        for (let i = controller.messages.length - 1; i >= 0; i--)
            if (controller.messages[i].role === "user") return controller.messages[i].content;
        return "";
    }
    readonly property string answer: {
        if (controller.response) return controller.response;
        const messages = controller.messages;
        if (messages === previousMessages) return "";
        if (messages.length && messages[messages.length - 1].role === "assistant") return messages[messages.length - 1].content;
        return "";
    }
    readonly property string bodyText: {
        // While local results are showing, the hints step aside; the model
        // hint stays so "no model installed" is still explained.
        if (showLocal && !controller.busy)
            return controller.connected && !controller.ready
                   ? "Install a local model to start chatting. Your conversations stay on this device." : "";
        if (!controller.connected) return "Connecting to Luma AI…";
        if (!controller.ready) return "Install a local model to start chatting. Your conversations stay on this device.";
        if (answer) return answer;
        if (controller.busy) return controller.stage || "Thinking…";
        return "Ask a question, get help writing, or open an app.\n\nTry “Buka terminal” or “Bantu saya menulis email singkat”.";
    }
    readonly property color foreground: dark ? "#F5F5F7" : "#1D1D1F"
    readonly property color secondary: dark ? "#b4b4bc" : "#66666f"
    readonly property bool showLocal: !microphoneActive && controller.draft.trim() !== ""
                                      && (localResults.length > 0 || localSearching)
    // The card only appears for something that actually exists: a response
    // (or a prompt currently being answered), local matches while typing, an
    // error, or the explicit post-Enter "no model" hint. An idle menu with
    // conversation history no longer opens a message card.
    readonly property bool showBody: !microphoneActive && (showLocal || controller.error !== ""
        || (responseVisible && (answer !== "" || lastPrompt !== "" || controller.busy !== "" || !controller.ready)))
    onLocalResultsChanged: if (localSelected >= localResults.length) localSelected = localResults.length - 1
    readonly property real bodyHeight: Math.min(maxBodyHeight, Math.max(174, bodyColumn.implicitHeight + footer.height + 36))
    width: 380
    height: showBody ? bodyY + bodyHeight : inputHeight
    signal dismissed()
    signal fullRequested()
    signal settingsRequested()
    signal microphoneRequested()

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
    function resetMessages() { responseVisible = false; }
    function submit() {
        // A keyboard-selected local result opens first; Enter without a
        // selection still asks Luma.
        if (showLocal && localSelected >= 0 && localSelected < localResults.length) {
            localResultActivated(localResults[localSelected]);
            return;
        }
        if (controller.busy || controller.draft.trim() === "") return;
        if (!controller.ready) {
            // No model yet: keep the prompt visible next to the install hint
            // instead of silently swallowing Enter.
            responseVisible = true;
            return;
        }
        previousMessages = controller.messages;
        controller.submit();
        responseVisible = true;
        input.forceActiveFocus();
    }
    Keys.onEscapePressed: event => { dismissed(); event.accepted = true; }

    Rectangle {
        width: parent.width; height: root.inputHeight; radius: 30
        visible: !root.externalSurface
        color: root.dark ? "#e6323239" : "#edf5f5fa"
        border.width: 1; border.color: root.dark ? "#515159" : "#ffffff"
    }
    TextField {
        id: input
        objectName: "lumaSearchInput"
        opacity: root.inputReveal
        x: 24; y: 1; width: parent.width - 84; height: root.inputHeight - 2
        text: root.controller.draft
        onTextChanged: root.controller.draft = text
        placeholderText: "Search or Ask"
        placeholderTextColor: root.secondary
        color: root.foreground
        selectionColor: root.accent
        font.family: root.fontFamily; font.pixelSize: 15
        background: null
        // Warm gradient caret with a very soft bloom, instead of the flat
        // white bar. The ends are fully rounded (radius = half the width) and
        // the caret blinks with a smooth fade. Qt keeps this delegate's x/y
        // in sync with the text, including horizontal scrolling.
        cursorDelegate: Item {
            id: caret
            objectName: "lumaSearchCaret"
            width: 2.5
            property bool blinkOn: true
            opacity: input.activeFocus && input.enabled && blinkOn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.InOutQuad } }
            Timer {
                id: blinkTimer
                interval: 540; repeat: true; running: true
                onTriggered: caret.blinkOn = !caret.blinkOn
            }
            Connections {
                target: input
                // Stay solid while the user types or moves the caret.
                function onTextChanged() { caret.blinkOn = true; blinkTimer.restart(); }
                function onCursorPositionChanged() { caret.blinkOn = true; blinkTimer.restart(); }
                function onActiveFocusChanged() { if (input.activeFocus) { caret.blinkOn = true; blinkTimer.restart(); } }
                function onEnabledChanged() { if (input.enabled) { caret.blinkOn = true; blinkTimer.restart(); } }
            }
            // Stacked low-alpha rounded rects stand in for a blur pass so the
            // bloom also renders on the software backend.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.26; height: parent.height * 0.80
                width: 13; radius: width / 2; color: "#0fffc287"
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.34; height: parent.height * 0.72
                width: 7.5; radius: width / 2; color: "#1cffc890"
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.44; height: parent.height * 0.60
                width: 4.5; radius: width / 2; color: "#33ffd0a0"
            }
            Rectangle {
                anchors.fill: parent; radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.dark ? "#ffffffff" : "#ff1d1d1f" }
                    GradientStop { position: 0.68; color: root.dark ? "#fff8ee" : "#ff35322e" }
                    GradientStop { position: 0.88; color: root.dark ? "#ffe3bd" : "#ff7a5326" }
                    GradientStop { position: 1.0; color: root.dark ? "#ffc27a" : "#ffa8601f" }
                }
            }
        }
        leftPadding: 0; rightPadding: 0
        // Typing must work even without an installed model: local context
        // results do not need inference, and the install hint explains the rest.
        enabled: !root.controller.busy
        selectByMouse: true
        maximumLength: 3500
        onAccepted: root.submit()
        Keys.onDownPressed: event => {
            if (root.showLocal && root.localResults.length > 0) {
                root.localSelected = Math.min(root.localResults.length - 1, root.localSelected + 1);
                event.accepted = true;
            }
        }
        Keys.onUpPressed: event => {
            if (root.showLocal && root.localResults.length > 0) {
                root.localSelected = Math.max(-1, root.localSelected - 1);
                event.accepted = true;
            }
        }
        Accessible.name: "Message Luma AI"
    }
    RoundButton {
        id: sendButton
        objectName: "lumaSearchSend"
        readonly property string iconState: root.controller.busy ? "stop" : (root.controller.draft.trim() !== "" ? "send" : "mic")
        opacity: root.inputReveal
        x: parent.width - 48; y: 14; width: 32; height: 32
        enabled: iconState === "mic" || root.controller.busy !== "" || root.controller.draft.trim() !== ""
        Accessible.name: iconState === "stop" ? "Stop response" : (iconState === "send" ? "Send message" : (root.microphoneActive ? "Stop microphone" : "Start microphone"))
        onClicked: {
            if (iconState === "mic") root.microphoneRequested();
            else if (root.controller.busy) root.controller.send({action: "stop"});
            else root.submit();
        }
        contentItem: Item {
            WGlyph {
                objectName: "lumaSearchMic"
                anchors.centerIn: parent; width: 18; height: 18
                visible: sendButton.iconState === "mic"
                kind: "mic"; color: root.microphoneActive ? "#79cfff" : root.secondary
            }
            Image {
                objectName: "lumaSearchSendIcon"
                anchors.centerIn: parent; width: 19; height: 19
                visible: sendButton.iconState === "send"
                source: Qt.resolvedUrl("assets/luma-send.svg")
                sourceSize: Qt.size(76, 76); smooth: true; mipmap: true
            }
            Rectangle {
                anchors.centerIn: parent; width: 10; height: 10; radius: 2
                visible: sendButton.iconState === "stop"; color: "#202024"
            }
        }
        background: Rectangle {
            radius: 16
            color: sendButton.iconState === "mic" ? "transparent" : (sendButton.down ? "#c7c7cc" : (sendButton.hovered ? "#ffffff" : "#ededf0"))
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
    Rectangle {
        y: root.bodyY; width: parent.width; height: root.bodyHeight; radius: 22
        visible: !root.externalSurface && root.showBody
        color: root.dark ? "#ec303037" : "#f0f0f0f7"
        border.width: 1; border.color: root.dark ? "#515159" : "#ffffff"
    }
    Flickable {
        id: scroll
        objectName: "lumaSearchAnswer"
        visible: root.showBody
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
                visible: root.lastPrompt !== "" && (root.answer !== "" || root.controller.busy !== "")
                width: parent.width; text: root.lastPrompt
                color: root.secondary; font.family: root.fontFamily; font.pixelSize: 12
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                visible: root.showLocal && root.localSearching && root.localResults.length === 0
                width: parent.width
                text: "Searching Notes, Calendar, and files…"
                color: root.secondary; font.family: root.fontFamily; font.pixelSize: 12
                wrapMode: Text.WordWrap; textFormat: Text.PlainText
            }
            // Local matches with provenance: kind chip, title, snippet with the
            // match highlighted, and the origin recorded at index time.
            Repeater {
                model: root.showLocal ? root.localResults : []
                delegate: Item {
                    id: resultRow
                    required property var modelData
                    required property int index
                    readonly property var provenance: modelData.provenance || {}
                    readonly property string sourceLabel: {
                        const origin = String(provenance.origin || "");
                        if (modelData.kind === "files") return origin || String(modelData.ref);
                        if (origin.indexOf("/") === 0) return ""; // internal db path is not a citable source
                        return origin ? origin.replace(/^macshell-/, "").replace(/^./, c => c.toUpperCase()) : "";
                    }
                    readonly property string kindLabel: ({
                        notes: "Notes", calendar: "Calendar", files: "File", mail: "Mail"
                    })[modelData.kind] || String(modelData.kind)
                    readonly property string kindTint: ({
                        notes: "#26ffb340", calendar: "#26ff6b6b", files: "#264da3ff", mail: "#269b7bff"
                    })[modelData.kind] || "#1fffffff"
                    readonly property string rowTitle: {
                        if (modelData.title && String(modelData.title) !== "") return String(modelData.title);
                        const ref = String(modelData.ref || "");
                        return ref.substring(ref.lastIndexOf("/") + 1) || "Untitled";
                    }
                    width: scroll.width; height: rowContent.implicitHeight + 16
                    Rectangle {
                        anchors.fill: parent; radius: 10
                        color: root.localSelected === resultRow.index
                               ? (root.dark ? "#1fffffff" : "#12000000") : "transparent"
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { root.localSelected = resultRow.index; root.localResultActivated(resultRow.modelData); }
                        Accessible.role: Accessible.Button
                        Accessible.name: resultRow.rowTitle + " (" + resultRow.kindLabel + ")"
                    }
                    Column {
                        id: rowContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 8; leftMargin: 4; rightMargin: 4 }
                        spacing: 3
                        Row {
                            width: parent.width; spacing: 8
                            Rectangle {
                                id: kindChip
                                radius: 5; color: resultRow.kindTint
                                width: chipText.width + 12; height: 18; anchors.verticalCenter: titleText.verticalCenter
                                Text {
                                    id: chipText; anchors.centerIn: parent
                                    text: resultRow.kindLabel; color: root.secondary
                                    font.pixelSize: 9; font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                id: titleText
                                width: parent.width - kindChip.width - 8
                                text: resultRow.rowTitle; color: root.foreground
                                font.family: root.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                                elide: Text.ElideRight; textFormat: Text.PlainText
                            }
                        }
                        Text {
                            width: parent.width
                            text: String(modelData.snippet || "").replace(/⟦/g, "**").replace(/⟧/g, "**")
                            visible: text !== ""
                            color: root.secondary; font.family: root.fontFamily; font.pixelSize: 12
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            textFormat: Text.MarkdownText
                        }
                        Text {
                            visible: resultRow.sourceLabel !== ""
                            width: parent.width
                            text: resultRow.sourceLabel + " · "
                                  + Qt.formatDate(new Date((modelData.modified || 0) * 1000), "d MMM yyyy")
                            color: root.secondary; opacity: 0.7
                            font.family: root.fontFamily; font.pixelSize: 10
                            elide: Text.ElideMiddle; textFormat: Text.PlainText
                        }
                    }
                }
            }
            Text {
                visible: root.showLocal && root.localResults.length > 0
                width: parent.width
                text: "Local results · ↑↓ to choose · ↵ opens"
                color: root.secondary; opacity: 0.6
                font.family: root.fontFamily; font.pixelSize: 10
                textFormat: Text.PlainText
            }
            TextEdit {
                width: parent.width; height: contentHeight
                visible: text !== ""
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
    Loader {
        id: playback
        active: false
        source: Qt.resolvedUrl("LumaPlayback.qml")
        onLoaded: item.start(root.answer)
    }
    Connections {
        target: playback.item
        function onErrorChanged() { if(playback.item.error) root.controller.error=playback.item.error; }
    }
    Row {
        id: footer
        visible: root.showBody
        opacity: root.contentReveal
        x: 16; y: root.bodyY + root.bodyHeight - height - 10
        width: parent.width - 32; height: 25; spacing: 8
        Text {
            width: Math.max(0, parent.width - fullButton.width - newButton.width - speakButton.width - 24)
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
            onClicked: { root.resetMessages(); root.controller.send({action: "new"}); root.focusInput(); }
        }
        PanelButton { id: speakButton; foreground: root.secondary; hoverColor: root.dark ? "#20ffffff" : "#15000000"; text: playback.item && playback.item.running ? "Stop voice" : "Read"; height: 25; enabled: root.answer !== ""; onClicked: { if(playback.item && playback.item.running) playback.item.stop(); else if(playback.item) playback.item.start(root.answer); else playback.active=true; } }
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
