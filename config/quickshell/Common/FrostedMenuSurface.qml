pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Flat menu vibrancy, independent of the Liquid Glass optical preferences.
// The dedicated backdrop never includes the menu itself.
Item {
    id: plate
    property bool dark: true
    property real radius: CornerTheme.menuRadius
    property Item backdrop: null
    property url wallpaperSource: ""
    property size screenSize: Qt.size(1920, 1080)
    property point samplePosition: Qt.point(0, 0)
    property color borderTint: "#8A9AB5"
    property bool opaque: DesktopPreferences.reduceTransparency
    property bool outline: true
    readonly property real blurRadius: 32
    readonly property url shaderUrl: Qt.resolvedUrl("LiquidGlass-frosted-menu.frag.qsb")
    readonly property bool ready: material.item !== null && material.item.ready

    ContinuousRectangle {
        anchors.fill: parent
        radius: plate.radius
        color: plate.dark ? "#1F1F21" : "#F7F7FA"
        visible: !plate.ready
    }
    Loader {
        id: material
        anchors.fill: parent
        active: plate.visible && !plate.opaque && GraphicsInfo.api !== GraphicsInfo.Software
            && (plate.backdrop !== null || plate.wallpaperSource.toString() !== "")
        sourceComponent: Item {
            id: glass
            readonly property real margin: 72
            readonly property real ds: plate.blurRadius >= 8 ? 0.5 : 1
            readonly property bool sourceReady: plate.backdrop !== null || wallpaper.status === Image.Ready
            readonly property bool ready: sourceReady && shader.status === ShaderEffect.Compiled
            Image {
                id: wallpaper
                width: plate.screenSize.width; height: plate.screenSize.height
                source: plate.backdrop ? "" : plate.wallpaperSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: plate.backdrop === null
            }
            ShaderEffectSource {
                id: capture
                sourceItem: plate.backdrop || wallpaper
                // Both sources are dedicated backdrop items, never the menu.
                hideSource: plate.backdrop === null
                visible: false; live: true
                sourceRect: Qt.rect(plate.samplePosition.x - glass.margin,
                    plate.samplePosition.y - glass.margin,
                    plate.width + 2 * glass.margin, plate.height + 2 * glass.margin)
                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * glass.ds)),
                    Math.max(1, Math.round(sourceRect.height * glass.ds)))
            }
            MultiEffect {
                id: frost
                source: capture
                width: capture.sourceRect.width * glass.ds
                height: capture.sourceRect.height * glass.ds
                blurEnabled: true; blurMax: 64
                blur: Math.min(1, plate.blurRadius * 1.4 * glass.ds / 64)
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource {
                id: blurred
                sourceItem: frost
                visible: false; live: true
            }
            LiquidGlassSurface {
                id: shader
                objectName: "frostedMenuShader"
                anchors.fill: parent
                visible: glass.sourceReady
                fragmentShader: plate.shaderUrl
                src: blurred
                itemSize: Qt.vector2d(width, height)
                glassSize: itemSize
                srcSize: Qt.vector2d(capture.sourceRect.width, capture.sourceRect.height)
                srcOffset: Qt.vector2d(glass.margin, glass.margin)
                pad: 0
                radius: plate.radius
                dark: plate.dark ? 1 : 0
                debug: 0
                shadowAmt: 0
            }
        }
    }
    // Same outside hairline and faint wallpaper-tinted edge as MenuBorder.
    ContinuousRectangle {
        visible: plate.outline
        anchors.fill: parent; anchors.margins: -1
        radius: plate.radius + 1; color: "transparent"
        border.width: 1
        border.color: plate.dark ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0, 0, 0, 0.14)
    }
    ContinuousRectangle {
        visible: plate.outline
        anchors.fill: parent
        radius: plate.radius; color: "transparent"
        border.width: 1.25
        border.color: Qt.rgba(plate.borderTint.r, plate.borderTint.g, plate.borderTint.b, plate.dark ? 0.16 : 0.12)
    }
}
