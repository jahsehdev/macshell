pragma ComponentBehavior: Bound
import "Common" as Corners
import QtQuick

FocusScope {
    id: surface
    required property var desktop
    required property var widgets
    property Item overlay: null
    property string widgetTarget: ""
    property string renameTarget: ""
    readonly property bool dark: widgets.darkGlass
    readonly property string fam: widgets.fontFamily
    property real pressX: 0
    property real pressY: 0
    property real pointerX: 0
    property real pointerY: 0
    property bool selecting: false
    property var originalSelection: []

    function closeMenu() { context.visible = false; }
    function showMenu(entries, x, y) {
        context.entries = entries;
        context.x = Math.max(4, Math.min(width - context.width - 4, x));
        context.y = Math.max(4, Math.min(height - context.height - 4, y));
        context.visible = true;
        forceActiveFocus();
    }
    function openFileMenu(x, y) {
        widgetTarget = "";
        showMenu([
            { label: "Open", action: "open" },
            { label: "Show in Files", action: "folder" },
            { separator: true },
            { label: "Rename…", action: "rename", enabled: desktop.selected.length === 1 },
            { label: "Move to Trash", action: "trash" }
        ], x, y);
    }
    function openWidgetMenu(id, x, y) {
        widgetTarget = id;
        showMenu([
            { label: "Edit Widgets…", action: "widgets" },
            { separator: true },
            { label: "Small", action: "small" },
            { label: "Medium", action: "medium" },
            { label: "Large", action: "large" },
            { separator: true },
            { label: "Remove Widget", action: "removeWidget" }
        ], x, y);
    }
    function startRename(name) {
        closeMenu();
        renameTarget = name;
        renameInput.text = name;
        renameInput.forceActiveFocus();
        renameInput.selectAll();
    }
    function rename() {
        if (!renameInput.text.trim()) return;
        desktop.send({ action: "rename", name: renameTarget, newName: renameInput.text });
        renameTarget = "";
        forceActiveFocus();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            surface.forceActiveFocus();
            surface.closeMenu();
            surface.pressX = mouse.x; surface.pressY = mouse.y;
            surface.pointerX = mouse.x; surface.pointerY = mouse.y;
            if (mouse.button === Qt.RightButton) {
                surface.showMenu([
                    { label: "New Folder", action: "mkdir" },
                    { label: "Open Desktop in Files", action: "folder" },
                    { separator: true },
                    { label: "Edit Widgets…", action: "widgets" },
                    { label: "Clean Up Icons", action: "cleanup" },
                    { separator: true },
                    { label: "Change Wallpaper…", action: "wallpaper" }
                ], mouse.x, mouse.y);
            } else {
                surface.originalSelection = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) ? surface.desktop.selected.slice() : [];
                surface.desktop.selected = surface.originalSelection.slice();
                surface.selecting = true;
            }
        }
        onPositionChanged: mouse => {
            if (!surface.selecting || !pressed) return;
            surface.pointerX = mouse.x; surface.pointerY = mouse.y;
            surface.desktop.selectRectangle(selection.x, selection.y, selection.width, selection.height, surface.originalSelection);
        }
        onReleased: mouse => {
            var clicked = surface.selecting && mouse.button === Qt.LeftButton
                && Math.abs(mouse.x - surface.pressX) < 4 && Math.abs(mouse.y - surface.pressY) < 4
                && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier));
            surface.selecting = false;
            if (clicked && surface.widgets.hub && !surface.widgets.editing)
                surface.widgets.hub.desktopController.desktop(surface.widgets.desktopScreen ? surface.widgets.desktopScreen.name : "", false);
        }
        onCanceled: surface.selecting = false
    }
    Corners.ContinuousRectangle {
        id: selection
        visible: surface.selecting && (width > 3 || height > 3)
        x: Math.min(surface.pressX, surface.pointerX)
        y: Math.min(surface.pressY, surface.pointerY)
        width: Math.abs(surface.pressX - surface.pointerX)
        height: Math.abs(surface.pressY - surface.pointerY)
        color: "#303D8BFF"
        border.width: 1
        border.color: "#A0BADDFF"
        radius: 3
    }
    Repeater {
        model: (Corners.DesktopPreferences.settings.stageManager ? Corners.DesktopPreferences.settings.stageItems : Corners.DesktopPreferences.settings.desktopItems) ? surface.desktop.items : []
        delegate: DesktopIcon {
            required property var modelData
            file: modelData
            desktop: surface.desktop
            controller: surface
            fontFamily: surface.fam
            x: modelData.x; y: modelData.y
        }
    }

    DropArea {
        id: drops
        parent: surface.overlay || surface
        anchors.fill: parent
        z: 20
        onEntered: drag => { drag.accepted = drag.hasUrls; }
        onDropped: drop => {
            if (!drop.hasUrls) return;
            surface.desktop.copyUrls(drop.urls);
            drop.accept(Qt.CopyAction);
        }
    }
    Corners.ContinuousRectangle {
        parent: surface.overlay || surface
        anchors.fill: parent
        anchors.margins: 12
        visible: drops.containsDrag
        color: "#103D8BFF"
        border.color: "#A0B8DCFF"
        border.width: 2
        radius: 20
        z: 19
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            text: "Copy to Desktop"
            color: "white"
            font.family: surface.fam; font.pixelSize: 18; font.weight: Font.DemiBold
            style: Text.Outline; styleColor: "#70000000"
        }
    }
    MouseArea {
        parent: surface.overlay || surface
        anchors.fill: parent
        visible: context.visible
        z: 90
        acceptedButtons: Qt.AllButtons
        onPressed: surface.closeMenu()
    }
    DesktopMenu {
        id: context
        parent: surface.overlay || surface
        dark: surface.dark
        fontFamily: surface.fam
        onChosen: action => {
            surface.closeMenu();
            if (action === "widgets") surface.widgets.openGallery();
            else if (action === "folder") surface.desktop.openFolder();
            else if (action === "mkdir") surface.desktop.send({ action: "mkdir" });
            else if (action === "cleanup") surface.desktop.arrange(true);
            else if (action === "trash") surface.desktop.trashSelected();
            else if (action === "rename" && surface.desktop.selected.length === 1) surface.startRename(surface.desktop.selected[0]);
            else if (action === "open") surface.desktop.selected.forEach(function(name) { surface.desktop.open(name); });
            else if (action === "removeWidget") surface.widgets.removeWidget(surface.widgetTarget);
            else if (action === "small" || action === "medium" || action === "large") surface.widgets.setSize(surface.widgetTarget, action);
            else if (action === "wallpaper" && surface.widgets.hub) surface.widgets.hub.openSettings("wallpaper");
        }
    }

    Item {
        parent: surface.overlay || surface
        anchors.fill: parent
        z: 120
        visible: surface.renameTarget !== ""
        MouseArea { anchors.fill: parent; onClicked: { surface.renameTarget = ""; surface.forceActiveFocus(); } }
        Corners.ContinuousRectangle {
            anchors.centerIn: parent
            width: Math.min(380, parent.width - 40); height: 158; radius: 22
            color: surface.dark ? "#F0272930" : "#F0F6F6F8"
            border.color: surface.dark ? "#40FFFFFF" : "#30000000"
            MouseArea { anchors.fill: parent }
            Text {
                x: 22; y: 18
                text: "Rename"
                color: surface.dark ? "white" : "#242428"
                font.family: surface.fam; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Corners.ContinuousRectangle { cornerSmoothing: 0;
                x: 20; y: 52; width: parent.width - 40; height: 34; radius: 8
                color: surface.dark ? "#40202024" : "white"
                border.color: "#5798EF"
                TextInput {
                    selectionColor: Corners.ThemeColors.selectionFor("shell", surface.dark)
                    selectedTextColor: Corners.ThemeColors.selectedTextFor("shell", surface.dark)
                    id: renameInput
                    anchors.fill: parent; anchors.margins: 8
                    font.family: surface.fam; font.pixelSize: 13
                    color: surface.dark ? "white" : "#242428"
                    clip: true; selectByMouse: true
                    onAccepted: surface.rename()
                    Keys.onEscapePressed: { surface.renameTarget = ""; surface.forceActiveFocus(); }
                }
            }
            Corners.ContinuousRectangle { cornerSmoothing: 0;
                x: parent.width - 106; y: 106; width: 86; height: 30; radius: 8
                color: "#2673DB"
                Text { anchors.centerIn: parent; text: "Rename"; color: "white"; font.family: surface.fam; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; onClicked: surface.rename() }
            }
            Text {
                x: 24; y: 113; text: "Cancel"
                color: surface.dark ? "#D8D8DD" : "#55555C"
                font.family: surface.fam; font.pixelSize: 13
                MouseArea { anchors.fill: parent; onClicked: { surface.renameTarget = ""; surface.forceActiveFocus(); } }
            }
        }
    }
    Connections { target: surface.desktop; function onRenameRequested(name) { surface.startRename(name); } }

    Corners.ContinuousRectangle {
        parent: surface.overlay || surface
        z: 80
        anchors.right: parent.right; anchors.rightMargin: 24
        anchors.bottom: parent.bottom; anchors.bottomMargin: 104
        width: Math.min(400, surface.width - 48); height: notice.implicitHeight + 28
        radius: 14
        visible: surface.desktop.busy || surface.desktop.message !== "" || surface.widgets.pickError !== ""
        color: surface.dark ? "#EB25272E" : "#EBF3F3F5"
        border.color: surface.desktop.messageIsError || surface.widgets.pickError !== "" ? "#C8E66565" : "#50FFFFFF"
        Text {
            id: notice
            x: 14; y: 14; width: parent.width - 28
            text: surface.desktop.busy ? (surface.desktop.busyAction === "trash" ? "Moving to Trash…" : "Copying to Desktop…")
                : (surface.desktop.message || surface.widgets.pickError)
            color: surface.dark ? "white" : "#242428"
            font.family: surface.fam; font.pixelSize: 13
            wrapMode: Text.Wrap
        }
    }
    Corners.ContinuousRectangle { cornerSmoothing: 0;
        parent: surface.overlay || surface
        z: 80
        x: 24; y: surface.height - 144
        width: overflowLabel.implicitWidth + 28; height: 34; radius: 12
        visible: surface.desktop.overflowCount > 0
        color: surface.dark ? "#EB25272E" : "#EBF3F3F5"
        Text {
            id: overflowLabel
            anchors.centerIn: parent
            text: surface.desktop.overflowCount + " more items · Open Desktop in Files"
            color: surface.dark ? "white" : "#242428"
            font.family: surface.fam; font.pixelSize: 12
        }
        MouseArea { anchors.fill: parent; onClicked: surface.desktop.openFolder() }
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            closeMenu(); desktop.selected = []; widgets.finishEditing(); event.accepted = true;
        } else if (event.key === Qt.Key_F2 && desktop.selected.length === 1) {
            startRename(desktop.selected[0]); event.accepted = true;
        } else if (event.key === Qt.Key_Delete || (event.key === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier))) {
            desktop.trashSelected(); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            desktop.selected.forEach(function(name) { desktop.open(name); }); event.accepted = true;
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            desktop.selected = desktop.items.map(function(file) { return file.name; }); event.accepted = true;
        }
    }
}
