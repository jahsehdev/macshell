pragma ComponentBehavior: Bound
import "Common" as Corners
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: galleryWindow
    required property var host
    screen: host.desktopScreen
    anchors.bottom: true
    margins.bottom: 96
    implicitWidth: Math.max(420, Math.min(860, host.screenSize()[0] - 48))
    implicitHeight: Math.max(280, Math.min(386, host.screenSize()[1] - 180))
    visible: host.editing
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "macwidgets-gallery"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    mask: Region { item: gallery }

    Corners.ContinuousRectangle {
        id: gallery
        anchors.fill: parent
        radius: 26
        readonly property bool dark: galleryWindow.host.darkGlass
        readonly property string fam: galleryWindow.host.fontFamily
        readonly property color fg: dark ? "#F2F2F5" : "#242428"
        readonly property color muted: dark ? "#A8A8B2" : "#696972"
        readonly property var types: [
            { type: "weather", name: "Weather", icon: "weather-clear", hint: "Conditions and forecast" },
            { type: "calendar", name: "Calendar", icon: "view-calendar", hint: "Your date at a glance" },
            { type: "clock", name: "Clock", icon: "preferences-system-time", hint: "Local time, live" },
            { type: "player", name: "Now Playing", icon: "multimedia-player", hint: "Music, controls and lyrics" },
            { type: "image", name: "Photos", icon: "image-x-generic", hint: "Choose a favourite picture" }
        ]
        property int category: 0
        property int styleIndex: 0
        property string query: ""
        readonly property var chosen: types[category]
        readonly property var styles: chosen.type === "image" ? ["normal"] : ["system"]
        color: dark ? "#EE22242C" : "#EEF4F4F7"
        border.width: 1
        border.color: dark ? "#50FFFFFF" : "#30000000"
        focus: true
        Keys.onEscapePressed: galleryWindow.host.finishEditing()

        Text {
            x: 23; y: 20
            text: "Widgets"
            color: gallery.fg
            font.family: gallery.fam; font.pixelSize: 21; font.weight: Font.DemiBold
        }
        Text {
            x: 23; y: 48
            text: "Add a widget, then drag it into place."
            color: gallery.muted
            font.family: gallery.fam; font.pixelSize: 12
        }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            x: parent.width - 99; y: 22; width: 76; height: 30; radius: 9
            color: doneMouse.pressed ? "#1B5AB7" : "#2878E2"
            Text { anchors.centerIn: parent; text: "Done"; color: "white"; font.family: gallery.fam; font.pixelSize: 13; font.weight: Font.DemiBold }
            MouseArea { id: doneMouse; anchors.fill: parent; onClicked: galleryWindow.host.finishEditing() }
        }
        Corners.ContinuousRectangle { cornerSmoothing: 0;
            x: 20; y: 82; width: 150; height: 30; radius: 8
            color: gallery.dark ? "#20000000" : "#15000000"
            TextInput {
                selectionColor: Corners.ThemeColors.selectionFor("shell", gallery.dark)
                selectedTextColor: Corners.ThemeColors.selectedTextFor("shell", gallery.dark)
                id: search
                anchors.fill: parent; anchors.margins: 8
                color: gallery.fg
                font.family: gallery.fam; font.pixelSize: 12
                clip: true; selectByMouse: true
                onTextChanged: gallery.query = text.trim().toLowerCase()
                Text { anchors.fill: parent; visible: search.text === ""; text: "Search widgets"; color: gallery.muted; font: search.font }
            }
        }
        Column {
            x: 14; y: 125; width: 162; spacing: 3
            Repeater {
                model: gallery.types
                delegate: Corners.ContinuousRectangle { cornerSmoothing: 0;
                    id: typeRow
                    required property int index
                    required property var modelData
                    width: 162
                    visible: gallery.query === "" || modelData.name.toLowerCase().indexOf(gallery.query) >= 0
                    height: visible ? 37 : 0
                    radius: 9
                    color: gallery.category === index ? "#2878E2" : (categoryMouse.containsMouse ? "#16888888" : "transparent")
                    Text {
                        x: 13; anchors.verticalCenter: parent.verticalCenter
                        text: typeRow.modelData.name
                        color: gallery.category === typeRow.index ? "white" : gallery.fg
                        font.family: gallery.fam; font.pixelSize: 13
                    }
                    MouseArea {
                        id: categoryMouse
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: { gallery.category = typeRow.index; gallery.styleIndex = 0; }
                    }
                }
            }
        }
        Corners.ContinuousRectangle { x: 188; y: 84; width: 1; height: parent.height - 107; color: gallery.dark ? "#18FFFFFF" : "#16000000" }
        Text {
            x: 209; y: 84
            text: gallery.chosen.name
            color: gallery.fg
            font.family: gallery.fam; font.pixelSize: 16; font.weight: Font.DemiBold
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 23
            y: 82; spacing: 4
            Repeater {
                model: gallery.styles
                delegate: Corners.ContinuousRectangle { cornerSmoothing: 0;
                    id: styleButton
                    required property int index
                    required property string modelData
                    width: styleText.implicitWidth + 18; height: 26; radius: 7
                    color: gallery.styleIndex === index ? (gallery.dark ? "#40FFFFFF" : "white") : "transparent"
                    Text {
                        id: styleText
                        anchors.centerIn: parent
                        text: ({ system: "Follows Appearance", liquid: "Glass", normal: gallery.chosen.type === "image" ? "Photo" : "Color", light: "Light", dark: "Dark" })[styleButton.modelData]
                        color: gallery.fg
                        font.family: gallery.fam; font.pixelSize: 12
                    }
                    MouseArea { anchors.fill: parent; onClicked: gallery.styleIndex = styleButton.index }
                }
            }
        }
        Flickable {
            id: previews
            x: 205; y: 120; width: parent.width - 225; height: parent.height - 166
            clip: true
            contentWidth: cards.width
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: cards
                spacing: 12
                Repeater {
                    model: ["small", "medium", "large"]
                    delegate: Corners.ContinuousRectangle {
                        cornerSmoothing: 0
                        id: card
                        required property string modelData
                        readonly property var dimensions: galleryWindow.host.dims(modelData)
                        readonly property real previewScale: Math.min(154 / dimensions[0], (height - 80) / dimensions[1])
                        width: 180; height: previews.height
                        radius: 17
                        color: addMouse.containsMouse ? (gallery.dark ? "#22FFFFFF" : "#10000000") : (gallery.dark ? "#0AFFFFFF" : "#08000000")
                        Item {
                            x: (parent.width - card.dimensions[0] * card.previewScale) / 2
                            y: 12 + (parent.height - 80 - card.dimensions[1] * card.previewScale) / 2
                            width: card.dimensions[0]; height: card.dimensions[1]
                            scale: card.previewScale
                            transformOrigin: Item.TopLeft
                            WidgetVisual {
                                anchors.fill: parent
                                host: galleryWindow.host
                                wtype: gallery.chosen.type
                                wstyle: gallery.styles[Math.min(gallery.styleIndex, gallery.styles.length - 1)]
                                wsize: card.modelData
                                preview: true
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - 54
                            text: galleryWindow.host.sizeNames[card.modelData]
                            color: gallery.fg
                            font.family: gallery.fam; font.pixelSize: 12
                        }
                        Corners.ContinuousRectangle { cornerSmoothing: 0;
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - 34
                            width: 72; height: 26; radius: 8
                            color: "#2878E2"
                            Text { anchors.centerIn: parent; text: "+ Add"; color: "white"; font.family: gallery.fam; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        MouseArea {
                            id: addMouse
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                if (gallery.chosen.type === "image") galleryWindow.host.pickImage("", card.modelData);
                                else galleryWindow.host.addWidget(gallery.chosen.type,
                                    gallery.styles[Math.min(gallery.styleIndex, gallery.styles.length - 1)], card.modelData);
                            }
                        }
                    }
                }
            }
        }
        Text {
            x: 209; y: parent.height - 32; width: parent.width - 232
            text: galleryWindow.host.pickError || "Widgets stay on the desktop when you click Done."
            color: galleryWindow.host.pickError ? "#F08080" : gallery.muted
            font.family: gallery.fam; font.pixelSize: 12
            elide: Text.ElideRight
        }
    }
}
