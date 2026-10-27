import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "Common" as Common

Scope {
    id: root
    property var hub: null
    property var info: ({})
    property alias window: win
    readonly property bool dark: hub && hub.dock ? hub.dock.darkMode : false
    readonly property string fontFamily: hub && hub.dock ? hub.dock.fontFamily : "SF Pro Text"
    readonly property color foreground: dark ? "#f1f1f3" : "#424244"
    readonly property color secondary: dark ? "#a2a2a8" : "#8c8c91"
    readonly property var summaryRows: [
        { label: "Processor", value: info.processor || "Loading…" },
        { label: "Memory", value: info.memory || "Loading…" },
        { label: "Serial number", value: info.serial || "Loading…" },
        { label: "Linux", value: info.distro || "Loading…" }
    ]
    readonly property var hardwareRows: [
        { label: "Model", value: info.deviceName || "Loading…" },
        { label: "Manufacturer", value: info.vendor || "Loading…" },
        { label: "Processor", value: info.processorFull || "Loading…" },
        { label: "Logical processors", value: String(info.cpuThreads || "—") },
        { label: "Memory", value: info.memory || "Loading…" },
        { label: "Graphics", value: info.graphics || "Loading…" },
        { label: "Serial number", value: info.serial || "Loading…" },
        { label: "Firmware", value: info.firmware || "Loading…" }
    ]
    readonly property var softwareRows: [
        { label: "Operating system", value: info.distro || "Loading…" },
        { label: "Release", value: info.version || "Rolling release" },
        { label: "Kernel", value: info.kernel || "Loading…" },
        { label: "Architecture", value: info.architecture || "Loading…" },
        { label: "Desktop", value: info.desktop || "Hyprland" },
        { label: "System volume", value: info.storage || "Loading…" }
    ]

    function refresh() { if (!probe.running) probe.running = true; }
    function open() {
        refresh();
        if (!win.visible) {
            const area = win.screen;
            win.x = area.virtualX + (area.width - win.width) / 2;
            win.y = area.virtualY + (area.height - win.height) / 2;
        }
        win.visible = true;
        win.raise();
        win.requestActivate();
    }
    function close() { win.visible = false; }
    function moreInfo() {
        if (!hub) return;
        hub.openSettings("system");
        close();
    }

    Process {
        id: probe
        command: ["python3", "-B", Quickshell.shellPath("bin/system_info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (value && typeof value === "object" && value.deviceName) root.info = value;
                } catch (error) { console.warn("[about-system]", String(error)); }
            }
        }
    }

    Window {
        id: win
        objectName: "aboutSystemWindow"
        title: "About This Linux"
        width: 360; height: 580
        minimumWidth: width; maximumWidth: width
        minimumHeight: height; maximumHeight: height
        visible: false
        color: "transparent"
        flags: Qt.Dialog | Qt.FramelessWindowHint

        Shortcut { sequences: ["Escape", "Ctrl+W"]; enabled: win.visible; onActivated: root.close() }

        Common.ContinuousRectangle {
            anchors.fill: parent
            radius: 14
            color: root.dark ? "#272729" : "#e4e4e5"
            border.width: 1
            border.color: root.dark ? "#555558" : "#eeeeef"

            Item {
                width: parent.width; height: 43
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                WindowControls {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    dark: root.dark
                    windowActive: win.active
                    closeOnly: true
                    onCloseClicked: root.close()
                }
            }

            Image {
                id: deviceImage
                anchors.horizontalCenter: parent.horizontalCenter
                y: 86; width: 230; height: 154
                source: Qt.resolvedUrl(root.info.portable ? "assets/about/laptop.svg" : "assets/about/desktop.svg")
                sourceSize: Qt.size(690, 462)
                fillMode: Image.PreserveAspectFit
                smooth: true
                Accessible.role: Accessible.Graphic
                Accessible.name: root.info.formFactor || "Computer"
            }

            Text {
                id: deviceName
                x: 20; y: 269; width: parent.width - 40
                text: root.info.deviceName || "This Computer"
                color: root.foreground
                font.family: root.fontFamily; font.pixelSize: 28; font.weight: Font.Bold
                minimumPixelSize: 19; fontSizeMode: Text.HorizontalFit
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                x: 20; y: 308; width: parent.width - 40
                text: root.info.formFactor ? root.info.formFactor + " · " + root.info.architecture : "System information"
                color: root.secondary
                font.family: root.fontFamily; font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }

            GridLayout {
                x: 25; y: 352; width: parent.width - 50
                columns: 2; columnSpacing: 12; rowSpacing: 5
                Repeater {
                    model: root.summaryRows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            Layout.preferredWidth: 103; Layout.alignment: Qt.AlignTop
                            text: modelData.label
                            color: root.foreground; horizontalAlignment: Text.AlignRight
                            font.family: root.fontFamily; font.pixelSize: 14
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.value; textFormat: Text.PlainText
                            color: modelData.value === "Not available" ? root.secondary : root.foreground
                            font.family: root.fontFamily; font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                }
            }

            Button {
                id: moreInfo
                objectName: "aboutMoreInfo"
                anchors.horizontalCenter: parent.horizontalCenter
                y: 475; width: 120; height: 29
                text: "More Info…"
                font.family: root.fontFamily; font.pixelSize: 14
                Accessible.name: "More system information"
                background: Rectangle {
                    radius: 7
                    color: moreInfo.down ? (root.dark ? "#555558" : "#bcbcbf")
                         : moreInfo.hovered ? (root.dark ? "#4c4c50" : "#cccccf")
                         : (root.dark ? "#414145" : "#d1d1d3")
                    border.width: moreInfo.visualFocus ? 2 : 0
                    border.color: Common.ThemeColors.accentFor("shell")
                }
                contentItem: Text {
                    text: moreInfo.text; font: moreInfo.font; color: root.foreground
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.moreInfo()
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 529
                text: "MacShell\nPowered by Linux"
                color: root.secondary
                font.family: root.fontFamily; font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.2
            }
        }
    }
}
