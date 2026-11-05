pragma ComponentBehavior: Bound
import "Common/CornerMath.js" as Curve
import "Common" as Corners
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// One continuous capsule and rounded tail, with the Dock's own material settings.
Item {
    id: tip
    property string text: ""
    property string fontFamily: "SF Pro Text"
    property string fontStyleName: ""
    property real maxWidth: 360
    property real pointerX: width / 2
    property bool pointerUp: false
    property bool liquid: false
    property bool frosted: false
    property bool dark: true
    property bool highContrast: false
    property real surfaceOpacity: 0.42
    property real glassBlur: 5
    property real glassLiquid: 1
    property real glassRim: 0.45
    property real glassGrain: 0.03
    // Same deep lens and fine rim as GlassMaterialPreview's pills.
    // qsb --qt6 -D DOCK_TOOLTIP -D DOCK_THIN_BORDER -o docktooltip-shared-material-v4.frag.qsb liquidglass.frag
    property url shaderUrl: Qt.resolvedUrl("docktooltip-shared-material-v4.frag.qsb")
    property bool glassFailed: false
    property bool backdropReady: true
    readonly property bool useLiquid: liquid && !frosted && backdrop !== null && backdropReady && !glassFailed
    property Item backdrop: null
    // Top-left in the shared, screen-sized backdrop. Includes icon magnification/lift.
    property point backdropOrigin: Qt.point(0, 0)
    readonly property real captureMargin: 82 // shader padding (10) + blur/refraction reach (72)
    readonly property rect requestedCaptureRect: Qt.rect(backdropOrigin.x - captureMargin,
        backdropOrigin.y - captureMargin, width + 2 * captureMargin, height + 2 * captureMargin)
    // Screen-space surface under the body, supplied by the Dock compositor.
    // Local previews can use their entire scene without a window boundary.
    property rect backdropBounds: requestedCaptureRect
    readonly property rect captureRect: {
        const left = Math.max(requestedCaptureRect.x, backdropBounds.x);
        const top = Math.max(requestedCaptureRect.y, backdropBounds.y);
        const right = Math.min(requestedCaptureRect.x + requestedCaptureRect.width, backdropBounds.x + backdropBounds.width);
        const bottom = Math.min(requestedCaptureRect.y + requestedCaptureRect.height, backdropBounds.y + backdropBounds.height);
        return Qt.rect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    }
    readonly property real bodyHeight: 32
    readonly property real tailHeight: 7
    readonly property real tailHalfWidth: 9
    readonly property real edgePadding: 16
    readonly property real tailX: Math.max(bodyHeight / 2 + tailHalfWidth,
        Math.min(width - bodyHeight / 2 - tailHalfWidth, pointerX))
    implicitWidth: Math.min(maxWidth, Math.max(60, label.implicitWidth + edgePadding * 2))
    implicitHeight: bodyHeight + tailHeight
    width: implicitWidth
    height: implicitHeight

    function outline(inset) {
        // Full capsule ends stay circular regardless of the global corner style.
        return Curve.tailPath(width,bodyHeight,bodyHeight/2,tailHeight,tailX,tailHalfWidth,0,inset);
    }

    // Frosted uses the menu bar's fixed Apps-panel material. The macdock
    // layer rule supplies actual backdrop blur without window exports or lenses.
    // Normal Blur uses the same compositor layer rule and tint as the Dock.
    // The tail is part of the outline, so there is no seam or doubled alpha.
    Shape {
        id: normal
        anchors.fill: parent
        visible: !tip.useLiquid
        transform: Scale { origin.y: tip.height / 2; yScale: tip.pointerUp ? -1 : 1 }
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            shadowEnabled: false
            shadowColor: Qt.rgba(0, 0, 0, 0.22)
            shadowBlur: 0.45
            shadowVerticalOffset: 3
        }
        ShapePath {
            // Keep the compositor blur active while a window capture is pending
            // or failed, including at the Clear preset's zero tint setting.
            fillColor: tip.frosted
                ? (tip.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.86) : Qt.rgba(0.97, 0.97, 0.98, 0.86))
                : (tip.dark ? Qt.rgba(0.10, 0.10, 0.11, Math.max(0.24, tip.surfaceOpacity))
                            : Qt.rgba(1, 1, 1, Math.max(0.24, tip.surfaceOpacity * 0.55)))
            strokeWidth: 1
            strokeColor: tip.frosted
                ? (tip.dark ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0, 0, 0, 0.14))
                : (tip.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.12))
            PathSvg { path: tip.outline(0.5) }
        }
        ShapePath {
            fillColor: "transparent"
            strokeWidth: 1
            strokeColor: tip.frosted
                ? (tip.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55))
                : (tip.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.45))
            PathSvg { path: tip.outline(1.5) }
        }
    }

    // Reuses MacShell's backdrop and Liquid Glass optics; no extra window captures.
    // The entire effect is unloaded once the tooltip fades out.
    Loader {
        anchors.fill: parent
        active: tip.useLiquid && tip.visible && tip.opacity > 0
        sourceComponent: Item {
            id: glass
            readonly property real padding: 10
            readonly property real materialBlur: Corners.GlassMaterial.blurRadius(tip.glassBlur)
            readonly property real ds: materialBlur >= 8 ? 0.5 : 1
            readonly property real blurAmount: materialBlur * 1.4 * ds / 64
            ShaderEffectSource {
                id: capture
                sourceItem: tip.backdrop
                hideSource: true
                live: true
                visible: false
                sourceRect: tip.captureRect
                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * glass.ds)),
                                     Math.max(1, Math.round(sourceRect.height * glass.ds)))
            }
            MultiEffect {
                id: blur1
                source: capture
                width: capture.sourceRect.width * glass.ds
                height: capture.sourceRect.height * glass.ds
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1, glass.blurAmount)
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource { id: blurred; sourceItem: blur1; live: true; visible: false }
            MultiEffect {
                id: blur2
                source: blurred
                width: blur1.width; height: blur1.height
                blurEnabled: glass.blurAmount > 1
                blurMax: 64
                blur: Math.max(0, Math.min(1, glass.blurAmount - 1))
                autoPaddingEnabled: false
                visible: false
            }
            ShaderEffectSource {
                id: extraBlurred
                sourceItem: glass.blurAmount > 1 ? blur2 : null
                live: true
                visible: false
            }
            ShaderEffect {
                x: -glass.padding; y: -glass.padding
                width: tip.width + 2 * glass.padding
                height: tip.height + 2 * glass.padding
                fragmentShader: tip.shaderUrl
                property variant src: glass.blurAmount > 1 ? extraBlurred : blurred
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(tip.width, tip.height)
                property vector2d srcSize: Qt.vector2d(capture.sourceRect.width, capture.sourceRect.height)
                property vector2d srcOffset: Qt.vector2d(tip.backdropOrigin.x - glass.padding - tip.captureRect.x,
                                                        tip.backdropOrigin.y - glass.padding - tip.captureRect.y)
                property real pad: glass.padding
                property real radius: tip.bodyHeight / 2
                property real bezel: tip.bodyHeight * 0.36
                property real thickness: 30 * tip.glassLiquid
                property real dispersion: 0.06 * tip.glassLiquid
                property real blurPx: 1.5
                property real tintMix: Math.max(0.06 + Corners.GlassMaterial.intensity * 0.88,
                    Corners.DesktopPreferences.glassTint(tip.surfaceOpacity, 0.55))
                property real saturation: 1.25
                property real dark: tip.dark ? 1 : 0
                property real debug: 0
                property real rim: tip.glassRim
                property real grain: tip.glassGrain
                property real magnify: 0.08 * tip.glassLiquid
                property real shadowAmt: 0   // liquid glass: no drop shadow
                property real rimTint: 0
                property real ringW: 0
                property real flatInner: 0
                property real squircle: 0
                property real bodyHeight: tip.bodyHeight
                property real tailHeight: tip.tailHeight
                property real tailX: tip.tailX
                property real tailWidth: tip.tailHalfWidth
                property real pointerUp: tip.pointerUp ? 1 : 0
                property vector4d backdropBounds: Qt.vector4d(
                    Math.max(0, tip.backdropBounds.x - tip.captureRect.x),
                    Math.max(0, tip.backdropBounds.y - tip.captureRect.y),
                    Math.min(tip.captureRect.width, tip.backdropBounds.x + tip.backdropBounds.width - tip.captureRect.x),
                    Math.min(tip.captureRect.height, tip.backdropBounds.y + tip.backdropBounds.height - tip.captureRect.y))
                onStatusChanged: if (status === ShaderEffect.Error) {
                    console.warn("[macdock-tooltip] Liquid Glass shader:", log);
                    tip.glassFailed = true;
                }
            }
        }
    }

    // A contrast veil sits above the optics and below the label. Keeping it
    // separate preserves refraction/rim while bounding bright artwork behind
    // white text (and dark content behind light-theme labels).
    Shape {
        anchors.fill: parent
        visible: tip.highContrast
        transform: Scale { origin.y: tip.height/2; yScale: tip.pointerUp?-1:1 }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: tip.dark ? Qt.rgba(0.035,0.04,0.05,0.60) : Qt.rgba(1,1,1,0.78)
            strokeWidth: 1
            strokeColor: tip.dark ? Qt.rgba(1,1,1,0.22) : Qt.rgba(0,0,0,0.16)
            PathSvg {path:tip.outline(0.5)}
        }
    }

    Text {
        id: label
        objectName:"dockTooltipLabel"
        x: tip.edgePadding
        y: (tip.pointerUp ? tip.tailHeight : 0) + (tip.bodyHeight - height) / 2
        width: tip.width - tip.edgePadding * 2
        text: tip.text
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        color: tip.highContrast && tip.dark ? "#FFFFFF" : tip.dark ? "#f5f5f7" : "#1d1d1f"
        font.pixelSize: tip.highContrast ? 14 : 13
        font.weight: tip.highContrast ? Font.DemiBold : Font.Normal
        style: tip.highContrast ? Text.Raised : Text.Normal
        styleColor: tip.dark ? "#B3000000" : "#AAFFFFFF"
        font.family: tip.fontFamily; font.styleName: tip.fontStyleName
        horizontalAlignment: Text.AlignHCenter
    }
}
