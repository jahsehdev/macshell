import "../Common" as Common
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  IconView — a theme icon masked to an Apple squircle. The shadow is NOT
//  rendered here: AppTile paints the shared assets/icon-shadow.png behind it,
//  so opening a page never creates one blur effect per icon.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string iconName: ""
    property string iconPath: ""
    property string fallbackText: ""
    property color fallbackColor: "transparent"
    property real cornerRadius: Theme.iconRadius
    property bool forceMask: Theme.forceSquircleMask
    property bool showInnerEdge: false

    implicitWidth: Theme.iconSize
    implicitHeight: Theme.iconSize

    readonly property bool isFilePath: iconPath !== "" || iconName.indexOf("/") === 0
    readonly property string resolvedPath: {
        if (iconPath !== "")
            return iconPath;
        if (iconName === "")
            return "";
        if (iconName.indexOf("/") === 0)
            return iconName;
        return Quickshell.iconPath(iconName, true);
    }
    readonly property bool hasIcon: resolvedPath !== ""
    readonly property bool useFallback: !hasIcon || fallbackColor.a > 0 && iconName === ""
    readonly property color effectiveFallback: fallbackColor.a > 0
        ? fallbackColor
        : Theme.fallbackPalette[Math.abs(hash(fallbackText || iconName)) % Theme.fallbackPalette.length]

    function hash(s) {
        let h = 0;
        for (let i = 0; i < s.length; ++i)
            h = ((h << 5) - h + s.charCodeAt(i)) | 0;
        return h;
    }

    Item {
        id: content
        visible: false

        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        layer.smooth: true

        Image {
            anchors.fill: parent
            visible: root.hasIcon && !root.useFallback
            source: root.hasIcon ? root.resolvedPath : ""
            sourceSize.width: Math.max(32, Math.round(root.width * 2))
            sourceSize.height: Math.max(32, Math.round(root.height * 2))
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            cache: true
        }

        Squircle {
            anchors.fill: parent
            visible: root.useFallback
            radius: root.cornerRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments

            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height
                GradientStop { position: 0.0; color: Qt.lighter(root.effectiveFallback, 1.18) }
                GradientStop { position: 1.0; color: Qt.darker(root.effectiveFallback, 1.20) }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.useFallback
            text: root.fallbackText !== "" ? root.fallbackText.charAt(0).toUpperCase() : "?"
            color: Qt.rgba(1, 1, 1, 0.94)
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(root.height * 0.44))
            font.weight: Font.DemiBold
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.20)
        }

    }

    // Apply appearance after drawing the source but before the existing mask.
    // The source layer is already needed for masking, so there is no extra capture.
    // hidden mask (still rendered into its own layer so MultiEffect can sample it)
    Item {
        id: maskSource

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Squircle {
            anchors.fill: parent
            radius: root.cornerRadius
            exponent: Theme.squircleExponent
            segmentsPerCorner: Theme.squircleSegments
            fillColor: "white"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: content
        layer.enabled: Common.IconStyle.effectMode !== 0
        layer.effect: Common.IconStyleEffect {}
        maskEnabled: root.forceMask
        maskSource: maskSource
    }
}
