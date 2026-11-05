pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "EmojiData.js" as Emojis

FocusScope {
    id: panel
    required property string folderPath
    property bool dark: false
    property string fontFamily: "sans-serif"
    property real pointerY: 124
    property bool tailOnLeft: false
    property real availableWidth: width + 58
    property bool demo: false
    property string name: ""
    property string colorValue: "#0a84ff"
    property string symbolValue: ""
    property string emojiValue: ""
    property string iconUrl: ""
    property var symbols: []
    property bool ready: false
    property bool busy: false
    property bool customized: false
    property string error: ""
    property var confirmedSettings: null
    property int emojiCategory: -1
    property string emojiQuery: ""
    property var recentEmoji: []
    readonly property var colors: ["#ffd43b", "#ff453a", "#ff9f0a", "#30c85a", "#0a84ff", "#bf5af2", "#929296"]
    readonly property var groups: ["Food & Drinks", "Activity", "Work & Study", "Nature & Places"]
    readonly property color foreground: dark ? "#eeeeef" : "#39393d"
    readonly property color secondary: dark ? "#b4b4ba" : "#77777c"
    readonly property var visibleEmoji: {
        const query = emojiQuery.trim().toLowerCase();
        return Emojis.list.filter(function(entry) {
            return (!query && emojiCategory === -2 ? recentEmoji.indexOf(entry[0]) >= 0 :
                    (query !== "" || emojiCategory < 0 || entry[3] === emojiCategory))
                && (!query || entry[4].indexOf(query) >= 0 || entry[0] === query);
        });
    }
    signal dismissed()
    signal changed()
    signal stateLoaded()
    width: 360
    height: 620
    focus: true

    function settings() { return { color: colorValue, symbol: symbolValue, emoji: emojiValue }; }
    function send(request) {
        error = "";
        if (demo) { customized = request.action !== "clear"; busy = false; changed(); return; }
        if (!worker.running || !ready) return;
        busy = true;
        worker.write(JSON.stringify(request) + "\n");
    }
    function applyColor(value) { colorValue = value; send({ action: "apply", settings: settings() }); }
    function applySymbol(value) {
        symbolValue = value === symbolValue ? "" : value; emojiValue = "";
        send({ action: "apply", settings: settings() });
    }
    function applyEmoji(value) {
        emojiValue = value; symbolValue = "";
        recentEmoji = [value].concat(recentEmoji.filter(function(e) { return e !== value; })).slice(0, 24);
        recents.setText(JSON.stringify(recentEmoji));
        send({ action: "apply", settings: settings() });
        emojiPicker.close();
    }
    function clear() {
        if (demo) { symbolValue = ""; emojiValue = ""; }
        send({ action: "clear" });
    }
    function symbolsIn(category) { return symbols.filter(function(s) { return s.category === category; }); }
    function symbolSource(symbol, color) {
        return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(symbol.svg
            .replace('viewBox="0 0 24 24"', 'viewBox="-2 -2 28 28"').replace(/\$COLOR/g, color));
    }
    function showEmojiPicker() { emojiPicker.open(); emojiSearch.forceActiveFocus(); }
    Keys.onEscapePressed: event => {
        if (emojiPicker.opened) emojiPicker.close();
        else if (colorPicker.opened) colorPicker.close();
        else dismissed();
        event.accepted = true;
    }

    FileView {
        id: recents
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/macshell/folder-emoji-recents.json"
        printErrors: false
        atomicWrites: true
        onLoaded: { try { const values = JSON.parse(text()); if (Array.isArray(values)) panel.recentEmoji = values.filter(v => typeof v === "string").slice(0, 24); } catch (e) {} }
    }
    Process {
        id: worker
        command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("bin/folder_customizer.py").toString().replace("file://", "")), "--serve", "--folder", panel.folderPath]
        running: panel.folderPath !== "" && !panel.demo
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const state = JSON.parse(line);
                    panel.busy = false;
                    if (state.event === "error") {
                        panel.error = state.message;
                        if (panel.confirmedSettings) {
                            panel.colorValue = panel.confirmedSettings.color;
                            panel.symbolValue = panel.confirmedSettings.symbol;
                            panel.emojiValue = panel.confirmedSettings.emoji;
                        }
                        return;
                    }
                    if (state.event === "state") {
                        panel.name = state.name; panel.colorValue = state.settings.color;
                        panel.symbolValue = state.settings.symbol; panel.emojiValue = state.settings.emoji;
                        panel.confirmedSettings = state.settings;
                        panel.iconUrl = state.icon; panel.symbols = state.symbols;
                        panel.customized = state.customized;
                        const first = !panel.ready;
                        panel.ready = true;
                        if (first) panel.stateLoaded(); else panel.changed();
                    }
                } catch (e) { panel.error = "Could not read the folder customization response."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("[folder-customizer]", text.trim()) }
        onExited: (code, status) => { panel.busy = false; if (code !== 0 && !panel.error) panel.error = "The folder customization service could not start."; }
    }

    FolderPopoverSurface {
        id: material
        objectName: "folderPopoverSurface"
        x: panel.tailOnLeft ? -tailLength : 0
        bodyWidth: panel.width
        height: panel.height
        dark: panel.dark
        pointerY: panel.pointerY
        tailOnLeft: panel.tailOnLeft
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: panel.forceActiveFocus() }
    Image {
        id: preview
        objectName: "folderPreview"
        x: (parent.width - width) / 2; y: 15; width: 112; height: 112
        source: panel.iconUrl
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true
    }
    Text {
        x: 24; y: 130; width: parent.width - 48; height: 24
        text: panel.name || "Customize Folder"
        color: panel.foreground
        font.family: panel.fontFamily; font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
    }
    Row {
        id: palette
        x: 13; y: 166; spacing: 8
        FolderButton {
            id: restoreButton
            width: 25; height: 29; hint: "Restore the original folder icon"
            dark: panel.dark; subtle: true
            enabled: panel.ready && !panel.busy && panel.customized
            contentItem: Item {
                Image {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    sourceSize: Qt.size(60, 60)
                    opacity: restoreButton.enabled ? 1 : 0.4
                    source: panel.symbolSource({ svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="$COLOR" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3h9l9 9q1 1 0 2l-7 7q-1 1-2 0l-9-9ZM9 7a2 2 0 1 1-4 0 2 2 0 1 1 4 0"/></svg>' }, panel.secondary)
                }
            }
            onClicked: panel.clear()
        }
        Repeater {
            model: panel.colors
            delegate: Button {
                id: swatch
                required property string modelData
                width: 27; height: 29
                enabled: panel.ready && !panel.busy
                Accessible.name: "Folder color " + modelData
                background: Rectangle {
                    anchors.centerIn: parent; width: 27; height: 27; radius: 14
                    color: swatch.modelData
                    border.width: swatch.activeFocus ? 2 : 1
                    border.color: swatch.activeFocus ? "#347cff" : "#25000000"
                }
                contentItem: Text {
                    text: panel.colorValue.toLowerCase() === swatch.modelData ? "✓" : ""
                    color: "white"; font.pixelSize: 22
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                onClicked: panel.applyColor(modelData)
            }
        }
        FolderButton {
            objectName: "customColorButton"
            width: 29; height: 29; text: "+"; hint: "Choose a custom color"; font.pixelSize: 22
            dark: panel.dark; enabled: panel.ready && !panel.busy
            onClicked: { hexField.text = panel.colorValue; colorPicker.open(); }
        }
    }
    Rectangle { x: 1; y: 216; width: parent.width - 2; height: 1; color: panel.dark ? "#30ffffff" : "#20000000" }
    Flickable {
        id: symbolScroll
        objectName: "symbolScroll"
        x: 10; y: 225; width: parent.width - 20; height: parent.height - y - 46
        clip: true; contentHeight: symbolColumn.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: symbolColumn
            width: symbolScroll.width - 5
            spacing: 17
            Repeater {
                model: panel.groups
                delegate: Column {
                    id: category
                    required property string modelData
                    width: symbolColumn.width; spacing: 3
                    Text {
                        x: 2; text: category.modelData; color: panel.foreground
                        font.family: panel.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold
                        height: 22
                    }
                    Grid {
                        columns: 7; columnSpacing: 1; rowSpacing: 4
                        Repeater {
                            model: panel.symbolsIn(category.modelData)
                            delegate: FolderButton {
                                id: symbolButton
                                required property var modelData
                                width: 46; height: 44; subtle: true; round: true; dark: panel.dark
                                hint: modelData.label; selected: panel.symbolValue === modelData.id
                                enabled: panel.ready && !panel.busy
                                contentItem: Item {
                                    Image {
                                        source: panel.symbolSource(symbolButton.modelData, symbolButton.selected ? "#347cff" : panel.dark ? "#bcbcc2" : "#77777b")
                                        sourceSize: Qt.size(72, 72); fillMode: Image.PreserveAspectFit
                                        anchors.centerIn: parent; width: 25; height: 25
                                    }
                                }
                                onClicked: panel.applySymbol(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle { x: 1; y: parent.height - 44; width: parent.width - 2; height: 43; color: panel.dark ? "#f0323237" : "#f0ededf0"; radius: 15 }
    Row {
        x: 10; y: parent.height - 35; spacing: 10
        FolderButton {
            objectName: "clearFolderButton"
            width: 165; height: 27; text: "Clear"; dark: panel.dark
            enabled: panel.ready && !panel.busy && panel.customized
            onClicked: panel.clear()
        }
        FolderButton {
            objectName: "emojiButton"
            width: 165; height: 27; text: "☻  Emoji"; dark: panel.dark
            enabled: panel.ready && !panel.busy
            onClicked: panel.showEmojiPicker()
        }
    }
    Rectangle {
        x: 10; y: parent.height - 104; width: parent.width - 20
        height: errorLabel.implicitHeight + 18; radius: 8
        color: panel.dark ? "#552b2b" : "#ffe4e2"; visible: panel.error !== ""
        Text {
            id: errorLabel
            x: 9; y: 9; width: parent.width - 18
            text: panel.error; color: panel.dark ? "#ffceca" : "#9e2921"
            wrapMode: Text.Wrap; font.pixelSize: 12
        }
    }
    BusyIndicator { anchors.centerIn: parent; running: !panel.ready && !panel.error; visible: running }

    Popup {
        id: emojiPicker
        objectName: "emojiPicker"
        x: Math.max(0, Math.min(58, panel.availableWidth - width))
        y: Math.max(10, Math.min(221, panel.height - height - 10))
        width: 330; height: Math.min(427, panel.height - 20)
        padding: 10
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 15; color: panel.dark ? "#f03a3a40" : "#f5f3f3f5"
            border.width: 1; border.color: panel.dark ? "#70ffffff" : "#40000000"
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.5; shadowColor: "#55000000"; shadowVerticalOffset: 5 }
        }
        contentItem: Item {
            TextField {
                id: emojiSearch
                objectName: "emojiSearch"
                x: 0; y: 0; width: parent.width; height: 31
                placeholderText: "Search"; selectByMouse: true
                color: panel.foreground
                leftPadding: 26; font.pixelSize: 13
                background: Rectangle { color: panel.dark ? "#25252a" : "white"; radius: 16; border.color: emojiSearch.activeFocus ? "#5aa0ff" : "#99999f"; border.width: emojiSearch.activeFocus ? 3 : 1 }
                Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "⌕"; color: panel.secondary; font.pixelSize: 18 }
                onTextChanged: panel.emojiQuery = text
                Keys.onDownPressed: emojiGrid.forceActiveFocus()
                Keys.onEscapePressed: emojiPicker.close()
            }
            GridView {
                id: emojiGrid
                objectName: "emojiGrid"
                x: 3; y: 40; width: parent.width - 3; height: parent.height - y - 31
                cellWidth: 49; cellHeight: 43
                clip: true; model: panel.visibleEmoji
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: 0
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: FolderButton {
                    required property var modelData
                    width: 45; height: 40; subtle: true; dark: panel.dark
                    text: modelData[0]; hint: modelData[1]
                    font.family: "Noto Color Emoji"; font.pixelSize: 28
                    onClicked: panel.applyEmoji(modelData[0])
                }
                Keys.onReturnPressed: if (count) panel.applyEmoji(panel.visibleEmoji[currentIndex][0])
            }
            Text {
                anchors.centerIn: emojiGrid; visible: emojiGrid.count === 0
                text: panel.emojiCategory === -2 ? "No recent emoji" : "No emoji found"
                color: panel.secondary; font.pixelSize: 13
            }
            Row {
                y: parent.height - 25; spacing: 1
                Repeater {
                    model: ["◷", "☻", "♙", "♧", "♨", "⌂", "⚽", "♧", "♡", "⚑"]
                    delegate: FolderButton {
                        required property string modelData
                        required property int index
                        width: 30; height: 25; text: modelData; subtle: true; dark: panel.dark
                        selected: panel.emojiCategory === (index === 0 ? -2 : index - 1)
                        hint: index === 0 ? "Recently used" : Emojis.categories[index - 1]
                        font.pixelSize: 17
                        onClicked: { panel.emojiCategory = index === 0 ? -2 : index - 1; emojiSearch.text = ""; emojiGrid.positionViewAtBeginning(); }
                    }
                }
            }
        }
    }
    Popup {
        id: colorPicker
        objectName: "customColorPicker"
        x: 35; y: 202; width: 290; height: 168; padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 14; color: panel.dark ? "#38383e" : "#f7f7f9"; border.color: "#60909096" }
        contentItem: Column {
            spacing: 12
            Text { text: "Custom folder color"; color: panel.foreground; font.pixelSize: 14; font.weight: Font.DemiBold }
            Slider {
                id: hueSlider
                width: parent.width; from: 0; to: 1
                onMoved: hexField.text = Qt.hsla(value, 0.85, 0.57, 1).toString()
                background: Rectangle {
                    x: hueSlider.leftPadding; y: (hueSlider.height - height) / 2; width: hueSlider.availableWidth; height: 10; radius: 5
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#ff4040" } GradientStop { position: 0.17; color: "#ffff40" }
                        GradientStop { position: 0.33; color: "#40ff40" } GradientStop { position: 0.5; color: "#40ffff" }
                        GradientStop { position: 0.67; color: "#4040ff" } GradientStop { position: 0.83; color: "#ff40ff" }
                        GradientStop { position: 1; color: "#ff4040" }
                    }
                }
            }
            Row {
                spacing: 10
                TextField {
                    id: hexField
                    objectName: "customColorHex"
                    width: 158; height: 32; color: panel.foreground
                    maximumLength: 7; selectByMouse: true
                    validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                    background: Rectangle { color: panel.dark ? "#242429" : "white"; radius: 6; border.color: "#99999f" }
                    onAccepted: if (acceptableInput) { panel.applyColor(text); colorPicker.close(); }
                }
                FolderButton {
                    width: 84; height: 32; text: "Apply"; dark: panel.dark
                    enabled: hexField.acceptableInput && !panel.busy
                    onClicked: { panel.applyColor(hexField.text); colorPicker.close(); }
                }
            }
        }
    }
}
