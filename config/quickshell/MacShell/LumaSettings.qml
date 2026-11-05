pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "Common" as Common

Column {
    id: root
    required property var controller
    required property var t
    spacing: 14
    property string removePending: ""
    property bool clearPending: false
    property string importTarget: ""
    Component.onCompleted: { controller.refresh(); ctx.run(["sources"]) }

    Common.ContinuousRectangle {
        width: parent.width; height: intro.implicitHeight + 40; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: intro; x: 20; y: 20; width: parent.width - 40; spacing: 9
            Row {
                spacing: 10
                Image { width: 48; height: 48; source: Qt.resolvedUrl("assets/luma-ai.png"); sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Luma AI"; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 27; font.weight: Font.DemiBold; color: root.t.text }
            }
            Text { width: parent.width; text: "A little help, right here on your MacShell."; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 14; color: root.t.text2; wrapMode: Text.WordWrap }
            Text { width: parent.width; text: "Chat, write, summarize and open your apps. Install a model to get started. Conversations stay on this device and work offline after installation."; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 13; color: root.t.text2; wrapMode: Text.WordWrap }
            Row {
                spacing: 8
                LumaButton { t: root.t; text: root.controller.ready ? "Open Luma AI" : "Preview Luma AI"; primary: true; onClicked: root.controller.open("") }
                LumaButton { t: root.t; text: "Release memory"; visible: root.controller.loaded; enabled: !root.controller.busy; onClicked: root.controller.send({action: "unload"}) }
            }
            Text { text: root.controller.loaded ? "Model loaded · released automatically after 90 seconds idle" : "Model not loaded · no inference running"; color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11; width: parent.width; wrapMode: Text.WordWrap }
        }
    }
    Common.ContinuousRectangle {
        width: parent.width; height: voiceOptions.implicitHeight + 32; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: voiceOptions; x: 16; y: 16; width: parent.width - 32; spacing: 10
            Text { text: "Offline voice"; color: root.t.text; font.pixelSize: 16; font.weight: Font.DemiBold }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: root.t.text2; text: "Dictation uses whisper-cli and a local whisper.cpp speech model. Read aloud uses espeak-ng. Neither feature uses cloud inference." }
            LumaButton { t: root.t; text: "Select local speech model…"; onClicked: speechModelDialog.open() }
            Text { id: voiceStatus; width: parent.width; wrapMode: Text.WordWrap; color: root.t.text2; text: "Speech dependencies are checked when used. A chat GGUF is not a speech model." }
        }
    }
    FileDialog {
        id: speechModelDialog; title: "Select whisper.cpp GGML speech model"
        nameFilters: ["whisper.cpp models (*.bin *.ggml)"]
        onAccepted: {
            voiceConfigure.command = ["python3", "-B", Quickshell.shellPath("bin/speech.py"), "configure", "--model", decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))];
            voiceConfigure.running = true;
        }
    }
    Process {
        id: voiceConfigure
        stdout: StdioCollector { onStreamFinished: { try { const result = JSON.parse(text); voiceStatus.text = result.error || (result.stt ? "Offline dictation ready." : "Speech model saved. Install whisper-cli and pw-record to enable dictation."); } catch(e) { voiceStatus.text = "Could not configure the speech model."; } } }
    }
    Text { text: "Local models"; leftPadding: 12; color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 14; font.weight: Font.DemiBold }
    Text {
        width: parent.width; leftPadding: 12; rightPadding: 12
        text: "Official Gemma 3 weights are gated on Hugging Face. Accept the Gemma terms on the model page, download the GGUF file, then choose Import GGUF if the in-app download is blocked."
        color: root.t.text2; wrapMode: Text.WordWrap; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11
    }
    Repeater {
        model: root.controller.catalog
        delegate: Common.ContinuousRectangle {
            id: card
            required property var modelData
            width: root.width; height: details.implicitHeight + 32; radius: 16; cornerSmoothing: 0
            color: root.t.card
            Column {
                id: details; x: 16; y: 16; width: parent.width - 32; spacing: 9
                Text { text: card.modelData.name + (card.modelData.id === "gemma-3-1b" ? " · Recommended" : "") + (card.modelData.installed && card.modelData.id === root.controller.selectedModel ? "  ✓ Active" : "") + (card.modelData.installed && !card.modelData.verified ? "  · Unverified" : ""); color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { width: parent.width; text: card.modelData.family + " " + card.modelData.params + " · " + card.modelData.size + " download · " + card.modelData.ram + "+ RAM suggested"; wrapMode: Text.WordWrap; color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12 }
                Text { width: parent.width; text: card.modelData.id === "gemma-3-1b" ? "Fastest option for everyday chat and short writing tasks." : "More capable responses, with higher memory use."; wrapMode: Text.WordWrap; color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12 }
                Row {
                    spacing: 8
                    LumaButton {
                        t: root.t
                        text: !card.modelData.installed ? "Install" : !root.controller.runtimeReady ? "Repair runtime" : !card.modelData.verified ? "Unverified" : card.modelData.id === root.controller.selectedModel ? "Installed" : "Use model"
                        primary: !card.modelData.installed || !root.controller.runtimeReady || !card.modelData.verified
                        enabled: !root.controller.busy && (!root.controller.runtimeReady || !card.modelData.installed || !card.modelData.verified || card.modelData.id !== root.controller.selectedModel)
                        onClicked: {
                            if (card.modelData.installed && root.controller.runtimeReady && card.modelData.verified)
                                root.controller.send({action: "select", model: card.modelData.id});
                            else if (card.modelData.installed && !card.modelData.verified) {
                                root.importTarget = card.modelData.id;
                                importDialog.open();
                            } else root.controller.install(card.modelData.id);
                        }
                    }
                    LumaButton {
                        t: root.t
                        text: "Import GGUF…"
                        enabled: !root.controller.busy
                        onClicked: { root.importTarget = card.modelData.id; importDialog.open(); }
                    }
                    LumaButton { t: root.t; text: root.removePending === card.modelData.id ? "Confirm remove" : "Remove"; visible: card.modelData.installed; enabled: !root.controller.busy; onClicked: { if (root.removePending === card.modelData.id) { root.controller.send({action: "remove", model: card.modelData.id}); root.removePending = ""; } else root.removePending = card.modelData.id; } }
                    LumaButton { t: root.t; text: "Keep"; visible: root.removePending === card.modelData.id; onClicked: root.removePending = "" }
                }
            }
        }
    }
    Common.ContinuousRectangle {
        width: root.width; height: progressCol.implicitHeight + 28; radius: 12; color: root.t.card
        visible: root.controller.busy === "install" || root.controller.busy === "import"
        Column {
            id: progressCol; x: 14; y: 14; width: parent.width - 28; spacing: 10
            Text { text: root.controller.stage; width: parent.width; wrapMode: Text.WordWrap; color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 13 }
            Rectangle { width: parent.width; height: 5; radius: 2.5; color: root.t.track
                Rectangle { width: parent.width * root.controller.progress; height: 5; radius: 2.5; color: root.t.accent }
            }
            Row { spacing: 12
                LumaButton { t: root.t; text: "Cancel"; onClicked: root.controller.send({action: "stop"}) }
                Text { text: Math.round(root.controller.progress * 100) + "%"; color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
    Text { text: root.controller.error; visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; color: root.t.danger; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 13 }
    Text { text: "Personal context"; leftPadding: 12; color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 14; font.weight: Font.DemiBold }
    Text {
        width: parent.width; leftPadding: 12; rightPadding: 12
        text: "Let Luma find your notes, calendar events and files in folders you choose. Everything is indexed and searched on this device; nothing leaves it. Sources are off by default."
        color: root.t.text2; wrapMode: Text.WordWrap; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11
    }
    Common.ContinuousRectangle {
        width: parent.width; height: ctxCard.implicitHeight + 32; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: ctxCard; x: 16; y: 16; width: parent.width - 32; spacing: 10
            Repeater {
                model: ctx.sources
                delegate: Row {
                    required property var modelData
                    spacing: 10
                    width: parent.width
                    Text {
                        width: parent.width - 150
                        text: modelData.label + "  ·  " + modelData.status
                              + (modelData.items > 0 ? "  ·  " + modelData.items + (modelData.kind === "files" ? " files" : " items") : "")
                        color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 13
                    }
                    // simplified iOS-style switch (the dock's SSwitch is not importable from here)
                    Item {
                        id: sw
                        width: 44; height: 26
                        opacity: enabled ? 1 : 0.4
                        readonly property bool on: modelData.enabled
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.fill: parent; radius: height / 2
                            color: sw.on ? root.t.accent
                                         : (root.t.dark ? Qt.rgba(120 / 255, 120 / 255, 128 / 255, 0.32) : "#E9E9EB")
                            Behavior on color { ColorAnimation { duration: 140 } }
                            border.color: sw.on ? Qt.darker(root.t.accent, 1.12)
                                                : (root.t.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06))
                        }
                        Rectangle {
                            width: 0.62 * parent.height; height: width; radius: width / 2
                            y: 0.10 * parent.height
                            x: sw.on ? parent.width - width - 0.10 * parent.height : 0.10 * parent.height
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.kind !== "mail"
                            onClicked: ctx.setEnabled(modelData.kind, !sw.on)
                        }
                    }
                }
            }
            Text {
                width: parent.width
                text: "Folders to index (files source, comma separated)"
                color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11
                visible: (ctx.sources.find(s => s.kind === "files") || {}).enabled
            }
            Row {
                spacing: 8
                visible: (ctx.sources.find(s => s.kind === "files") || {}).enabled
                Rectangle {
                    width: parent.width - 120; height: 30; radius: 8
                    color: root.t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                    TextInput {
                        id: foldersInput
                        anchors.fill: parent; anchors.margins: 8; verticalAlignment: TextInput.AlignVCenter
                        color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12
                        selectByMouse: true
                        text: {
                            var f = ctx.sources.find(s => s.kind === "files");
                            return (f && f.config && f.config.folders) ? f.config.folders.join(", ") : "";
                        }
                    }
                }
                LumaButton { t: root.t; text: "Apply"; onClicked: ctx.configureFiles(foldersInput.text) }
            }
            Row {
                spacing: 8
                LumaButton { t: root.t; text: ctx.busy ? "Indexing…" : "Index now"; enabled: !ctx.busy; onClicked: ctx.run(["index"]) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ctx.lastResult !== "" ? "Last index: " + ctx.lastResult : ""
                    color: root.t.text2; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11; width: parent.width - 140; wrapMode: Text.WordWrap
                }
            }
            Text {
                width: parent.width
                text: ctx.error !== "" ? ctx.error : "Mail joins when MacShell Mail arrives (planned stage GG-16)."
                color: ctx.error !== "" ? root.t.danger : root.t.text2
                font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 11; wrapMode: Text.WordWrap
            }
        }
    }
    Text { text: "Your device, your conversations"; leftPadding: 12; color: root.t.text; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 14; font.weight: Font.DemiBold }
    Common.ContinuousRectangle {
        width: root.width; height: privacy.implicitHeight + 32; radius: 16; color: root.t.card
        Column {
            id: privacy; x: 16; y: 16; width: parent.width - 32; spacing: 10
            Text { width: parent.width; text: "No cloud account or API key. Internet is used only to install models and their runtime. Luma does not read your screen or clipboard. Personal context — notes, calendar events and folders you explicitly add above — is off by default: you turn each source on yourself, and indexing and search stay on this device."; color: root.t.text2; wrapMode: Text.WordWrap; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12 }
            Text { width: parent.width; text: "The first installation also downloads a CPU runtime. Downloads and imports are checked against pinned Gemma SHA-256 values and recorded in a local provenance manifest. Cancelled downloads can resume when you retry. Larger models need more RAM than their download size."; color: root.t.text2; wrapMode: Text.WordWrap; font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""; font.pixelSize: 12 }
            LumaButton { t: root.t; text: root.clearPending ? "Confirm delete history" : "Delete all conversations"; enabled: !root.controller.busy; onClicked: { if (root.clearPending) { root.controller.send({action: "clear_history"}); root.clearPending = false; } else root.clearPending = true; } }
            LumaButton { t: root.t; text: "Keep conversations"; visible: root.clearPending; onClicked: root.clearPending = false }
        }
    }
    // Personal-context bridge (bin/context.py): sources, enable/disable, folders, index.
    // Invisible layout-wise; the card above reads its state.
    Item {
        id: ctx
        visible: false; width: 0; height: 0
        property var sources: []
        property bool busy: false
        property string lastResult: ""
        property string error: ""
        readonly property string ctxPy: Quickshell.shellPath("bin/context.py")
        function parse(text) {
            try { return JSON.parse(text || ""); } catch (err) { return null; }
        }
        function run(args) {
            if (ctxProc.running) return;
            if (args[0] === "index") busy = true;
            ctxProc.args = args;
            ctxProc.running = true;
        }
        function setEnabled(kind, on) {
            run([on ? "enable" : "disable", "--kind", kind]);
        }
        function configureFiles(text) {
            if (typeof text !== "string" || text === "") return;
            run(["configure", "--kind", "files", "--folders", text]);
        }
        Process {
            id: ctxProc
            property var args: []
            command: ["python3", "-B", ctx.ctxPy].concat(ctxProc.args)
            stdout: StdioCollector {
                onStreamFinished: {
                    var r = ctx.parse(text);
                    if (!r) { ctx.error = "context bridge returned no JSON"; return; }
                    if (r.error) { ctx.error = r.error; return; }
                    ctx.error = "";
                    if (r.sources) ctx.sources = r.sources;
                    if (r.report) {
                        var parts = [];
                        for (var kind in r.report) {
                            var rep = r.report[kind];
                            if (rep.indexed > 0) parts.push(kind + " +" + rep.indexed);
                        }
                        ctx.lastResult = parts.length > 0 ? parts.join(", ") : "up to date";
                        ctx.busy = false;
                        ctx.run(["sources"]);
                    }
                }
            }
        }
    }
    FileDialog {
        id: importDialog
        title: "Choose an official Gemma 3 GGUF"
        fileMode: FileDialog.OpenFile
        nameFilters: ["GGUF models (*.gguf)"]
        onAccepted: {
            var path = decodeURIComponent(selectedFile.toString());
            if (path.indexOf("file://") === 0) path = path.substring(7);
            if (root.importTarget !== "") root.controller.importModel(root.importTarget, path);
        }
    }
}
