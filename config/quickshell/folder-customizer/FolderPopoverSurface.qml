pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
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
    property bool shadow: true
    property color fill: dark ? "#ed2d2e33" : "#edf3f3f5"
    property color stroke: dark ? "#70ffffff" : "#50000000"
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
    Shape {
        x: 0; y: surface.height
        width: surface.height; height: surface.width
        rotation: -90
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        ShapePath {
            fillColor: surface.fill
            strokeColor: surface.stroke
            strokeWidth: 1
            PathSvg { path: surface.outline }
        }
    }
}
