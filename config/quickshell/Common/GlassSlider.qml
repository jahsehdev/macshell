pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls

// One native input control for Settings, popovers, Launchpad and media seeking.
Controls.Slider {
    id: slider
    property bool dark: false
    property color accentColor: "#0a84ff"
    property color trackColor: dark ? "#505054" : "#bfc0c4"
    property color handleColor: dark ? "#c9ced4" : "#f1f2f4"
    property color surfaceColor: dark ? "#303234" : "#d8d8d8"
    property real uiScale: 1
    property real materialOpacity: DesktopPreferences.glassOpacity(GlassMaterial.baseOpacity)
    property real glassBlur: DesktopPreferences.glassBlur(GlassMaterial.baseBlur)
    property real liquidStrength: DesktopPreferences.glassLiquid(GlassMaterial.baseLiquid)
    property real glassRim: DesktopPreferences.glassRim(GlassMaterial.baseRim)
    readonly property var material: GlassMaterial.profile(GlassMaterial.intensity)
    property bool tickMarks: false
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property real pressProgress: thumb.pressProgress
    readonly property real knobCenter: handle.x + handle.width / 2
    implicitWidth: 230
    implicitHeight: 30 * uiScale
    leftPadding: 0; rightPadding: 0
    topPadding: 0; bottomPadding: 0
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    live: true
    snapMode: stepSize > 0 ? Controls.Slider.SnapAlways : Controls.Slider.NoSnap
    opacity: enabled ? 1 : 0.4

    background: Item {
        x: slider.leftPadding
        y: 0
        width: slider.availableWidth
        height: slider.height
        Rectangle {
            id: track
            x: thumb.width / 2
            y: (parent.height - height) / 2
            width: Math.max(0, parent.width - thumb.width)
            height: 6 * slider.uiScale
            radius: height / 2
            color: slider.trackColor
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height; radius: height / 2
                color: slider.accentColor
            }
        }
        Repeater {
            model: slider.tickMarks ? 3 : 0
            Rectangle {
                required property int index
                x: track.x + index * track.width / 2 - width / 2
                y: track.y + track.height + 5 * slider.uiScale
                width: 2 * slider.uiScale; height: width; radius: width / 2
                color: slider.trackColor
            }
        }
    }
    handle: Item {
        id: thumb
        objectName: "glassSliderHandle"
        implicitWidth: 32 * slider.uiScale
        implicitHeight: 21 * slider.uiScale
        width: implicitWidth; height: implicitHeight
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: (slider.height - height) / 2
        property real pressProgress: slider.pressed ? 1 : 0
        Behavior on pressProgress {
            NumberAnimation {
                duration: DesktopPreferences.anim(slider.pressed ? 180 : 220)
                easing.type: Easing.OutBack
                easing.overshoot: 1.1
            }
        }
        scale: 1 + 0.22 * pressProgress
        readonly property bool glassAllowed: !slider.software && !DesktopPreferences.reduceTransparency
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: slider.software && slider.pressed && !DesktopPreferences.reduceTransparency
                ? (slider.dark ? Qt.rgba(0.13, 0.18, 0.24, 0.5) : Qt.rgba(0.70, 0.74, 0.79, 0.3))
                : slider.handleColor
            opacity: thumb.glassAllowed ? 1 - Math.max(0, Math.min(1, thumb.pressProgress)) : 1
        }
        Loader {
            objectName: "glassSliderPressedEffect"
            anchors.fill: parent
            active: slider.visible && thumb.glassAllowed && thumb.pressProgress > 0.005
            opacity: Math.max(0, Math.min(1, thumb.pressProgress))
            sourceComponent: localGlass
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            // Keep the visible edge below one logical pixel while scaling.
            border.width: (slider.visualFocus ? 0.8 : 0.55) / thumb.scale
            border.color: slider.visualFocus ? Qt.rgba(slider.accentColor.r, slider.accentColor.g, slider.accentColor.b, 0.7)
                : slider.dark ? "#557f91a5" : "#55515e6c"
        }
    }
    Component {
        id: localGlass
        Item {
            ShaderEffectSource {
                id: trackSource
                sourceItem: slider.background
                hideSource: false
                live: true
                visible: false
            }
            // Keep the narrow track sharp: pre-blurring it erased the lens
            // distortion. The material tint still follows system preferences.
            ShaderEffect {
                anchors.fill: parent
                fragmentShader: Qt.resolvedUrl("LiquidGlass-slider.frag.qsb")
                property variant src: trackSource
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d srcSize: Qt.vector2d(slider.background.width, slider.background.height)
                property vector2d srcOffset: Qt.vector2d(thumb.x - slider.background.x, thumb.y - slider.background.y)
                property vector4d baseColor: Qt.vector4d(slider.surfaceColor.r, slider.surfaceColor.g, slider.surfaceColor.b, 1)
                property real dark: slider.dark ? 1 : 0
                property real spread: thumb.scale
                property vector4d optics: Qt.vector4d(slider.material.thickness, slider.material.dispersion, slider.material.magnify, slider.material.saturation)
                property vector4d finish: Qt.vector4d(slider.material.tint, slider.glassRim, DesktopPreferences.glassGrain(slider.material.grain), slider.material.blurPx)
            }
        }
    }
}
