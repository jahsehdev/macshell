pragma ComponentBehavior: Bound
// macOS Settings pop-up button. Search is opt-in; regular menus align the selected row
// with the button, while searchable menus open below it with a fixed search header.
import "Common" as Corners
import QtQuick
import QtQuick.Controls

Item {
    id: pu
    required property var t
    property var model: []
    property int current: 0
    property var colorSwatches: []
    property bool allowReselect: false
    property string accessibleLabel: ""
    property bool searchable: false
    property string searchPlaceholder: "Search"
    signal opening()
    readonly property var filteredIndices: {
        const query = searchable ? searchField.text.trim().toLocaleLowerCase() : "";
        const indices = [];
        for (let i = 0; i < model.length; i++)
            if (!query || String(model[i]).toLocaleLowerCase().includes(query)) indices.push(i);
        return indices;
    }
    signal picked(int index)
    width: 220; height: 26
    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: accessibleLabel || String(model[current] || "")
    Accessible.onPressAction: openMenu()
    Keys.onSpacePressed: openMenu()
    Keys.onReturnPressed: openMenu()
    Keys.onUpPressed: { if (model.length) picked((current + model.length - 1) % model.length); }
    Keys.onDownPressed: { if (model.length) picked((current + 1) % model.length); }
    Corners.ContinuousRectangle {
        anchors.fill: parent; radius: 6
        color: puMa.containsMouse || menu.visible ? pu.t.hover : "transparent"
        border.width: pu.activeFocus ? 1 : 0
        border.color: pu.t.accent
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    Text {
        id: selectedValue
        anchors.right: chev.left; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 30; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
        text: pu.model[pu.current] !== undefined ? pu.model[pu.current] : ""
        color: pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
    }
    Corners.ColorDot {
        visible: pu.colorSwatches.length > 0
        value: pu.colorSwatches[pu.current] || "multicolor"
        width: 16; height: 16
        x: Math.max(2, selectedValue.x + selectedValue.width - Math.min(selectedValue.contentWidth, selectedValue.width) - 23)
        anchors.verticalCenter: parent.verticalCenter
    }
    Canvas {
        id: chev
        anchors.right: parent.right; anchors.rightMargin: 7; anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 12
        property color ink: pu.t.text2
        onInkChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset();
            c.strokeStyle = ink; c.lineWidth = 1.4; c.lineCap = "round"; c.lineJoin = "round";
            c.beginPath(); c.moveTo(1, 4.2); c.lineTo(4, 1.2); c.lineTo(7, 4.2); c.stroke();
            c.beginPath(); c.moveTo(1, 7.8); c.lineTo(4, 10.8); c.lineTo(7, 7.8); c.stroke();
        }
    }
    function openMenu() { opening(); menu.open(); }
    function pickRow(index) {
        if (index < 0 || index >= filteredIndices.length) return;
        const originalIndex = filteredIndices[index];
        menu.close();
        if (allowReselect || originalIndex !== current) picked(originalIndex);
    }
    function moveSelection(step) {
        if (!filteredIndices.length) return;
        results.currentIndex = (results.currentIndex + step + filteredIndices.length) % filteredIndices.length;
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    MouseArea { id: puMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pu.openMenu() }

    Popup {
        id: menu
        objectName: "settingsPopupMenu"
        readonly property real rowH: pu.searchable ? 32 : 26
        readonly property real searchH: pu.searchable ? 44 : 0
        readonly property real resultsH: Math.max(pu.filteredIndices.length, pu.searchable ? 1 : 0) * rowH
        width: Math.max(pu.width, pu.searchable ? 248 : 180)
        x: pu.width - width
        // macOS: the current item sits right on the button; if that would leave the window, the menu shifts to fit,
        // and a menu taller than the window scrolls (no separate popup window: those fought Hyprland's pointer grabs)
        // Qt keeps the popup inside the window (8 px margin): it shifts up and, if still too tall, shrinks — the list scrolls
        margins: 8
        height: searchH + (pu.searchable ? Math.min(resultsH, 256) : resultsH) + 2 * padding
        y: pu.searchable ? pu.height + 4 : -(padding + pu.current * rowH)
        padding: Corners.CornerTheme.menuInset
        modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: {
            searchField.clear();
            results.currentIndex = Math.max(0, pu.filteredIndices.indexOf(pu.current));
            results.positionViewAtIndex(results.currentIndex, ListView.Contain);
        }
        onOpened: {
            if (pu.searchable) searchField.forceActiveFocus();
            else results.forceActiveFocus();
        }
        onClosed: pu.forceActiveFocus()
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 320; easing.type: Easing.OutQuint }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; to: 0.97; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        background: Item {
            Corners.ContinuousRectangle {
                anchors.fill: parent; radius: Corners.CornerTheme.menuRadius
                color: pu.t.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.985) : Qt.rgba(0.98, 0.98, 0.99, 0.99)
                border.width: 1; border.color: pu.t.dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.10)
            }
        }
        contentItem: Item {
            TextField {
                id: searchField
                objectName: "settingsPopupSearch"
                visible: pu.searchable
                width: parent.width; height: 34
                leftPadding: 32; rightPadding: 10
                topPadding: 0; bottomPadding: 0
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: pu.searchPlaceholder
                Accessible.name: pu.searchPlaceholder
                color: pu.t.text; placeholderTextColor: pu.t.text2
                selectionColor: pu.t.accent
                font.family: pu.t.fam; font.pixelSize: 13
                selectByMouse: true
                onTextChanged: results.currentIndex = pu.filteredIndices.length ? 0 : -1
                Keys.onDownPressed: pu.moveSelection(1)
                Keys.onUpPressed: pu.moveSelection(-1)
                onAccepted: pu.pickRow(results.currentIndex)
                background: Corners.ContinuousRectangle {
                    radius: 10
                    color: pu.t.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.04)
                    border.width: searchField.activeFocus ? 1.5 : 1
                    border.color: searchField.activeFocus ? pu.t.accent : pu.t.text3
                }
                Canvas {
                    x: 11; anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14
                    property color ink: pu.t.text2
                    onInkChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d"); c.reset();
                        c.strokeStyle = ink; c.lineWidth = 1.5; c.lineCap = "round";
                        c.beginPath(); c.arc(5.5, 5.5, 4, 0, Math.PI * 2); c.stroke();
                        c.beginPath(); c.moveTo(8.5, 8.5); c.lineTo(12, 12); c.stroke();
                    }
                }
            }
            ListView {
                id: results
                objectName: "settingsPopupResults"
                y: menu.searchH
                width: parent.width; height: parent.height - y
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: pu.filteredIndices
                keyNavigationEnabled: false
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Keys.onUpPressed: pu.moveSelection(-1)
                Keys.onDownPressed: pu.moveSelection(1)
                Keys.onReturnPressed: pu.pickRow(currentIndex)
                Keys.onEnterPressed: pu.pickRow(currentIndex)
                Keys.onSpacePressed: pu.pickRow(currentIndex)
                delegate: Item {
                    id: row
                    required property int modelData
                    required property int index
                    readonly property bool highlighted: rowMa.containsMouse || (results.activeFocus || pu.searchable) && results.currentIndex === index
                    width: menu.width - 2 * menu.padding; height: menu.rowH
                    Corners.MenuHighlight {
                        anchors.fill: parent
                        color: row.highlighted ? pu.t.accent : "transparent"
                    }
                    Text {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        text: "\u2713"; visible: row.modelData === pu.current
                        color: row.highlighted ? "white" : pu.t.text; font.pixelSize: 12; font.bold: true
                    }
                    Text {
                        x: pu.colorSwatches.length > 0 ? 49 : 26; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 8; elide: Text.ElideRight
                        text: pu.model[row.modelData]
                        color: row.highlighted ? "white" : pu.t.text; font.family: pu.t.fam; font.pixelSize: 13
                    }
                    Corners.ColorDot {
                        visible: pu.colorSwatches.length > 0
                        value: pu.colorSwatches[row.modelData] || "multicolor"
                        x: 27; width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MouseArea {
                        id: rowMa; anchors.fill: parent; hoverEnabled: true
                        onPositionChanged: results.currentIndex = row.index
                        onClicked: pu.pickRow(row.index)
                    }
                }
            }
            Text {
                visible: pu.searchable && pu.filteredIndices.length === 0
                y: menu.searchH; width: parent.width; height: menu.rowH
                text: "No results"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                color: pu.t.text2; font.family: pu.t.fam; font.pixelSize: 13
            }
        }
    }
}
