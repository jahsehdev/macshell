import QtQuick
import QtQuick.Controls
import "ControlCatalog.js" as Catalog

Rectangle {
    id: gallery
    objectName: "controlsGallery"
    property var controller
    property Item dragLayer: parent
    property bool dark: false
    property color accent: "#0a84ff"
    property string fontFamily: "SF Pro Text"
    property string category: "all"
    property string query: ""
    property string message: "Drag controls to Control Center or the menu bar."
    property bool dragging: false
    property string actionId: ""
    property string actionDestination: "controlcenter"
    property var sections: Catalog.sections(category, query)
    readonly property color foreground: dark ? "#f5f5f7" : "#29292c"
    readonly property color secondary: dark ? "#a9acb8" : "#747887"
    readonly property color separator: dark ? "#20ffffff" : "#140e1733"
    readonly property bool compact: width < 470
    readonly property real sidebarWidth: compact ? 68 : 196
    readonly property real contentLeft: sidebarWidth + (compact ? 16 : 22)
    readonly property var activeCategory: Catalog.categories.filter(function(item) { return item.id === gallery.category; })[0] || Catalog.categories[0]
    readonly property string heading: query.trim() !== "" ? "Search Results" : category === "all" ? "Add Controls" : activeCategory.label
    signal finished()
    signal controlDragged(string id, real px, real py)
    signal controlDropped(string id, real px, real py)
    signal dragCanceled()
    color: dark ? "#25272e" : "#f5f6fa"
    radius: 26
    antialiasing: true
    border.width: 1
    border.color: dark ? "#48ffffff" : "#ffffff"
    focus: visible
    Keys.onEscapePressed: {
        if (actions.visible) actions.visible = false;
        else finished();
    }
    onVisibleChanged: {
        if (visible) { search.forceActiveFocus(); category = "all"; search.text = ""; }
        else { actions.visible = false; dragging = false; dragCanceled(); }
    }
    function notify(text) { message = text; notice.restart(); }
    function showActions(id, px, py, destination) {
        actionId = id;
        actionDestination = destination || "controlcenter";
        actions.x = Math.max(sidebarWidth + 6, Math.min(width - actions.width - 10, px));
        actions.y = Math.max(8, Math.min(height - actions.height - 10, py));
        actions.visible = true;
    }
    function closeActions() { actions.visible = false; }
    function applyAction(action) {
        var id = actionId, c = controller;
        actions.visible = false;
        if (action === "cc") {
            if (c.ccControls.indexOf(id) >= 0) { c.ccRemove(id); notify("Removed from Control Center"); }
            else { c.ccAdd(id); notify("Added to Control Center"); }
        } else if (action === "bar") {
            c.pinControl(id, !c.controlPinned(id));
            notify(c.controlPinned(id) ? "Added to Menu Bar" : "Removed from Menu Bar");
        } else if (action === "left" || action === "right") c.moveControlPin(id, action === "left" ? -1 : 1);
        else c.resizeControl(id, action);
    }
    Timer { id: notice; interval: 2600; onTriggered: gallery.message = "Drag controls to Control Center or the menu bar." }
    // Own the panel's empty areas so the shell's click-away layer stays behind it.
    MouseArea { anchors.fill: parent; onPressed: actions.visible = false }

    Rectangle {
        x: 8; y: 8; width: gallery.sidebarWidth - 8; height: parent.height - 16
        radius: 20; antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0; color: gallery.dark ? "#353842" : "#e9edf5" }
            GradientStop { position: 1; color: gallery.dark ? "#2b2d35" : "#e8eaf1" }
        }
        border.width: 1; border.color: gallery.dark ? "#10ffffff" : "#80ffffff"
    }
    Rectangle {
        id: searchBox
        x: gallery.compact ? gallery.contentLeft : 20
        y: gallery.compact ? 91 : 20
        width: gallery.compact ? gallery.width - x - 20 : gallery.sidebarWidth - 32
        height: 34; radius: 17; antialiasing: true
        color: gallery.dark ? "#24262e" : "#c0ffffff"
        border.color: search.activeFocus ? "#700a84ff" : gallery.separator
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 130 } }
        ControlIcon { x: 11; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: "search"; color: gallery.secondary }
        TextInput {
            id: search
            objectName: "controlSearch"
            x: 33; width: parent.width - x - (text.length ? 31 : 10); anchors.verticalCenter: parent.verticalCenter
            font.family: gallery.fontFamily; font.pixelSize: 12
            color: gallery.foreground
            clip: true; selectByMouse: true
            onTextChanged: { gallery.query = text; actions.visible = false; catalogScroll.contentY = 0; }
            Accessible.name: "Search controls"
            Text { width: parent.width; elide: Text.ElideRight; visible: search.text === ""; text: "Search Controls"; color: gallery.secondary; font: search.font }
            Keys.onEscapePressed: { if (text !== "") text = ""; else gallery.finished(); }
        }
        Button {
            id: clearSearch
            objectName: "clearControlSearch"
            visible: search.text.length > 0
            anchors.right: parent.right; anchors.rightMargin: 5; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; padding: 6
            hoverEnabled: true
            Accessible.name: "Clear search"
            background: Rectangle { radius: height / 2; color: clearSearch.hovered ? (gallery.dark ? "#20ffffff" : "#10000000") : "transparent" }
            contentItem: ControlIcon { kind: "close"; color: gallery.secondary }
            onClicked: { search.text = ""; search.forceActiveFocus(); }
        }
    }
    Flickable {
        id: sidebarScroll
        x: 16; y: gallery.compact ? 20 : 69; width: gallery.sidebarWidth - 24; height: gallery.height - y - 20
        contentHeight: categoryColumn.height; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 4 }
        Column {
            id: categoryColumn
            width: sidebarScroll.width; spacing: 4
            Repeater {
                model: Catalog.categories
                delegate: Button {
                    id: categoryItem
                    required property var modelData
                    objectName: "controlCategory_" + modelData.id
                    readonly property bool current: gallery.category === modelData.id
                    width: categoryColumn.width
                    height: !gallery.compact && modelData.id === "capture" ? 48 : 42
                    padding: 0; hoverEnabled: true
                    Accessible.name: modelData.label
                    background: Rectangle {
                        radius: 12; antialiasing: true
                        color: categoryItem.current ? gallery.accent
                             : categoryItem.down ? (gallery.dark ? "#484d5b" : "#d6dce8")
                             : categoryItem.hovered ? (gallery.dark ? "#3b3e49" : "#90ffffff") : "transparent"
                        border.width: categoryItem.visualFocus ? 2 : 0
                        border.color: categoryItem.current ? "#b3ffffff" : gallery.accent
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    contentItem: Item {
                        Rectangle {
                            x: gallery.compact ? (parent.width - width) / 2 : 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 7; antialiasing: true
                            color: categoryItem.modelData.id === "all" ? (categoryItem.current ? gallery.accent : gallery.dark ? "#555a68" : "#8b91a0") : categoryItem.modelData.color
                            ControlIcon { anchors.centerIn: parent; width: 17; height: 17; kind: categoryItem.modelData.icon; color: "white" }
                        }
                        Text {
                            visible: !gallery.compact
                            x: 43; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 6
                            text: categoryItem.modelData.label; wrapMode: Text.WordWrap
                            color: categoryItem.current ? "#ffffff" : gallery.foreground
                            font.family: gallery.fontFamily; font.pixelSize: 12
                            font.weight: categoryItem.current ? Font.Medium : Font.Normal
                        }
                    }
                    ToolTip.visible: gallery.compact && categoryItem.hovered
                    ToolTip.text: modelData.label
                    ToolTip.delay: 500
                    onClicked: { gallery.category = modelData.id; catalogScroll.contentY = 0; actions.visible = false; }
                }
            }
        }
    }

    Text {
        id: headingText
        objectName: "controlGalleryHeading"
        x: gallery.contentLeft; y: 25
        width: gallery.width - x - 20
        text: gallery.heading; color: gallery.foreground
        font.family: gallery.fontFamily; font.pixelSize: gallery.compact ? 22 : 24; font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    Text {
        x: gallery.contentLeft; y: 60
        width: gallery.width - x - 20
        text: gallery.query.trim() !== "" ? "Find a control, then choose where it belongs." : "Personalize Control Center and your menu bar."
        color: gallery.secondary; font.family: gallery.fontFamily; font.pixelSize: 12
        wrapMode: Text.WordWrap
    }
    Flickable {
        id: catalogScroll
        objectName: "controlCatalogScroll"
        x: gallery.contentLeft; y: gallery.compact ? 143 : 104
        width: gallery.width - x - 20; height: gallery.height - y - 71
        contentWidth: width; contentHeight: catalogColumn.height
        clip: true; interactive: !gallery.dragging
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5 }
        Column {
            id: catalogColumn
            width: catalogScroll.width - 4; spacing: 22
            Rectangle {
                id: whatsNew
                objectName: "controlsDemoCard"
                visible: gallery.category === "all" && gallery.query.trim() === ""
                width: parent.width
                height: Math.max(156, demoDescription.y + demoDescription.implicitHeight + 17)
                radius: 14; antialiasing: true
                color: gallery.dark ? "#36373c" : "#e6e6e9"
                Text {
                    id: demoTitle
                    x: 14; y: 17; width: parent.width * 0.5 - 23
                    text: "What’s New"; color: gallery.foreground
                    font.family: gallery.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    id: demoDescription
                    x: demoTitle.x; y: demoTitle.y + demoTitle.implicitHeight + 5
                    width: demoTitle.width
                    text: "Control Center is more flexible than ever. Resize and rearrange controls to make it your own. Add your favorites to the menu bar."
                    wrapMode: Text.WordWrap; color: gallery.foreground
                    font.family: gallery.fontFamily; font.pixelSize: 12; lineHeight: 1.1
                }
                ControlsPreview {
                    objectName: "controlsDesktopPreview"
                    x: parent.width * 0.5; y: 14
                    width: parent.width * 0.5 - 14; height: parent.height - 28
                    dark: gallery.dark
                }
            }
            Repeater {
                model: gallery.sections
                delegate: Column {
                    id: section
                    required property var modelData
                    width: catalogColumn.width; spacing: 12
                    Text {
                        visible: gallery.category === "all"
                        text: section.modelData.label; color: gallery.secondary
                        font.family: gallery.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    Flow {
                        id: controlsFlow
                        width: parent.width; spacing: 10
                        Repeater {
                            model: section.modelData.controls
                            delegate: Item {
                                id: card
                                required property var modelData
                                readonly property bool added: gallery.controller && gallery.controller.ccControls.indexOf(modelData.id) >= 0
                                readonly property bool square: modelData.id === "nowplaying" || (section.modelData.id === "suggestions" && modelData.id === "desktop")
                                readonly property bool pill: !square && modelData.w > 1
                                readonly property int cells: square || pill ? 2 : 1
                                readonly property int columns: controlsFlow.width < 280 ? 2 : 4
                                width: ((controlsFlow.width - (columns - 1) * 10) / columns) * cells + (cells - 1) * 10
                                height: (square ? 132 : 66) + (pill || square ? 0 : 38)
                                opacity: gallery.dragging && gallery.actionId === modelData.id ? 0.5 : 1
                                activeFocusOnTab: true
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.label
                                Accessible.onPressAction: openActions()
                                function openActions() {
                                    var p = mapToItem(gallery, width / 2, 50);
                                    gallery.showActions(modelData.id, p.x, p.y);
                                }
                                Keys.onSpacePressed: openActions()
                                Keys.onReturnPressed: openActions()
                                ControlSurface {
                                    id: controlShape
                                    objectName: "galleryControl_" + card.modelData.id
                                    width: card.pill || card.square ? parent.width : Math.min(parent.width, 66)
                                    height: card.square ? 132 : 66
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    radius: card.square ? 24 : height / 2
                                    dark: gallery.dark; hovered: cardMouse.containsMouse
                                    pressed: cardMouse.pressed && !cardMouse.moved
                                    neutral: true
                                    focusVisible: card.activeFocus
                                    scale: pressed ? 0.97 : 1
                                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                                    ControlIcon {
                                        x: card.pill || card.square ? 16 : (parent.width - width)/2
                                        y: card.square ? 21 : (parent.height - height)/2
                                        width: 26; height: 26; kind: card.modelData.glyph
                                        color: "#ffffff"
                                    }
                                    Text {
                                        visible: card.pill || card.square
                                        x: card.pill ? 52 : 15; y: card.square ? parent.height - height - 16 : (parent.height-height)/2
                                        width: parent.width - x - 14; text: card.modelData.label
                                        color: "#ffffff"; font.family: gallery.fontFamily; font.pixelSize: 14; font.weight: Font.Medium
                                        wrapMode: Text.WordWrap
                                    }
                                    Rectangle {
                                        visible: card.added
                                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: -1
                                        width: 21; height: 21; radius: 10.5; color: "#007aff"; antialiasing: true
                                        border.width: 2; border.color: gallery.color
                                        ControlIcon { anchors.centerIn: parent; width: 13; height: 13; kind: "check"; color: "white" }
                                    }
                                }
                                Text {
                                    visible: !card.pill && !card.square
                                    y: 74; width: parent.width; text: card.modelData.label
                                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                    color: gallery.secondary; font.family: gallery.fontFamily; font.pixelSize: 12
                                }
                                MouseArea {
                                    id: cardMouse
                                    objectName: "galleryMouse_" + card.modelData.id
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    hoverEnabled: true; preventStealing: true
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    property point pressPoint
                                    property bool moved: false
                                    onPressed: mouse => {
                                        gallery.forceActiveFocus(Qt.MouseFocusReason);
                                        actions.visible = false;
                                        moved = false; pressPoint = mapToItem(gallery.dragLayer, mouse.x, mouse.y);
                                    }
                                    onPositionChanged: mouse => {
                                        if (!pressed || pressedButtons !== Qt.LeftButton) return;
                                        var p = mapToItem(gallery.dragLayer, mouse.x, mouse.y);
                                        if (!moved && Math.abs(p.x-pressPoint.x)+Math.abs(p.y-pressPoint.y) < 7) return;
                                        moved = true; gallery.dragging = true; gallery.actionId = card.modelData.id;
                                        gallery.controlDragged(card.modelData.id, p.x, p.y);
                                    }
                                    onReleased: mouse => {
                                        if (moved) {
                                            var p = mapToItem(gallery.dragLayer, mouse.x, mouse.y);
                                            gallery.dragging = false; gallery.controlDropped(card.modelData.id,p.x,p.y);
                                        }
                                    }
                                    onClicked: mouse => {
                                        if (moved) return;
                                        var p = mapToItem(gallery, mouse.x, mouse.y);
                                        gallery.showActions(card.modelData.id, p.x, p.y);
                                    }
                                    onCanceled: { gallery.dragging = false; gallery.dragCanceled(); }
                                }
                            }
                        }
                    }
                }
            }
            Text {
                visible: gallery.sections.length === 0
                width: parent.width; height: 120; verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: "No controls found.\nTry a different search."
                color: gallery.secondary; font.family: gallery.fontFamily; font.pixelSize: 14
            }
        }
    }
    Rectangle { x: gallery.contentLeft; y: parent.height - 62; width: parent.width - x - 20; height: 1; color: gallery.separator }
    Text {
        x: gallery.contentLeft; y: parent.height - 49; width: parent.width - x - 107
        height: 38
        text: gallery.message; color: gallery.secondary
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        font.family: gallery.fontFamily; font.pixelSize: 12
    }
    Button {
        id: doneButton
        objectName: "galleryDone"
        anchors.right: parent.right; anchors.rightMargin: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 17
        width: 80; height: 36; padding: 0
        text: "Done"; hoverEnabled: true
        Accessible.name: text
        scale: down ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        background: ControlSurface { dark: gallery.dark; prominent: true; hovered: doneButton.hovered; pressed: doneButton.down; focusVisible: doneButton.visualFocus }
        contentItem: Text { text: doneButton.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: gallery.fontFamily; font.pixelSize: 14; font.weight: Font.Medium }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        onClicked: gallery.finished()
    }

    // Inline context menu: stays on the same Wayland surface during a drag.
    MouseArea { visible: actions.visible; anchors.fill: parent; z: 99; onClicked: actions.visible = false }
    Rectangle {
        id: actions
        objectName: "controlActions"
        visible: false; z: 100
        width: Math.min(244, gallery.width - gallery.sidebarWidth - 16)
        height: actionColumn.height + 12; radius: 17; antialiasing: true
        color: gallery.dark ? "#353842" : "#fafbff"; border.color: gallery.separator
        readonly property var definition: Catalog.find(gallery.actionId)
        readonly property var rows: {
            if (!definition || !gallery.controller) return [];
            var id = gallery.actionId, cc = gallery.controller.ccControls.indexOf(id) >= 0;
            var pinned = gallery.controller.controlPinned(id);
            var rows = [
                {label: cc ? "Remove from Control Center" : "Add to Control Center", action: "cc", icon: "grid"},
                {label: pinned ? "Remove from Menu Bar" : "Add to Menu Bar", action: "bar", icon: "menubar"}
            ];
            if (gallery.actionDestination === "bar") {
                rows.push({label: "Move Left", action: "left", icon: "left"});
                rows.push({label: "Move Right", action: "right", icon: "right"});
            }
            if (cc && definition.sizes) definition.sizes.forEach(function(s) {
                rows.push({label: s[0].toUpperCase()+s.slice(1), action: s,
                    icon: Catalog.sizeName(id, gallery.controller.ccSizes) === s ? "check" : s});
            });
            return rows;
        }
        Column {
            id: actionColumn
            x: 6; y: 6; width: parent.width - 12; spacing: 2
            Repeater {
                model: actions.rows
                delegate: Button {
                    id: actionButton
                    required property var modelData
                    objectName: "controlAction_" + modelData.action
                    width: actionColumn.width; height: 38; padding: 0
                    hoverEnabled: true
                    Accessible.name: modelData.label
                    background: Rectangle {
                        radius: 11; antialiasing: true
                        color: actionButton.down ? "#0062cf" : actionButton.hovered || actionButton.visualFocus ? "#007aff" : "transparent"
                        Behavior on color { ColorAnimation { duration: 90 } }
                    }
                    contentItem: Item {
                        ControlIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; kind: actionButton.modelData.icon; color: actionButton.hovered || actionButton.visualFocus ? "white" : gallery.secondary }
                        Text { x: 38; width: parent.width - x - 8; anchors.verticalCenter: parent.verticalCenter; text: actionButton.modelData.label; elide: Text.ElideRight; color: actionButton.hovered || actionButton.visualFocus ? "white" : gallery.foreground; font.family: gallery.fontFamily; font.pixelSize: 12 }
                    }
                    onClicked: gallery.applyAction(modelData.action)
                }
            }
        }
    }
}
