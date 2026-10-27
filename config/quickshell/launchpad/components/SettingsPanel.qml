import "../Common" as Corners
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import ".."

FocusScope {
    id: root
    signal dismissed()
    property int tab: 0
    property var draft: ({})
    property var restoreIds: []
    readonly property bool dark: Theme.darkMode
    readonly property color ink: dark ? "#e8e8eb" : "#242428"
    readonly property color muted: dark ? "#a3a3aa" : "#66666e"
    readonly property color field: dark ? "#252526" : "#ffffff"
    readonly property color rim: dark ? "#444448" : "#c8c8cf"
    readonly property color buttonFill: dark ? "#38383b" : "#e0e0e5"
    readonly property color buttonHover: dark ? "#555559" : "#d2d2d9"
    readonly property color accent: Theme.accent
    readonly property var tabs: ["Layout", "Features", "Background", "Hidden Apps"]
    readonly property var draftGeometry: Theme.layoutGeometry(width,
        height + (Theme.showDock ? Theme.bottomInset : 0) - (draft.showDock ? Theme.bottomInset : 0), draft)
    readonly property bool layoutFits: draftGeometry.fits
    readonly property bool customImageReady: draft.backgroundType === "desktop" || imageCheck.status === Image.Ready
    property bool saving: Theme.settingsSaving
    function imageLabel(url) {
        const text = String(url || "");
        const path = text.startsWith("file://") ? text.slice(7) : text;
        try { return decodeURIComponent(path); }
        catch (e) { return path; }
    }
    function change(key, value) {
        const next = Object.assign({}, draft);
        next[key] = value;
        draft = next;
    }
    function cancel() { if (!saving) dismissed(); }
    Component.onCompleted: {
        draft = Theme.settingsSnapshot();
        Theme.settingsError = "";
        forceActiveFocus();
    }
    onTabChanged: Qt.callLater(function () { if (scroll.contentItem) scroll.contentItem.contentY = 0; })
    Keys.onEscapePressed: event => { cancel(); event.accepted = true; }
    Connections {
        target: Theme
        function onSettingsSaved() {
            if (LaunchpadState.restoreHidden(root.restoreIds)) root.dismissed();
            else Theme.settingsError = LaunchpadState.layoutSaveError;
        }
    }
    Image { id: imageCheck; visible: false; source: root.draft.backgroundType === "wallpaper" ? "file://" + Theme.tahoeWallpaper : root.draft.customImage; sourceSize: Qt.size(64, 64) }
    FileDialog {
        id: imagePicker
        title: "Choose a background image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        onAccepted: root.change("customImage", selectedFile.toString())
    }
    MouseArea { anchors.fill: parent; onClicked: root.cancel() }

    Item {
        id: panel
        width: Math.max(0, Math.min(620, parent.width - 32))
        height: Math.max(0, Math.min(520, parent.height - 24))
        anchors.centerIn: parent
        clip: true
        Squircle {
            objectName: "settings-panel-background"
            anchors.fill: parent
            radius: 32
            exponent: Theme.squircleExponent
            segmentsPerCorner: 48
            fillColor: root.dark ? "#fa232323" : "#faf4f4f7"
            strokeColor: root.dark ? "#44444464" : "#80b8b8c0"
            strokeWidth: 1
        }
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10
            enabled: !root.saving
            RowLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 44
                Text { text: "Launchpad Settings"; color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 21; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Button {
                    id: closeButton
                    implicitWidth: 27
                    implicitHeight: 27
                    padding: 0
                    enabled: !Theme.settingsSaving
                    Accessible.name: "Close settings"
                    onClicked: root.cancel()
                    contentItem: Text {
                        text: "×"
                        color: closeButton.hovered ? root.ink : root.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Corners.ContinuousRectangle { cornerSmoothing: 0;
                        radius: Math.min(width, height) / 2
                        color: closeButton.down ? "#35ffffff"
                             : closeButton.hovered ? "#20ffffff" : "transparent"
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                ColumnLayout {
                    Layout.preferredWidth: panel.width < 650 ? 130 : 190
                    Layout.fillHeight: true
                    spacing: 8
                    Repeater {
                        model: root.tabs
                        delegate: Corners.ContinuousRectangle { cornerSmoothing: 0;
                            required property string modelData
                            required property int index
                            objectName: "tab-" + modelData
                            Layout.fillWidth: true
                            implicitHeight: 40
                            radius: 10
                            color: root.tab === index ? root.accent
                                 : navMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) : "transparent"
                            border.width: root.tab === index ? 1 : 0
                            border.color: root.accent
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 5; spacing: 10
                                Canvas {
                                    Layout.preferredWidth: 19; Layout.preferredHeight: 19
                                    opacity: root.tab === index ? 1 : 0.65
                                    readonly property color ink: root.tab === index ? "white" : root.ink
                                    onInkChanged: requestPaint()
                                    onPaint: {
                                        const c = getContext("2d");
                                        c.clearRect(0, 0, width, height);
                                        c.strokeStyle = ink; c.lineWidth = 1.4; c.lineCap = "round";
                                        c.beginPath();
                                        if (index === 0) {
                                            for (const n of [6, 13]) { c.moveTo(n, 2); c.lineTo(n, 17); c.moveTo(2, n); c.lineTo(17, n); }
                                        } else if (index === 1) {
                                            for (const n of [4, 9, 14]) { c.moveTo(2, n); c.lineTo(17, n); }
                                            c.moveTo(6, 2); c.lineTo(6, 6); c.moveTo(13, 7); c.lineTo(13, 11); c.moveTo(8, 12); c.lineTo(8, 16);
                                        } else if (index === 2) {
                                            c.rect(2, 3, 15, 13); c.moveTo(3, 14); c.lineTo(8, 9); c.lineTo(11, 12); c.lineTo(14, 8); c.lineTo(17, 12);
                                        } else {
                                            c.moveTo(1, 9); c.bezierCurveTo(5, 2, 14, 2, 18, 9); c.bezierCurveTo(14, 16, 5, 16, 1, 9);
                                            c.moveTo(12, 9); c.arc(9.5, 9, 2.5, 0, Math.PI * 2);
                                        }
                                        c.stroke();
                                    }
                                }
                                Text { text: modelData; color: root.tab === index ? "white" : root.muted; font.family: Theme.fontFamily; font.pixelSize: 14; Layout.fillWidth: true }
                            }
                            MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
                Corners.ContinuousRectangle { Layout.fillHeight: true; implicitWidth: 1; color: root.dark ? "#25ffffff" : "#25000000" }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14
                    ScrollView {
                        id: scroll
                        objectName: "settings-scroll"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        Item {
                            width: scroll.availableWidth
                            implicitHeight: [layoutPage, featuresPage, backgroundPage, hiddenPage][root.tab].implicitHeight
                        ColumnLayout {
                            id: layoutPage
                            width: scroll.availableWidth
                            spacing: 18
                            visible: root.tab === 0
                            Heading { text: "Layout" }
                            ToggleRow { label: "Automatic layout"; checked: root.draft.autoLayout; onToggled: value => root.change("autoLayout", value) }
                            Caption { text: "Automatically fit columns and rows to your screen." }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: panel.width < 760 ? 2 : 4
                                columnSpacing: 14; rowSpacing: 12
                                Repeater {
                                    model: [{label: "Columns", key: "columns", max: 20}, {label: "Rows", key: "rows", max: 12}, {label: "Folder Columns", key: "folderCols", max: 8}, {label: "Folder Rows", key: "folderRows", max: 7}]
                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        enabled: !root.draft.autoLayout || modelData.key.indexOf("folder") === 0
                                        opacity: enabled ? 1 : 0.45
                                        Caption { text: modelData.label }
                                        SpinBox {
                                            id: spin
                                            objectName: "spin-" + modelData.key
                                            from: 1; to: modelData.max
                                            value: root.draft.autoLayout && modelData.key === "columns" ? root.draftGeometry.columns
                                                 : root.draft.autoLayout && modelData.key === "rows" ? root.draftGeometry.rows : root.draft[modelData.key]
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            onValueModified: root.change(modelData.key, value)
                                            contentItem: Text { text: spin.value; color: root.ink; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                            background: Corners.ContinuousRectangle { cornerSmoothing: 0; radius: 8; color: root.field; border.color: root.rim }
                                            up.indicator: Corners.ContinuousRectangle { cornerSmoothing: 0; x: spin.width - width; width: 23; height: spin.height; radius: 6; color: root.buttonFill; Text { anchors.centerIn: parent; text: "+"; color: root.ink } }
                                            down.indicator: Corners.ContinuousRectangle { cornerSmoothing: 0; width: 23; height: spin.height; radius: 6; color: root.buttonFill; Text { anchors.centerIn: parent; text: "−"; color: root.ink } }
                                        }
                                    }
                                }
                            }
                            SliderRow { label: "Icon Size"; from: 40; to: 112; value: root.draft.iconSize; unit: " px"; onMoved: value => root.change("iconSize", Math.round(value)) }
                            SliderRow { label: "Background Opacity"; from: 0; to: 100; value: root.draft.backgroundOpacity * 100; unit: "%"; onMoved: value => root.change("backgroundOpacity", value / 100) }
                        }
                        ColumnLayout {
                            width: scroll.availableWidth
                            spacing: 14
                            id: featuresPage
                            visible: root.tab === 1
                            Heading { text: "Features" }
                            ToggleRow { label: "Show Dock in Launchpad"; checked: root.draft.showDock; onToggled: value => root.change("showDock", value) }
                            ToggleRow { label: "Start at Login"; checked: root.draft.startAtLogin; onToggled: value => root.change("startAtLogin", value) }
                            ToggleRow { label: "Reset Search on Relaunch"; checked: root.draft.resetSearch; onToggled: value => root.change("resetSearch", value) }
                            ToggleRow { label: "Enable Animations"; checked: root.draft.animationsEnabled; onToggled: value => root.change("animationsEnabled", value) }
                            SliderRow { label: "Folder Drop Delay"; from: 0; to: 3000; value: root.draft.dropDelay; unit: " ms"; onMoved: value => root.change("dropDelay", Math.round(value)) }
                            SliderRow { label: "Page Scroll Debounce"; from: 0; to: 3000; value: root.draft.scrollDebounce; unit: " ms"; onMoved: value => root.change("scrollDebounce", Math.round(value)) }
                            SliderRow { label: "Page Scroll Threshold"; from: 10; to: 200; value: root.draft.scrollThreshold; onMoved: value => root.change("scrollThreshold", Math.round(value)) }
                            Heading { text: "Large Folder" }
                            Caption { text: "Customize the background of an open folder." }
                            ToggleRow { label: "Close Folder After Removing an App"; checked: root.draft.closeAfterRemove; onToggled: value => root.change("closeAfterRemove", value) }
                            ToggleRow { label: "Dissolve Single-App Folders"; checked: root.draft.dissolveSingleItemFolders; onToggled: value => root.change("dissolveSingleItemFolders", value) }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [{label: "Normal Blur", key: "blur"}, {label: "Liquid Glass", key: "liquid"}]
                                    delegate: SButton {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        primary: root.draft.folderBackgroundStyle === modelData.key
                                        Accessible.name: "Large folder: " + modelData.label
                                        onClicked: root.change("folderBackgroundStyle", modelData.key)
                                    }
                                }
                            }
                            SliderRow { label: "Folder Background Blur"; from: 0; to: 100; value: root.draft.folderBackgroundBlur * 100; unit: "%"; onMoved: value => root.change("folderBackgroundBlur", value / 100) }
                            Caption { text: "Applies to both styles. At 0%, no extra folder blur is added to the Launchpad background." }
                        }
                        ColumnLayout {
                            width: scroll.availableWidth
                            spacing: 20
                            id: backgroundPage
                            visible: root.tab === 2
                            Heading { text: "Background Type" }
                            RowLayout {
                                spacing: 4
                                Layout.fillWidth: true
                                Repeater {
                                    model: [{label: "Desktop Blur", key: "desktop"}, {label: "Tahoe Wallpaper", key: "wallpaper"}, {label: "Custom Image", key: "custom"}]
                                    delegate: SButton {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        primary: root.draft.backgroundType === modelData.key
                                        onClicked: root.change("backgroundType", modelData.key)
                                    }
                                }
                            }
                            Caption { visible: root.draft.backgroundType === "desktop"; text: "Uses your desktop's existing Hyprland blur. Choose an image to adjust its blur separately." }
                            SButton { visible: root.draft.backgroundType === "custom"; text: "Choose Image…"; onClicked: imagePicker.open() }
                            Caption { visible: root.draft.backgroundType === "custom"; text: root.draft.customImage ? root.imageLabel(root.draft.customImage) : "No image selected" }
                            Corners.ContinuousRectangle {
                                Layout.fillWidth: true; implicitHeight: 120; radius: 10; color: root.dark ? "#17171a" : "#e2e2e7"; clip: true
                                visible: root.draft.backgroundType !== "desktop"
                                Image { anchors.fill: parent; source: root.draft.backgroundType === "custom" ? root.draft.customImage : "file://" + Theme.tahoeWallpaper; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(600, 200) }
                            }
                            SliderRow { visible: root.draft.backgroundType !== "desktop"; label: "Background Blur"; from: 0; to: 100; value: root.draft.backgroundBlur * 100; unit: "%"; onMoved: value => root.change("backgroundBlur", value / 100) }
                            Caption { visible: !root.customImageReady; text: imageCheck.status === Image.Loading ? "Loading image…" : "Choose a readable image before applying." }
                        }
                        ColumnLayout {
                            width: scroll.availableWidth
                            spacing: 12
                            id: hiddenPage
                            visible: root.tab === 3
                            Heading { text: "Hidden Apps" }
                            Caption { text: "Select apps to restore to the launcher, then click Apply." }
                            Caption { visible: LaunchpadState.hidden.length === 0; text: "No hidden apps." }
                            Repeater {
                                model: LaunchpadState.hidden
                                delegate: Corners.ContinuousRectangle {
                                    id: hiddenRow
                                    required property string modelData
                                    readonly property var entry: LaunchpadState.entryById(modelData)
                                    readonly property bool restoring: root.restoreIds.indexOf(modelData) >= 0
                                    Layout.fillWidth: true; implicitHeight: 56; radius: 10
                                    color: restoring ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : (root.dark ? "#16ffffff" : "#16000000")
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 5; spacing: 12
                                        Image { source: hiddenRow.entry ? Quickshell.iconPath(hiddenRow.entry.icon, true) : ""; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                                        Text { text: hiddenRow.entry ? hiddenRow.entry.name : hiddenRow.modelData; color: root.ink; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                                        SButton { text: hiddenRow.restoring ? "Undo" : "Restore"; onClicked: root.restoreIds = hiddenRow.restoring ? root.restoreIds.filter(id => id !== hiddenRow.modelData) : root.restoreIds.concat([hiddenRow.modelData]) }
                                    }
                                }
                            }
                            SButton { visible: LaunchpadState.hidden.length > 0; text: "Unhide All Apps"; onClicked: root.restoreIds = LaunchpadState.hidden.slice() }
                        }
                    }
                    }
                    Caption { visible: !root.layoutFits; text: "This grid is too large for your screen. Reduce its size or enable Automatic Layout."; color: "#ffbb77" }
                    Caption { visible: Theme.settingsError !== ""; text: Theme.settingsError; color: "#ff6969" }
                    RowLayout {
                        Layout.fillWidth: true
                        SButton { text: "Reset to Defaults"; enabled: !Theme.settingsSaving; onClicked: { root.draft = Object.assign({}, Theme.settingsDefaults); root.restoreIds = []; Theme.settingsError = ""; } }
                        Item { Layout.fillWidth: true }
                        SButton { text: "Cancel"; enabled: !Theme.settingsSaving; onClicked: root.cancel() }
                        SButton { text: Theme.settingsSaving ? "Saving…" : "Apply"; primary: true; enabled: !Theme.settingsSaving && root.customImageReady && root.layoutFits; onClicked: Theme.saveSettings(root.draft) }
                    }
                }
            }
        }
    }

    component Heading: Text {
        color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 17; font.weight: Font.DemiBold
        Layout.fillWidth: true
    }
    component Caption: Text {
        color: root.muted; font.family: Theme.fontFamily; font.pixelSize: 12; wrapMode: Text.Wrap
        Layout.fillWidth: true
    }
    component SButton: Button {
        id: button
        objectName: text
        property bool primary: false
        implicitHeight: 32
        implicitWidth: Math.max(64, label.implicitWidth + 24)
        contentItem: Text { id: label; text: button.text; color: button.enabled ? (button.primary ? "white" : root.ink) : root.muted; font.family: Theme.fontFamily; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Corners.ContinuousRectangle { cornerSmoothing: 0; radius: 8; color: button.primary ? (button.down ? Qt.darker(root.accent, 1.2) : root.accent) : button.hovered ? root.buttonHover : root.buttonFill; opacity: button.enabled ? 1 : 0.45 }
    }
    component ToggleRow: RowLayout {
        id: toggle
        objectName: label
        property string label
        property bool checked
        signal toggled(bool value)
        Layout.fillWidth: true
        Text { text: toggle.label; color: root.ink; font.family: Theme.fontFamily; font.pixelSize: 14; Layout.fillWidth: true; wrapMode: Text.Wrap }
        AbstractButton {
            id: switchButton
            objectName: "switch"
            checkable: true
            checked: toggle.checked
            implicitWidth: 58; implicitHeight: 27
            Accessible.name: toggle.label
            onToggled: toggle.toggled(checked)
            background: Corners.ContinuousRectangle { cornerSmoothing: 0;
                radius: height / 2
                color: switchButton.checked ? root.accent : (root.dark ? "#444448" : "#c3c3ca")
                Behavior on color { ColorAnimation { duration: Theme.animationsEnabled ? 140 : 0 } }
                Corners.ContinuousRectangle { cornerSmoothing: 0;
                    width: switchButton.down ? 37 : 34; height: 23; radius: height / 2
                    x: switchButton.checked ? parent.width - width - 2 : 2; y: 2
                    color: switchButton.checked ? "#e0ecff" : "#e2e2e4"
                    Behavior on x { NumberAnimation { duration: Theme.animationsEnabled ? 160 : 0; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: Theme.animationsEnabled ? 100 : 0 } }
                }
            }
        }
    }
    component SliderRow: ColumnLayout {
        id: sliderRow
        objectName: label
        property string label
        property real from: 0
        property real to: 100
        property real value: 0
        property string unit: ""
        signal moved(real value)
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Heading { text: sliderRow.label; font.pixelSize: 14 }
            Text { text: Math.round(sliderRow.value) + sliderRow.unit; color: root.muted; font.pixelSize: 12 }
        }
        Slider {
            id: slider
            objectName: "slider"
            Layout.fillWidth: true
            from: sliderRow.from; to: sliderRow.to; value: sliderRow.value
            onMoved: sliderRow.moved(value)
            implicitHeight: 28
            background: Corners.ContinuousRectangle { cornerSmoothing: 0;
                x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth; height: 5; radius: 3; color: root.dark ? "#4b4b4e" : "#b8b8bf"
                Corners.ContinuousRectangle { cornerSmoothing: 0; width: slider.visualPosition * parent.width; height: parent.height; radius: 3; color: root.accent }
            }
            handle: Corners.ContinuousRectangle { cornerSmoothing: 0;
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: 24; height: 20; radius: 10; color: slider.pressed ? "white" : "#dedee2"
            }
        }
    }
}
