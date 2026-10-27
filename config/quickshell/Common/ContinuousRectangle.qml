pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes as Shapes
import "CornerMath.js" as Curve

// Fixed continuous corners for surfaces. Circular controls and tiny radii use
// native rectangles and never instantiate a Shape renderer.
Item {
    id: surface
    property color color: "white"
    property real radius: 0
    property Gradient gradient: null
    readonly property ContinuousBorder border: ContinuousBorder {}
    property real cornerSmoothing: CornerTheme.smoothing
    property bool normalizeRadius: true
    readonly property real effectiveRadius: normalizeRadius
        ? CornerTheme.panelRadius(width,height,radius,cornerSmoothing)
        : Math.max(0, Math.min(radius,width/2,height/2))
    readonly property real stroke: border.color.a > 0 ? Math.max(0,border.width) : 0
    readonly property bool continuous: cornerSmoothing > 0 && radius >= 3 && width > 0 && height > 0
    readonly property int segments: Math.max(16,Math.min(48,Math.ceil(Math.sqrt(Math.min(effectiveRadius,width/2,height/2)*6))))
    // Geometry depends only on size/radius/stroke, never on Dock settings or fill colour.
    readonly property string outline: continuous ? Curve.path(width,height,effectiveRadius,cornerSmoothing,stroke/2,segments) : ""
    onGradientChanged: if (curve.item) curve.item.updateGradient()

    Rectangle {
        anchors.fill: parent
        visible: !surface.continuous
        radius: surface.effectiveRadius
        color: surface.color
        gradient: surface.gradient
        border.width: surface.stroke
        border.color: surface.border.color
        antialiasing: true
    }
    Loader {
        id: curve
        anchors.fill: parent
        active: surface.continuous
        sourceComponent: Shapes.Shape {
            preferredRendererType: Shapes.Shape.CurveRenderer
            antialiasing: true
            function updateGradient() { fill.stops=surface.gradient ? surface.gradient.stops : []; }
            Component.onCompleted: updateGradient()
            Shapes.ShapePath {
                strokeColor: surface.border.color
                strokeWidth: surface.stroke
                fillColor: surface.gradient ? "transparent" : surface.color
                fillGradient: surface.gradient ? fill : null
                joinStyle: Shapes.ShapePath.RoundJoin
                PathSvg { path: surface.outline }
            }
            Shapes.LinearGradient {
                id: fill
                x1: 0; y1: 0
                x2: surface.gradient && surface.gradient.orientation === Gradient.Horizontal ? surface.width : 0
                y2: surface.gradient && surface.gradient.orientation === Gradient.Horizontal ? 0 : surface.height
            }
        }
    }
}
