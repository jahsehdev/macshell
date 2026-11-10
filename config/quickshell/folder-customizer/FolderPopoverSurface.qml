pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "Common" as Common
import "CornerMath.js" as Curve

// The Dock tooltip's continuous outline, rotated to point right. The panel
// and pointer share one fill, border and shadow, with no overlapping alpha.
Item {
    id: surface
    property real bodyWidth: 360
    property real radius: 23
    property real tailLength: 10
    property real tailHalfWidth: 15
    property real pointerY: 124
    property bool tailOnLeft: false
    property bool dark: false
    property url wallpaperSource: ""
    property size screenSize: Qt.size(1920, 1080)
    property point samplePosition: Qt.point(0, 0)
    property bool shadow: true
    property color fill: dark ? "#1F1F21" : "#F7F7FA"
    property color stroke: dark ? "#30ffffff" : "#25000000"
    readonly property real tailY: Math.max(radius + tailHalfWidth,
        Math.min(height - radius - tailHalfWidth, pointerY))
    readonly property string outline: Curve.tailPath(height, bodyWidth, radius,
        tailLength, height - tailY, tailHalfWidth, 0, 0.5)
    width: bodyWidth + tailLength
    transform: Scale { origin.x: surface.width / 2; xScale: surface.tailOnLeft ? -1 : 1 }
    layer.enabled: shadow && GraphicsInfo.api !== GraphicsInfo.Software
    layer.effect: MultiEffect {
        shadowEnabled: true; shadowBlur: 0.6
        shadowColor: "#50000000"; shadowVerticalOffset: 8
    }
    // Blur only the wallpaper, then clip it to the existing continuous body
    // and pointer. Never capture the symbols, preview or emoji grid.
    Common.FrostedMenuSurface {
        id: frost
        anchors.fill: parent
        dark: surface.dark
        radius: 0
        outline: false
        wallpaperSource: surface.wallpaperSource
        screenSize: surface.screenSize
        samplePosition: surface.samplePosition
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Shape {
            x: 0; y: surface.height
            width: surface.height; height: surface.width
            rotation: -90
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "white"; strokeWidth: 0
                PathSvg { path: surface.outline }
            }
        }
    }
    Shape {
        x: 0; y: surface.height
        width: surface.height; height: surface.width
        rotation: -90
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        ShapePath {
            fillColor: frost.ready && GraphicsInfo.api !== GraphicsInfo.Software ? "transparent" : surface.fill
            strokeColor: surface.stroke
            strokeWidth: 1
            PathSvg { path: surface.outline }
        }
    }
}
