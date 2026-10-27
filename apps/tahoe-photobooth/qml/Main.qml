import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Tahoe.PhotoBooth 1.0

ApplicationWindow {
    id: win
    objectName: "photoBoothWindow"
    width: 800; height: 640
    minimumWidth: 560; minimumHeight: 450
    visible: true
    title: "Photo Booth"
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    font.family: booth.fontFamily
    font.pixelSize: 13
    readonly property bool dark: booth.dark
    readonly property color panel: dark ? "#282828" : "#ececed"
    readonly property color fg: dark ? "#f4f4f5" : "#242426"
    readonly property color line: dark ? "#505052" : "#bcbcc1"
    property bool effectsOpen: false
    property var selected: null
    property bool allowClose: false
    property bool galleryVisible: true
    readonly property var player: playbackLoader.item ? playbackLoader.item.player : null
    readonly property var exportDialog: booth.exportDialog
    readonly property bool viewing: selected !== null
    readonly property bool adjustable: [3, 5, 6, 7].indexOf(booth.effect) !== -1
    function trigger(modifiers) {
        if (viewing) { selected = null; return; }
        effectsOpen = false;
        booth.capture((modifiers & Qt.AltModifier) !== 0, (modifiers & Qt.ShiftModifier) !== 0);
    }
    function live() { if (player) player.stop(); selected = null; }
    function toggleSettings() { settingsMenu.requestedOpen ? settingsMenu.close() : settingsMenu.open(); }
    onSelectedChanged: {
        if (player) player.stop();
    }
    onClosing: event => {
        if (!allowClose) { event.accepted = false; booth.requestClose(); }
    }
    Connections {
        target: booth
        function onCloseReady() {
            win.allowClose = true;
            // Idle cleanup emits synchronously inside onClosing. Qt ignores a
            // nested close there, so finish the rejected event before retrying.
            Qt.callLater(function() { win.close(); });
        }
        function onFlashRequested() { flashAnimation.restart(); }
        function onSaved(url) { gallery.positionViewAtBeginning(); }
    }
    Component.onCompleted: nativeReady.start()
    Timer { id: nativeReady; interval: 500; onTriggered: booth.windowReady() }
    Shortcut { sequence: "Space"; enabled: !settingsMenu.visible && !exportDialog.visible && !exportError.visible && !deleteDialog.visible; onActivated: win.trigger(Qt.NoModifier) }
    Shortcut { sequence: "Escape"; onActivated: { if (deleteDialog.visible) deleteDialog.reject(); else if (settingsMenu.visible) settingsMenu.close(); else if (booth.countdown > 0) booth.cancel(); else if (effectsOpen) effectsOpen = false; else if (viewing) live(); } }
    Shortcut { sequence: "Ctrl+E"; enabled: viewing; onActivated: exportDialog.open(win.selected.url, win) }
    Shortcut { sequence: "Ctrl+,"; onActivated: win.toggleSettings() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }

    Rectangle {
        id: shell
        anchors.fill: parent
        color: win.panel
        radius: win.visibility === Window.Maximized ? 0 : 10
        border.width: 1; border.color: win.line
        clip: true
        Rectangle {
            id: titlebar
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 32
            color: win.dark ? "#353535" : "#e2e2e4"
            radius: shell.radius
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: parent.height / 2; color: parent.color }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: win.line }
            MouseArea {
                anchors.fill: parent
                onPressed: win.startSystemMove()
                onDoubleClicked: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 9; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Repeater {
                    model: ["close", "minimize", "maximize"]
                    delegate: Item {
                        required property string modelData
                        objectName: "trafficLight-" + modelData
                        width: 18; height: 24
                        readonly property string kind: modelData === "maximize" && win.visibility === Window.Maximized ? "restore" : modelData
                        Image {
                            anchors.centerIn: parent; width: 16; height: 16
                            sourceSize: Qt.size(32, 32)
                            source: booth.controlsPath + (win.dark ? "dark/" : "light/") + "titlebutton-" + parent.kind
                                  + (windowMouse.pressed ? "-active" : windowMouse.containsMouse ? "-hover" : !win.active ? "-backdrop" : "")
                                  + (win.dark ? "-dark" : "") + "@2.png"
                            Rectangle { anchors.fill: parent; radius: width / 2; visible: parent.status === Image.Error; color: modelData === "close" ? "#ff6057" : modelData === "minimize" ? "#ffbd2e" : "#28c840" }
                        }
                        MouseArea {
                            id: windowMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                if (modelData === "close") win.close();
                                else if (modelData === "minimize") booth.minimize();
                                else win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized();
                            }
                        }
                        Accessible.name: modelData
                        Accessible.role: Accessible.Button
                        Accessible.onPressAction: windowMouse.clicked(null)
                    }
                }
            }
            Text { anchors.centerIn: parent; text: "Photo Booth"; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg }
            ActionButton {
                id: settingsButton
                objectName: "settingsButton"
                anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 26; implicitWidth: 26; padding: 5
                cornerRadius: height / 2
                dark: win.dark; glyph: "settings"
                Accessible.name: "Camera settings"
                selected: settingsMenu.requestedOpen
                onClicked: win.toggleSettings()
            }
        }

        Item {
            id: stage
            clip: true
            anchors.top: titlebar.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: galleryPanel.top
            Rectangle { anchors.fill: parent; color: "black" }
            CameraView { anchors.fill: parent; controller: booth; visible: !win.viewing && !win.effectsOpen }
            Image { anchors.fill: parent; source: win.viewing && !win.selected.video ? win.selected.url : ""; visible: win.viewing && !win.selected.video; fillMode: Image.PreserveAspectCrop; cache: false; asynchronous: true }
            Loader {
                id: playbackLoader
                anchors.fill: parent
                active: win.viewing && win.selected.video
                sourceComponent: Item {
                    property alias player: mediaPlayer
                    VideoOutput { id: playback; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
                    MediaPlayer { id: mediaPlayer; source: win.selected ? win.selected.url : ""; videoOutput: playback; audioOutput: AudioOutput {} }
                }
            }
            ActionButton {
                anchors.centerIn: parent; visible: win.viewing && win.selected.video
                text: win.player && win.player.playbackState === MediaPlayer.PlayingState ? "Pause" : "Play video"
                glyph: win.player && win.player.playbackState === MediaPlayer.PlayingState ? "" : "play"
                dark: true
                onClicked: if (win.player) win.player.playbackState === MediaPlayer.PlayingState ? win.player.pause() : win.player.play()
                opacity: win.player && win.player.playbackState === MediaPlayer.PlayingState ? 0.55 : 1
            }
            Column {
                anchors.centerIn: parent; width: Math.min(parent.width - 48, 380); spacing: 14
                visible: !booth.hasFrame && !win.viewing
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; width: 42; height: 42; name: "camera"; ink: "#85858b" }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Waiting for your camera"; color: "#e7e7eb"; font.pixelSize: 20; font.weight: Font.Medium }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: booth.status; wrapMode: Text.WordWrap; color: "#a5a5ad"; font.pixelSize: 13 }
                ActionButton { anchors.horizontalCenter: parent.horizontalCenter; text: "Retry camera"; dark: true; onClicked: booth.retryCamera() }
            }
            GridLayout {
                anchors.fill: parent; anchors.margins: 12
                columns: 3; rowSpacing: 8; columnSpacing: 8
                visible: win.effectsOpen && !win.viewing
                Repeater {
                    model: booth.effectNames
                    delegate: Rectangle {
                        id: effectTile
                        required property int index
                        required property string modelData
                        objectName: "effect-" + index
                        Layout.fillWidth: true; Layout.fillHeight: true
                        color: "#161616"; border.width: 2
                        border.color: booth.effect === index ? "#0a84ff" : effectMouse.containsMouse ? "#b0b0b8" : "#48484b"
                        radius: 14; clip: true
                        scale: effectMouse.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        CameraView { anchors.fill: parent; anchors.margins: 5; anchors.bottomMargin: 32; controller: booth; effect: index }
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 6; anchors.horizontalCenter: parent.horizontalCenter
                            width: effectLabel.implicitWidth + 20; height: 22; radius: 11
                            color: booth.effect === effectTile.index ? "#0a84ff" : effectMouse.containsMouse ? "#55555c" : "#35353b"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: effectLabel; anchors.centerIn: parent; text: effectTile.modelData; color: "white"; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                        MouseArea { id: effectMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { booth.effect = index; win.effectsOpen = false; } }
                        Accessible.name: modelData + " effect"
                        Accessible.role: Accessible.Button
                        Accessible.onPressAction: { booth.effect = index; win.effectsOpen = false; }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: booth.countdown > 0 ? booth.countdown : ""
                color: "white"; font.pixelSize: 140; font.weight: Font.Bold
                style: Text.Outline; styleColor: "#55000000"
            }
            Rectangle {
                id: flash; anchors.fill: parent; color: "white"; opacity: 0; visible: opacity > 0
                SequentialAnimation {
                    id: flashAnimation
                    NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 45 }
                    PauseAnimation { duration: 110 }
                    NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 160 }
                }
            }
            Rectangle {
                anchors.top: parent.top; anchors.topMargin: 12; anchors.horizontalCenter: parent.horizontalCenter
                width: recordStatus.implicitWidth + 26; height: 28; radius: 14; color: "#b018181b"
                visible: booth.recording || booth.demo
                Text {
                    id: recordStatus; anchors.centerIn: parent
                    text: booth.recording ? "●  " + Math.floor(booth.duration / 60000).toString().padStart(2, "0") + ":" + Math.floor(booth.duration / 1000 % 60).toString().padStart(2, "0") : "DEMO · synthetic camera"
                    color: booth.recording ? "#ff595c" : "white"; font.pixelSize: 12
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14; anchors.horizontalCenter: parent.horizontalCenter
                width: strengthRow.width + 22; height: 34; radius: 17; color: "#b028282c"
                visible: win.adjustable && !win.effectsOpen && !win.viewing && !booth.busy
                Row {
                    id: strengthRow; anchors.centerIn: parent; spacing: 8
                    Text { text: booth.effectNames[booth.effect]; color: "white"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Slider {
                        id: strengthSlider
                        width: 140; height: 28; padding: 0
                        from: 0; to: 1; value: booth.strength
                        onMoved: booth.strength = value
                        background: Rectangle {
                            x: strengthSlider.leftPadding
                            y: (strengthSlider.height - height) / 2
                            width: strengthSlider.availableWidth; height: 4; radius: 2
                            color: "#55ffffff"
                            Rectangle { width: parent.width * strengthSlider.visualPosition; height: parent.height; radius: 2; color: "#0a84ff" }
                        }
                        handle: ButtonSurface {
                            x: strengthSlider.leftPadding + strengthSlider.visualPosition * (strengthSlider.availableWidth - width)
                            y: (strengthSlider.height - height) / 2
                            implicitWidth: 18; implicitHeight: 18
                            pressed: strengthSlider.pressed
                            focusVisible: strengthSlider.visualFocus
                        }
                    }
                }
            }
            Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 12; anchors.horizontalCenter: parent.horizontalCenter; visible: booth.mode === 0 && booth.busy && booth.countdown === 0; text: booth.burstProgress + " / 4"; color: "white"; font.pixelSize: 22; font.weight: Font.DemiBold }
        }

        Rectangle {
            id: toolbar
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            height: 56; color: win.panel; radius: shell.radius
            Rectangle { anchors.top: parent.top; width: parent.width; height: parent.height / 2; color: parent.color }
            Rectangle { width: parent.width; height: 1; color: win.line; opacity: 0.65 }
            TabBar {
                id: modeTabs
                anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
                width: 120; height: 32; padding: 3; spacing: 0
                visible: !win.viewing
                enabled: !booth.busy
                opacity: enabled ? 1 : 0.4
                currentIndex: booth.mode
                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex !== booth.mode) booth.mode = currentIndex;
                    win.effectsOpen = false;
                }
                background: ButtonSurface {
                    dark: win.dark
                    Rectangle {
                        x: modeTabs.leftPadding + Math.max(0, modeTabs.currentIndex) * width
                        y: modeTabs.topPadding
                        width: modeTabs.availableWidth / 3; height: modeTabs.availableHeight
                        radius: height / 2
                        antialiasing: true
                        color: win.dark ? "#808089" : "#ffffff"
                        border.width: 1; border.color: win.dark ? "#24ffffff" : "#12000000"
                        Behavior on x {
                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                        }
                    }
                }
                contentItem: Row {
                    spacing: modeTabs.spacing
                    Repeater { model: modeTabs.contentModel }
                }
                Repeater {
                    model: ["burst", "camera", "video"]
                    TabButton {
                        id: modeTab
                        required property string modelData
                        required property int index
                        objectName: "mode-" + index
                        implicitWidth: 38; implicitHeight: 26
                        width: modeTabs.availableWidth / 3; height: modeTabs.availableHeight
                        padding: 0; hoverEnabled: true
                        Accessible.name: index === 0 ? "Four photos" : index === 1 ? "Single photo" : "Record video"
                        background: Item {
                            Rectangle {
                                anchors.fill: parent; radius: height / 2; antialiasing: true
                                color: modeTab.down ? (win.dark ? "#30ffffff" : "#16000000")
                                     : modeTab.hovered && !modeTab.checked ? (win.dark ? "#18ffffff" : "#80ffffff") : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: -2
                                radius: height / 2; color: "transparent"; antialiasing: true
                                visible: modeTab.visualFocus
                                border.width: 2; border.color: "#800a84ff"
                            }
                        }
                        contentItem: Item {
                            Glyph {
                                anchors.centerIn: parent; width: 16; height: 16
                                name: modeTab.modelData
                                ink: win.dark ? "#f5f5f7" : "#242426"
                            }
                        }
                        DockToolTip {
                            objectName: modeTab.objectName + "-tooltip"
                            target: modeTab
                            dark: win.dark
                            visible: modeTab.enabled && modeTab.hovered && !modeTab.down
                            text: modeTab.Accessible.name
                        }
                    }
                }
            }
            ActionButton {
                objectName: "backToCameraButton"
                anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                visible: win.viewing; text: "Camera"; glyph: "back"; dark: win.dark; onClicked: win.live()
            }
            Button {
                id: captureButton
                objectName: "captureButton"
                property int captureModifiers: 0
                anchors.centerIn: parent; width: 44; height: 44
                hoverEnabled: true
                scale: down ? 0.93 : 1
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                visible: !win.viewing
                enabled: (booth.hasFrame || booth.recording) && !booth.finalizing && (booth.countdown > 0 || booth.burstProgress === 0 || booth.recording)
                Accessible.name: booth.recording ? "Stop recording" : booth.countdown > 0 ? "Cancel countdown" : "Take photo or record video"
                background: ButtonSurface {
                    dark: win.dark
                    prominent: true; tint: "#ff3b30"
                    pressed: captureButton.down; hovered: captureButton.hovered
                    focusVisible: captureButton.visualFocus
                    opacity: captureButton.enabled ? 1 : 0.45
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 4
                        radius: width / 2; color: "transparent"
                        border.width: 1; border.color: "#70ffffff"; antialiasing: true
                    }
                    Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 4; color: "white"; visible: booth.recording || booth.countdown > 0 }
                    Glyph { anchors.centerIn: parent; width: 21; height: 21; solid: true; name: booth.mode === 2 ? "video" : "camera"; visible: !booth.recording && booth.countdown === 0 }
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => { captureButton.captureModifiers = mouse.modifiers; mouse.accepted = false; }
                }
                onClicked: { if (booth.countdown > 0) booth.cancel(); else win.trigger(captureModifiers); captureModifiers = 0; }
            }
            Row {
                anchors.centerIn: parent; spacing: 8; visible: win.viewing
                ActionButton { objectName: "copyButton"; glyph: "copy"; dark: win.dark; Accessible.name: "Copy photo or video"; onClicked: booth.copyMedia(win.selected.url) }
                ActionButton { objectName: "exportButton"; glyph: "export"; text: "Export…"; dark: win.dark; onClicked: exportDialog.open(win.selected.url, win) }
                ActionButton { objectName: "trashButton"; glyph: "trash"; dark: win.dark; tint: win.dark ? "#ff746c" : "#d83b34"; Accessible.name: "Move to Trash"; onClicked: deleteDialog.open() }
            }
            ActionButton {
                objectName: "effectsButton"
                anchors.right: parent.right; anchors.rightMargin: 17; anchors.verticalCenter: parent.verticalCenter
                text: win.effectsOpen ? "Done" : "Effects"; implicitWidth: 82
                selected: win.effectsOpen
                dark: win.dark; visible: !win.viewing; enabled: !booth.busy
                onClicked: win.effectsOpen = !win.effectsOpen
            }
        }
        Rectangle {
            id: galleryPanel
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: toolbar.top
            height: booth.gallery.length > 0 && win.galleryVisible ? 58 : 0
            color: win.dark ? "#202020" : "#dcdcdf"; clip: true
            ListView {
                id: gallery; anchors.fill: parent; anchors.margins: 4; spacing: 5
                enabled: !booth.busy
                orientation: ListView.Horizontal; model: booth.gallery
                delegate: Rectangle {
                    id: galleryTile
                    required property var modelData
                    required property int index
                    objectName: "galleryCapture-" + index
                    width: 66; height: gallery.height
                    radius: 9; color: win.dark ? "#38383e" : "#f7f7fa"; border.width: 2
                    border.color: win.selected && win.selected.url.toString() === modelData.url.toString() ? "#0a84ff"
                                : galleryMouse.containsMouse ? (win.dark ? "#90ffffff" : "#60000000")
                                : win.dark ? "#26ffffff" : "#30000000"
                    scale: galleryMouse.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Image { anchors.fill: parent; anchors.margins: 4; source: modelData.thumbnail; asynchronous: true; sourceSize.width: 180; fillMode: Image.PreserveAspectFit }
                    Glyph { anchors.centerIn: parent; width: 19; height: 19; name: "play"; visible: modelData.video }
                    MouseArea { id: galleryMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { win.selected = modelData; win.effectsOpen = false; } onDoubleClicked: if (modelData.video && win.player) win.player.play() }
                    Accessible.name: modelData.name
                    Accessible.role: Accessible.Button
                    Accessible.onPressAction: win.selected = modelData
                }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            }
        }
    }

    component DevicePicker: ComboBox {
        id: picker
        Layout.fillWidth: true
        implicitHeight: 32
        font.pixelSize: 12
        font.family: booth.fontFamily
        hoverEnabled: true
        textRole: "name"
        palette.base: win.panel
        palette.text: win.fg
        palette.highlight: "#0a84ff"
        palette.highlightedText: "white"
        background: ButtonSurface {
            dark: win.dark; pressed: picker.down; hovered: picker.hovered
            focusVisible: picker.visualFocus
            opacity: picker.enabled ? 1 : 0.45
        }
        contentItem: Text { leftPadding: 10; rightPadding: 25; text: picker.displayText; font: picker.font; color: win.fg; opacity: picker.enabled ? 1 : 0.45; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
        indicator: Glyph { name: "chevron"; width: 12; height: 12; x: picker.width - 22; y: (picker.height - height) / 2; ink: win.fg; opacity: picker.enabled ? 0.7 : 0.3 }
        delegate: ItemDelegate {
            id: deviceOption
            required property var model
            required property int index
            width: picker.width - 8; height: 30
            highlighted: picker.highlightedIndex === index
            contentItem: Text {
                text: deviceOption.model.name
                font: picker.font
                color: deviceOption.highlighted ? "white" : win.fg
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle { radius: 10; color: deviceOption.highlighted ? "#007aff" : "transparent" }
        }
        popup: Popup {
            y: picker.height + 5
            width: picker.width
            implicitHeight: Math.min(contentItem.implicitHeight + 8, 180)
            padding: 4
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
            background: ButtonSurface { dark: win.dark; cornerRadius: 14 }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: picker.popup.visible ? picker.delegateModel : null
                currentIndex: picker.highlightedIndex
                ScrollIndicator.vertical: ScrollIndicator {}
            }
        }
    }
    component SettingToggle: Switch {
        id: toggle
        Layout.fillWidth: true
        implicitHeight: 32
        padding: 0
        font.pixelSize: 12
        font.family: booth.fontFamily
        hoverEnabled: true
        indicator: ButtonSurface {
            implicitWidth: 36; implicitHeight: 22
            x: toggle.width - width; y: (toggle.height - height) / 2
            dark: win.dark; prominent: toggle.checked; tint: toggle.checked ? "#007aff" : "transparent"
            hovered: toggle.hovered; pressed: toggle.down
            focusVisible: toggle.visualFocus
            opacity: toggle.enabled ? 1 : 0.45
            Rectangle {
                x: toggle.checked ? parent.width - width - 2 : 2
                y: 2; width: 18; height: 18; radius: 9
                color: "#ffffff"; antialiasing: true
                border.width: 1; border.color: "#10000000"
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Text { text: toggle.text; font: toggle.font; rightPadding: 46; verticalAlignment: Text.AlignVCenter; color: win.fg; opacity: toggle.enabled ? 1 : 0.45; elide: Text.ElideRight }
    }
    Popup {
        id: settingsMenu
        objectName: "settingsMenu"
        property real reveal: 0
        property bool requestedOpen: false
        onAboutToShow: { requestedOpen = true; booth.retryCamera(); }
        onAboutToHide: requestedOpen = false
        enter: Transition {
            NumberAnimation { target: settingsMenu; property: "reveal"; to: 1; duration: 450; easing.type: Easing.Linear }
        }
        exit: Transition {
            NumberAnimation { target: settingsMenu; property: "reveal"; to: 0; duration: 350; easing.type: Easing.Linear }
        }
        parent: settingsButton
        popupType: Popup.Item
        x: settingsButton.width - width
        y: settingsButton.height + 7
        width: Math.min(332, win.width - 24)
        height: Math.min(implicitHeight, win.height - 50)
        margins: 8
        padding: 12
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: SettingsGlass {
            backdrop: shell
            dark: win.dark
            progress: settingsMenu.reveal
            originSize: Qt.size(settingsButton.width, settingsButton.height)
            originOffset: settingsMenu.y
        }
        contentItem: ScrollView {
            id: settingsScroll
            implicitHeight: settingsOptions.implicitHeight
            enabled: settingsMenu.requestedOpen && settingsMenu.reveal > 0.95
            opacity: Math.max(0, Math.min(1, (settingsMenu.reveal - 0.5) / 0.5))
            transform: [
                Scale {
                    origin.x: settingsScroll.width
                    xScale: Math.max(0.001, (settingsMenu.width - settingsMenu.background.surfaceLeft - 2 * settingsMenu.padding) / Math.max(1, settingsScroll.width))
                    yScale: Math.max(0.001, (settingsMenu.background.surfaceHeight - 2 * settingsMenu.padding) / Math.max(1, settingsScroll.height))
                },
                Translate { y: settingsMenu.background.surfaceTop }
            ]
            layer.enabled: settingsMenu.background.hardwareEffects && settingsMenu.reveal < 0.999
            layer.effect: ShaderEffect {
                property var source
                property vector2d itemSize: Qt.vector2d(settingsScroll.width, settingsScroll.height)
                property real reveal: settingsMenu.reveal
                fragmentShader: "qrc:/shaders/settings-content.frag.qsb"
            }
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ColumnLayout {
                id: settingsOptions
                width: settingsScroll.availableWidth
                spacing: 6
                Label { text: "Camera settings"; color: win.fg; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.bottomMargin: 3 }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Camera"; color: win.fg; font.pixelSize: 12; Layout.preferredWidth: 78 }
                    DevicePicker {
                        objectName: "cameraPicker"
                        model: booth.cameras.length ? booth.cameras : [{ name: booth.demo ? "Demo camera" : "No camera connected" }]
                        currentIndex: Math.max(0, booth.cameraIndex)
                        enabled: !booth.busy && !booth.demo && booth.cameras.length > 0
                        onActivated: booth.cameraIndex = currentIndex
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Microphone"; color: win.fg; font.pixelSize: 12; Layout.preferredWidth: 78 }
                    DevicePicker {
                        model: booth.microphones.length ? booth.microphones : [{ name: booth.demo ? "Demo audio" : "No microphone connected" }]
                        currentIndex: Math.max(0, booth.microphoneIndex)
                        enabled: !booth.busy && !booth.demo && booth.microphones.length > 0
                        onActivated: booth.microphoneIndex = currentIndex
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !booth.demo
                    ActionButton {
                        objectName: "openDroidcamButton"
                        Layout.fillWidth: true
                        visible: booth.droidcamInstalled
                        text: "Open DroidCam"; glyph: "camera"; dark: win.dark
                        onClicked: booth.openDroidcam()
                    }
                    ActionButton {
                        objectName: "refreshCamerasButton"
                        text: "Refresh"; dark: win.dark; enabled: !booth.busy
                        onClicked: booth.retryCamera()
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !booth.demo && booth.droidcamInstalled && booth.cameras.length === 0
                    text: "Connect your phone in DroidCam and press Start. The camera list updates automatically."
                    font.pixelSize: 11; wrapMode: Text.WordWrap
                    color: win.dark ? "#b5b5bc" : "#62626a"
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 3; Layout.bottomMargin: 2; height: 1; color: win.line; opacity: 0.6 }
                SettingToggle { objectName: "microphoneToggle"; text: "Record microphone audio"; checked: booth.microphone; enabled: !booth.busy; onToggled: booth.microphone = checked }
                SettingToggle { text: "Mirror camera and saved captures"; checked: booth.mirrored; enabled: !booth.busy; onToggled: booth.mirrored = checked }
                SettingToggle { text: "Enable screen flash"; checked: booth.flashEnabled; onToggled: booth.flashEnabled = checked }
                SettingToggle { text: "Show photo strip"; checked: win.galleryVisible; onToggled: win.galleryVisible = checked }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 2; Layout.bottomMargin: 2; height: 1; color: win.line; opacity: 0.6 }
                ActionButton {
                    Layout.fillWidth: true
                    text: "Open Photo Booth folder"; glyph: "folder"; dark: win.dark
                    onClicked: { settingsMenu.close(); booth.openLibrary(); }
                }
                Label { Layout.fillWidth: true; Layout.topMargin: 3; text: "Alt-click skips countdown\nShift-click skips screen flash"; color: win.dark ? "#a5a5ac" : "#74747b"; font.pixelSize: 11; wrapMode: Text.WordWrap }
            }
        }
    }
    Connections {
        target: booth
        function onExportFailed(message) { exportError.text = message; exportError.open(); }
    }
    Dialog {
        id: exportError
        property string text: ""
        title: "Could not export"
        anchors.centerIn: parent
        width: Math.min(340, win.width - 32)
        padding: 20
        contentWidth: width - leftPadding - rightPadding
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        modal: true; focus: true
        standardButtons: Dialog.NoButton
        header: null; footer: null
        background: ContinuousPanel { cornerRadius: 24; color: win.dark ? "#2c2c2e" : "#ffffff" }
        contentItem: ColumnLayout {
            spacing: 16
            Label { Layout.fillWidth: true; text: exportError.title; color: win.fg; font.pixelSize: 18; font.weight: Font.Medium; wrapMode: Text.WordWrap }
            Label { Layout.fillWidth: true; text: exportError.text; color: win.fg; wrapMode: Text.WordWrap }
            ActionButton { Layout.alignment: Qt.AlignRight; text: "OK"; implicitWidth: 80; dark: win.dark; prominent: true; onClicked: exportError.accept() }
        }
    }

    component DeleteButton: ActionButton {
        id: control
        property bool primary: false
        Layout.fillWidth: true
        implicitHeight: 46
        padding: 10
        dark: win.dark
        prominent: primary
        font.pixelSize: 15
        font.weight: Font.Medium
    }
    Dialog {
        id: deleteDialog
        objectName: "deleteDialog"
        anchors.centerIn: parent
        width: Math.min(340, win.width - 32)
        modal: true
        focus: true
        popupType: Popup.Item
        closePolicy: Popup.CloseOnEscape
        title: "Move this capture to Trash?"
        header: null
        footer: null
        standardButtons: Dialog.NoButton
        padding: 12
        topPadding: 22
        bottomPadding: 12
        background: ContinuousPanel {
            cornerRadius: 32
            color: win.dark ? "#2c2c2e" : "#ffffff"
        }
        contentItem: ColumnLayout {
            spacing: 0
            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 14
                text: deleteDialog.title
                color: win.fg
                font.family: booth.fontFamily
                font.pixelSize: 20
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                Layout.bottomMargin: 26
                text: "You can restore it later from Trash in Files."
                color: win.dark ? "#e5e5e7" : "#242426"
                font.family: booth.fontFamily
                font.pixelSize: 14
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                uniformCellSizes: true
                DeleteButton {
                    id: cancelDeleteButton
                    objectName: "cancelDeleteButton"
                    text: "No, Don’t"
                    onClicked: deleteDialog.reject()
                }
                DeleteButton {
                    objectName: "confirmDeleteButton"
                    text: "Yes, Delete"
                    primary: true
                    enabled: win.viewing && !booth.busy
                    onClicked: deleteDialog.accept()
                }
            }
        }
        onOpened: cancelDeleteButton.forceActiveFocus(Qt.PopupFocusReason)
        onAccepted: { if (win.player) win.player.stop(); if (win.selected && booth.trashMedia(win.selected.url)) win.selected = null; }
    }
    // Native Wayland resize requests keep the frame resizable with custom controls.
    Repeater {
        model: [Qt.TopEdge, Qt.BottomEdge, Qt.LeftEdge, Qt.RightEdge, Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge | Qt.RightEdge, Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge | Qt.RightEdge]
        MouseArea {
            required property int modelData
            readonly property bool topEdge: (modelData & Qt.TopEdge) !== 0
            readonly property bool bottomEdge: (modelData & Qt.BottomEdge) !== 0
            readonly property bool leftEdge: (modelData & Qt.LeftEdge) !== 0
            readonly property bool rightEdge: (modelData & Qt.RightEdge) !== 0
            width: (leftEdge || rightEdge) ? 5 : win.width - 10
            height: (topEdge || bottomEdge) ? 5 : win.height - 10
            x: rightEdge ? win.width - width : leftEdge ? 0 : 5
            y: bottomEdge ? win.height - height : topEdge ? 0 : 5
            cursorShape: (topEdge || bottomEdge) && (leftEdge || rightEdge) ? (topEdge === leftEdge ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : (leftEdge || rightEdge) ? Qt.SizeHorCursor : Qt.SizeVerCursor
            onPressed: win.startSystemResize(modelData)
        }
    }
}
