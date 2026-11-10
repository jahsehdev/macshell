pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "Common" as Common

Column {
    id: preview
    required property var t
    property real value: Common.GlassMaterial.intensity
    property bool reducedTransparency: Common.DesktopPreferences.reduceTransparency
    property var materialSettings: null
    signal moved(real value)
    width: 360
    spacing: 10
    readonly property real amount: reducedTransparency ? 1 : Math.max(0, Math.min(1, value))
    readonly property color ink: t.dark ? "#f5f5f7" : "#202124"
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software

    // Only the scrolling page feeds the shader. The floating controls stay outside
    // that source so they refract the photo or address card beneath them.
    Rectangle {
        id: roundMask
        width: page.width; height: page.height
        radius: 20
        color: "white"
        layer.enabled: true
        visible: false
    }
    Item {
        id: page
        width: preview.width
        height: width * 0.67
        clip: true
        layer.enabled: !preview.software
        layer.effect: MultiEffect { maskEnabled: true; maskSource: roundMask }
        Flickable {
            id: document
            objectName: "appleParkPage"
            anchors.fill: parent
            contentWidth: width
            contentHeight: photo.height + addressCard.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Accessible.name: "Apple Park preview"
            Image {
                id: photo
                width: document.width
                height: page.height * 0.85
                source: Qt.resolvedUrl("assets/settings/apple-park.png")
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }
            Rectangle {
                id: addressCard
                y: photo.height
                width: document.width
                height: Math.max(140, details.implicitHeight + 44)
                color: preview.t.dark ? "#151514" : "#eae7df"
                Column {
                    id: details
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Text {
                        width: parent.width
                        text: "Welcome to Apple Park"
                        wrapMode: Text.WordWrap
                        color: preview.t.dark ? "#eeeeeb" : "#191918"
                        font.family: preview.t.fam; font.styleName: preview.t.fontStyleName || ""
                        font.pixelSize: Math.max(17, page.width * 0.049)
                        font.weight: Font.Bold
                    }
                    Text {
                        objectName: "appleParkAddress"
                        width: parent.width
                        text: "One Apple Park Way, Cupertino, CA 95014, United States"
                        wrapMode: Text.WordWrap
                        color: preview.t.dark ? "#b8b8b4" : "#65645f"
                        font.family: preview.t.fam; font.styleName: preview.t.fontStyleName || ""
                        font.pixelSize: Math.max(12, page.width * 0.032)
                        lineHeight: 1.25
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 5
            }
        }
        ShaderEffectSource {
            id: backdrop
            sourceItem: document
            live: preview.visible
            visible: false
        }
        MultiEffect {
            id: blur
            width: page.width; height: page.height
            source: backdrop
            blurEnabled: preview.amount > 0
            blurMax: 32
            blur: preview.amount * 0.95
            autoPaddingEnabled: false
            visible: false
        }
        ShaderEffectSource {
            id: blurredBackdrop
            sourceItem: blur
            live: true
            visible: false
        }
        // Toolbar positions follow the photo as the settings window resizes.
        Pill {
            x: page.width * 0.03; y: page.width * 0.03
            width: page.width * 0.27; height: page.width * 0.132
            GlassPreviewIcon {
                x: parent.width * 0.16
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height * 0.43; height: width
                kind: "share"; color: preview.ink
            }
            Row {
                x: parent.width * 0.65
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: preview.ink } }
            }
        }
        Pill {
            x: page.width * 0.33; y: page.width * 0.03
            width: page.width * 0.132; height: width
            GlassPreviewIcon {
                anchors.centerIn: parent
                width: parent.width * 0.46; height: width
                kind: "tabs"; color: preview.ink
            }
        }
        Pill {
            x: page.width * 0.49; y: page.width * 0.03
            width: page.width * 0.48; height: page.width * 0.132
            GlassPreviewIcon {
                x: parent.height * 0.27
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height * 0.40; height: width
                kind: "search"; color: preview.ink
                opacity: 0.7
            }
            Text {
                x: parent.height * 0.87
                anchors.verticalCenter: parent.verticalCenter
                text: "Search"
                color: preview.ink
                opacity: 0.8
                font.family: preview.t.fam; font.styleName: preview.t.fontStyleName || ""
                font.pixelSize: parent.height * 0.37
                font.weight: Font.Medium
            }
        }
    }

    // This local scene contains the page and its surrounding surface, never
    // the value label itself. Allocate its texture only while the label shows.
    Loader {
        id: valueBackdrop
        visible: false
        active: valueLabel.visible && !preview.software && !preview.reducedTransparency
        sourceComponent: Item {
            width: preview.width
            height: preview.height
            Rectangle { anchors.fill: parent; color: preview.t.dark ? "#303234" : "#f4f4f5" }
            ShaderEffectSource {
                width: page.width; height: page.height
                sourceItem: page
                hideSource: false
                live: true
            }
        }
    }

    Item {
        id: sliderRow
        width: preview.width
        height: 28
        z: 2
        property bool hoverReady: false
        GlassPreviewIcon {
            x: 0; anchors.verticalCenter: parent.verticalCenter
            width: 21; height: 21
            kind: "material"; color: preview.t.text2
        }
        Common.GlassSlider {
            id: slider
            objectName: "liquidGlassSlider"
            x: 29; width: parent.width - 58; height: parent.height
            from: 0; to: 1; stepSize: 0.01
            value: preview.value
            enabled: !preview.reducedTransparency
            opacity: enabled ? 1 : 0.45
            live: true
            focusPolicy: Qt.StrongFocus
            onHoveredChanged: sliderRow.hoverReady = false
            Accessible.name: "Liquid Glass"
            Accessible.description: "Adjust glass from clear to tinted"
            onMoved: preview.moved(value)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home) { preview.moved(from); event.accepted = true; }
                else if (event.key === Qt.Key_End) { preview.moved(to); event.accepted = true; }
            }
            dark: preview.t.dark
            accentColor: preview.t.accent
            trackColor: preview.t.track
            tickMarks: true
            materialOpacity: preview.materialSettings ? preview.materialSettings.effGlassOpacity : Common.DesktopPreferences.glassOpacity(0.42)
            glassBlur: preview.materialSettings ? preview.materialSettings.effGlassBlur : Common.DesktopPreferences.glassBlur(5)
            liquidStrength: preview.materialSettings ? preview.materialSettings.effGlassLiquid : Common.DesktopPreferences.glassLiquid(1)
            glassRim: preview.materialSettings ? preview.materialSettings.effGlassRim : Common.DesktopPreferences.glassRim(0.45)
        }
        Timer {
            interval: 350
            running: slider.hovered
            onTriggered: sliderRow.hoverReady = true
        }
        DockTooltip {
            id: valueLabel
            objectName: "liquidGlassValueLabel"
            text: Math.round(slider.value * 100) + "% tinted"
            fontFamily: preview.t.fam
            maxWidth: sliderRow.width - 4
            readonly property real knobCenter: slider.x + slider.handle.x + slider.handle.width / 2
            x: Math.max(2, Math.min(sliderRow.width - width - 2, knobCenter - width / 2))
            y: slider.y + slider.handle.y - height - 5
            pointerX: knobCenter - x
            visible: opacity > 0
            opacity: slider.enabled && (slider.pressed || slider.visualFocus || (slider.hovered && sliderRow.hoverReady)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Common.DesktopPreferences.anim(100) } }
            liquid: !preview.software && !preview.reducedTransparency
            dark: preview.t.dark
            surfaceOpacity: preview.materialSettings ? preview.materialSettings.effGlassOpacity : Common.DesktopPreferences.glassOpacity(0.42)
            glassBlur: preview.materialSettings ? preview.materialSettings.effGlassBlur : Common.DesktopPreferences.glassBlur(5)
            glassLiquid: preview.materialSettings ? preview.materialSettings.effGlassLiquid : Common.DesktopPreferences.glassLiquid(1)
            glassRim: preview.materialSettings ? preview.materialSettings.effGlassRim : Common.DesktopPreferences.glassRim(0.45)
            glassGrain: preview.materialSettings ? preview.materialSettings.effGlassGrain : Common.DesktopPreferences.glassGrain(0.03)
            backdrop: valueBackdrop.item as Item
            backdropOrigin: Qt.point(valueLabel.x, sliderRow.y + valueLabel.y)
        }
        GlassPreviewIcon {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 21; height: 21
            kind: "material"; filled: true; color: preview.t.text2
        }
    }
    Text {
        visible: preview.reducedTransparency
        width: preview.width
        text: "Turn off Reduce transparency to adjust Liquid Glass."
        wrapMode: Text.WordWrap
        color: preview.t.text2
        font.family: preview.t.fam; font.styleName: preview.t.fontStyleName || ""
        font.pixelSize: 11
    }

    component Pill: Item {
        id: pill
        Rectangle {
            anchors.fill: parent
            visible: preview.software
            radius: height / 2
            color: preview.t.dark ? Qt.rgba(0.16, 0.18, 0.19, 0.24 + preview.amount * 0.7)
                                  : Qt.rgba(1, 1, 1, 0.24 + preview.amount * 0.7)
        }
        Common.LiquidGlassSurface {
            anchors.fill: parent
            visible: !preview.software
            materialIntensity: preview.value
            fragmentShader: Qt.resolvedUrl("Common/LiquidGlass.frag.dock.qsb")
            src: preview.amount > 0 ? blurredBackdrop : backdrop
            itemSize: Qt.vector2d(width, height)
            glassSize: itemSize
            srcSize: Qt.vector2d(page.width, page.height)
            srcOffset: Qt.vector2d(pill.x, pill.y)
            pad: 0
            radius: height / 2
            bezel: height * 0.22
            dark: preview.t.dark ? 1 : 0
            debug: 0
            shadowAmt: 0
            squircle: 0
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 0.7
            border.color: preview.t.dark ? "#55ffffff" : "#90ffffff"
        }
    }
}
