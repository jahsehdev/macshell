pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Common" as GlassCommon

// Copied from UpstreamBar/MacBar.qml's LGlass component. Keep its material
// optical pipeline intact; the portal shader only adapts its contour for a tail.
Item {
    id: g
    property Item backdrop: null
    property url shaderUrl: ""
    property bool liquid: false
    property bool dark: true
    property real bx: 0                 // position of this slab inside the backdrop item
    property real by: 0
    property real tailHeight:0
    property real pointerX:width/2
    property real tailAmount:1
    property real cornerR: 20
    property real tint: 0.4             // 0..1, from the translucency setting
    property real thickness: 30
    property real strength: 1.0         // liquid glass strength multiplier
    property real rim: 0.45
    property real rimTint: 0            // 1 = rim + border line take a brighter shade of the glass's own local colour
    property real ringW: 0              // width (px) of the thin border line along the edge, 0 = none
    property real grain: 0.03
    property real blur: 5               // Clear backdrop blur; Tinted uses the shared maximum preset
    property bool debug: false
    signal shaderError()

    Rectangle {
        visible: !g.liquid && g.tailHeight<=0
        anchors.fill: parent
        radius: g.cornerR
        color: g.dark ? Qt.rgba(0.12, 0.12, 0.13, 0.30 + g.tint * 0.9) : Qt.rgba(1, 1, 1, 0.30 + g.tint * 0.7)
        border.width: 1
        border.color: g.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.55)
    }
    Loader {
        anchors.fill: parent
        active: g.liquid && g.backdrop !== null && g.visible
        sourceComponent: Item {
            id: lg
            readonly property real m: 72     // extra backdrop captured around the slab (refraction + blur reach)
            readonly property real p: 10     // shader padding (drop shadow)
            // a Gaussian blur of 8 px or more doesn't need full resolution: blurring at half size is visually identical
            // and costs a quarter of the GPU work, every frame
            readonly property real materialBlur: GlassCommon.GlassMaterial.blurRadius(g.blur)
            readonly property real ds: materialBlur >= 8 ? 0.5 : 1.0
            readonly property real bn: materialBlur * 1.4 * ds / 64.0
            ShaderEffectSource {
                id: bsrc
                sourceItem: g.backdrop
                hideSource: true
                live: true
                visible: false
                sourceRect: Qt.rect(g.bx - lg.p - lg.m, g.by - lg.p - lg.m,
                                    g.width + 2 * (lg.p + lg.m), g.height + 2 * (lg.p + lg.m))
                textureSize: Qt.size(Math.max(1, Math.round(sourceRect.width * lg.ds)), Math.max(1, Math.round(sourceRect.height * lg.ds)))
            }
            MultiEffect {
                id: bblurFx
                source: bsrc
                width: bsrc.sourceRect.width * lg.ds; height: bsrc.sourceRect.height * lg.ds
                blurEnabled: true
                blurMax: 64
                blur: Math.min(1.0, lg.bn)
                autoPaddingEnabled: false
                visible: false
            }
            // real Gaussian pre-blur of the backdrop (Qt MultiEffect): the glass shader refracts THIS texture,
            // so there are no sampled copies of the background any more
            ShaderEffectSource {
                id: bblur
                sourceItem: bblurFx
                live: true
                visible: false
            }
            MultiEffect {
                id: bblur2Fx
                source: bblur
                width: bsrc.sourceRect.width * lg.ds; height: bsrc.sourceRect.height * lg.ds
                blurEnabled: lg.bn > 1.0
                blurMax: 64
                blur: Math.max(0.0, Math.min(1.0, lg.bn - 1.0))
                autoPaddingEnabled: false
                visible: false
            }
            // second Gaussian pass: only active when the slider goes past a single pass's 64 px limit
            ShaderEffectSource {
                id: bblur2
                // the 2nd pass is a pure copy unless the blur radius exceeds one pass: skip it then (same pixels, one GPU pass less)
                sourceItem: lg.bn > 1.0 ? bblur2Fx : null
                live: true
                visible: false
            }
            ShaderEffect {
                id: fx
                x: -lg.p; y: -lg.p
                width: g.width + 2 * lg.p
                height: g.height + 2 * lg.p
                fragmentShader: g.shaderUrl
                onStatusChanged: {
                    console.log("[macbar-glass] shader status:", status, "(0 = compiled, 1 = uncompiled, 2 = error)", log);
                    if (status === ShaderEffect.Error) g.shaderError();
                }
                property variant src: lg.bn > 1.0 ? bblur2 : bblur
                property real padPx: lg.p
                property vector2d itemSize: Qt.vector2d(width, height)
                property vector2d glassSize: Qt.vector2d(g.width, g.height)
                property vector2d srcSize: Qt.vector2d(bsrc.sourceRect.width, bsrc.sourceRect.height)
                property vector2d srcOffset: Qt.vector2d(lg.m, lg.m)
                property real pad: lg.p
                property real radius: g.cornerR
                property real bezel: Math.min(g.height * 0.36, 26)
                property real thickness: g.thickness * g.strength * 1.6      // bar popovers: boosted to match the stronger dock glass
                property real dispersion: 0.06 * g.strength * 1.3
                property real magnify: 0.05 * g.strength * 1.6
                property real rim: g.rim
                property real grain: g.grain * 0.2
                property real blurPx: 1.5
                property real tintMix: g.tint * 0.55
                property real saturation: 1.25
                property real dark: g.dark ? 1 : 0
                property real debug: g.debug ? 1 : 0
                property real shadowAmt: 1
                property real tailHeight:g.tailHeight
                property real pointerX:g.pointerX
                property real tailAmount:g.tailAmount
                property real flatInner: 0
                property real rimTint: g.rimTint
                property real ringW: g.ringW
            }
        }
    }
}
