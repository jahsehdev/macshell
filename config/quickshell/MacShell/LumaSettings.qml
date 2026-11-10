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
    spacing: 12
    property bool reduceMotion: false
    property string removePending: ""
    property bool clearPending: false
    property string importTarget: ""
    Component.onCompleted: { controller.refresh(); ctx.run(["sources"]) }

    Common.ContinuousRectangle {
        width: parent.width; height: intro.implicitHeight + 32; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: intro; x: 16; y: 16; width: parent.width - 32; spacing: 12
            Row {
                spacing: 10
                Image { width: 40; height: 40; source: Qt.resolvedUrl("assets/luma-ai.png"); sourceSize: Qt.size(144, 144); fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true }
                LumaSettingsText { t: root.t; anchors.verticalCenter: parent.verticalCenter; text: "Luma AI"; font.pixelSize: 24; font.weight: Font.DemiBold; font.styleName: ""; color: root.t.text }
            }
            LumaSettingsText { t: root.t; width: parent.width; text: "A little help, right here on your MacShell."; font.pixelSize: 14; color: root.t.text2; wrapMode: Text.WordWrap }
            LumaSettingsText { t: root.t; width: parent.width; text: "Chat, write, summarize and open your apps. Install a model to get started. Conversations stay on this device and work offline after installation."; font.pixelSize: 13; color: root.t.text2; wrapMode: Text.WordWrap }
            Flow {
                width: parent.width
                spacing: 8
                LumaButton { t: root.t; text: root.controller.ready ? "Open Luma AI" : "Preview Luma AI"; primary: true; onClicked: root.controller.open("") }
                LumaButton { t: root.t; text: "Release memory"; visible: root.controller.loaded; enabled: !root.controller.busy; onClicked: root.controller.send({action: "unload"}) }
            }
            LumaSettingsText { t: root.t; text: root.controller.loaded ? "Model loaded · released automatically after 90 seconds idle" : "Model not loaded · no inference running"; color: root.t.text2; font.pixelSize: 12; width: parent.width; wrapMode: Text.WordWrap }
        }
    }
    Common.ContinuousRectangle {
        width: parent.width; height: voiceOptions.implicitHeight + 32; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: voiceOptions; x: 16; y: 16; width: parent.width - 32; spacing: 10
            LumaSettingsText { t: root.t; text: "Offline voice"; color: root.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; font.styleName: "" }
            LumaSettingsText { t: root.t; width: parent.width; wrapMode: Text.WordWrap; color: root.t.text2; text: "Dictation uses whisper-cli and a local whisper.cpp speech model. Read aloud uses espeak-ng. Neither feature uses cloud inference." }
            LumaButton { t: root.t; text: "Select local speech model…"; onClicked: speechModelDialog.open() }
            LumaSettingsText { t: root.t; id: voiceStatus; width: parent.width; wrapMode: Text.WordWrap; color: root.t.text2; text: "Speech dependencies are checked when used. A chat GGUF is not a speech model." }
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
    LumaSettingsText { t: root.t; text: "Local models"; topPadding: 12; leftPadding: 16; color: root.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; font.styleName: "" }
    LumaSettingsText { t: root.t;
        width: parent.width; leftPadding: 16; rightPadding: 16
        text: "Official Gemma 3 weights are gated on Hugging Face. Accept the Gemma terms on the model page, download the GGUF file, then choose Import GGUF if the in-app download is blocked."
        color: root.t.text2; wrapMode: Text.WordWrap; font.pixelSize: 12
    }
    Repeater {
        model: root.controller.catalog
        delegate: Common.ContinuousRectangle {
            id: card
            required property var modelData
            width: root.width; height: details.implicitHeight + 32; radius: 16; cornerSmoothing: 0
            color: root.t.card
            Column {
                id: details; x: 16; y: 16; width: parent.width - 32; spacing: 10
                LumaSettingsText { t: root.t; width: parent.width; wrapMode: Text.WordWrap; text: card.modelData.name + (card.modelData.id === "gemma-3-1b" ? " · Recommended" : "") + (card.modelData.installed && card.modelData.id === root.controller.selectedModel ? "  ✓ Active" : "") + (card.modelData.installed && !card.modelData.verified ? "  · Unverified" : ""); color: root.t.text; font.pixelSize: 15; font.weight: Font.DemiBold; font.styleName: "" }
                LumaSettingsText { t: root.t; width: parent.width; text: card.modelData.family + " " + card.modelData.params + " · " + card.modelData.size + " download · " + card.modelData.ram + "+ RAM suggested"; wrapMode: Text.WordWrap; color: root.t.text2; font.pixelSize: 12 }
                LumaSettingsText { t: root.t; width: parent.width; text: card.modelData.id === "gemma-3-1b" ? "Fastest option for everyday chat and short writing tasks." : "More capable responses, with higher memory use."; wrapMode: Text.WordWrap; color: root.t.text2; font.pixelSize: 12 }
                Flow {
                    width: parent.width
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
            LumaSettingsText { t: root.t; text: root.controller.stage; width: parent.width; wrapMode: Text.WordWrap; color: root.t.text; font.pixelSize: 13 }
            Rectangle { width: parent.width; height: 5; radius: 2.5; color: root.t.track
                Rectangle { width: parent.width * root.controller.progress; height: 5; radius: 2.5; color: root.t.accent }
            }
            Row { spacing: 12
                LumaButton { t: root.t; text: "Cancel"; onClicked: root.controller.send({action: "stop"}) }
                LumaSettingsText { t: root.t; text: Math.round(root.controller.progress * 100) + "%"; color: root.t.text2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
    LumaSettingsText { t: root.t; text: root.controller.error; visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; color: root.t.danger; font.pixelSize: 13 }
    LumaSettingsText { t: root.t; text: "Personal context"; topPadding: 12; leftPadding: 16; color: root.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; font.styleName: "" }
    LumaSettingsText { t: root.t;
        width: parent.width; leftPadding: 16; rightPadding: 16
        text: "Let Luma find your notes, calendar events and files in folders you choose. Everything is indexed and searched on this device; nothing leaves it. Sources are off by default."
        color: root.t.text2; wrapMode: Text.WordWrap; font.pixelSize: 12
    }
    Common.ContinuousRectangle {
        width: parent.width; height: ctxCard.implicitHeight + 24; radius: 16; cornerSmoothing: 0
        color: root.t.card
        Column {
            id: ctxCard; x: 16; y: 8; width: parent.width - 32; spacing: 0
            Repeater {
                model: ctx.sources
                delegate: Item {
                    id: sourceRow
                    objectName: "lumaSourceRow_" + modelData.kind
                    required property var modelData
                    required property int index
                    width: ctxCard.width
                    height: Math.max(64, sourceLabels.implicitHeight + 24)
                    Rectangle {
                        visible: sourceRow.index > 0
                        width: parent.width; height: 1
                        color: root.t.sep
                    }
                    Column {
                        id: sourceLabels
                        width: Math.max(0, parent.width - sourceSwitch.width - 20)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        LumaSettingsText { t: root.t;
                            width: parent.width
                            text: sourceRow.modelData.label
                            color: root.t.text
                            font.pixelSize: 14
                        }
                        LumaSettingsText { t: root.t;
                            width: parent.width
                            text: sourceRow.modelData.status
                                  + (sourceRow.modelData.items > 0 ? " · " + sourceRow.modelData.items
                                     + (sourceRow.modelData.kind === "files" ? " files" : " items") : "")
                            font.pixelSize: 12
                        }
                    }
                    Common.SettingsSwitch {
                        id: sourceSwitch
                        objectName: "lumaSourceSwitch_" + sourceRow.modelData.kind
                        t: root.t
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: sourceRow.modelData.enabled
                        enabled: sourceRow.modelData.kind !== "mail" && !ctxProc.running
                        accessibleLabel: sourceRow.modelData.label
                        reduceMotion: root.reduceMotion
                        onToggled: value => ctx.setEnabled(sourceRow.modelData.kind, value)
                    }
                }
            }
            LumaSettingsText { t: root.t;
                width: parent.width
                topPadding: 12; bottomPadding: 8
                text: "Folders to index (files source, comma separated)"
                color: root.t.text2; font.pixelSize: 12
                visible: !!(ctx.sources.find(s => s.kind === "files") || {}).enabled
            }
            Flow {
                width: parent.width
                spacing: 8
                visible: !!(ctx.sources.find(s => s.kind === "files") || {}).enabled
                Rectangle {
                    width: Math.max(0, parent.width - applyFolders.width - 8); height: 32; radius: 8
                    color: root.t.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                    TextInput {
                        id: foldersInput
                        objectName: "lumaFoldersInput"
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                        color: root.t.text; font.pixelSize: 12
                        font.family: root.t.fam; font.styleName: root.t.fontStyleName || ""
                        clip: true
                        Accessible.name: "Folders to index"
                        selectByMouse: true
                        text: {
                            var f = ctx.sources.find(s => s.kind === "files");
                            return (f && f.config && f.config.folders) ? f.config.folders.join(", ") : "";
                        }
                    }
                }
                LumaButton { id: applyFolders; t: root.t; text: "Apply"; onClicked: ctx.configureFiles(foldersInput.text) }
            }
            Row {
                width: parent.width
                topPadding: 12
                spacing: 12
                LumaButton { id: indexButton; t: root.t; text: ctx.busy ? "Indexing…" : "Index now"; enabled: !ctxProc.running; onClicked: ctx.run(["index"]) }
                LumaSettingsText { t: root.t;
                    anchors.verticalCenter: parent.verticalCenter
                    text: ctx.lastResult !== "" ? "Last index: " + ctx.lastResult : ""
                    color: root.t.text2; font.pixelSize: 12; width: Math.max(0, parent.width - indexButton.width - 12); wrapMode: Text.WordWrap
                }
            }
            LumaSettingsText { t: root.t;
                width: parent.width
                topPadding: 10
                text: ctx.error !== "" ? ctx.error : "Mail joins when MacShell Mail arrives (planned stage GG-16)."
                color: ctx.error !== "" ? root.t.danger : root.t.text2
                font.pixelSize: 12; wrapMode: Text.WordWrap
            }
        }
    }
    LumaSettingsText { t: root.t; text: "Your device, your conversations"; topPadding: 12; leftPadding: 16; color: root.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; font.styleName: "" }
    Common.ContinuousRectangle {
        width: root.width; height: privacy.implicitHeight + 32; radius: 16; color: root.t.card
        Column {
            id: privacy; x: 16; y: 16; width: parent.width - 32; spacing: 10
            LumaSettingsText { t: root.t; width: parent.width; text: "No cloud account or API key. Internet is used only to install models and their runtime. Luma does not read your screen or clipboard. Personal context — notes, calendar events and folders you explicitly add above — is off by default: you turn each source on yourself, and indexing and search stay on this device."; color: root.t.text2; wrapMode: Text.WordWrap; font.pixelSize: 12 }
            LumaSettingsText { t: root.t; width: parent.width; text: "The first installation also downloads a CPU runtime. Downloads and imports are checked against pinned Gemma SHA-256 values and recorded in a local provenance manifest. Cancelled downloads can resume when you retry. Larger models need more RAM than their download size."; color: root.t.text2; wrapMode: Text.WordWrap; font.pixelSize: 12 }
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
            onExited: {
                ctx.busy = false;
                if (args[0] !== "sources" && ctx.error === "") ctx.run(["sources"]);
            }
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
