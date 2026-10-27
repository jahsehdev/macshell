import QtQuick
import QtQuick.Shapes

Shape {
    id: panel
    property real cornerRadius: 32
    property color color: "white"
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    // Two cubic curves per corner. Collinear controls meet each straight edge
    // with zero curvature; equal first and second derivatives at the midpoint
    // keep the corner C2 continuous, rather than a circular radius joined to a line.
    function outline() {
        const w = width;
        const h = height;
        const r = Math.min(cornerRadius, w / 2, h / 2);
        return `M ${r} 0 L ${w-r} 0
            C ${w-0.8*r} 0 ${w-0.4*r} 0 ${w-0.2*r} ${0.2*r}
            C ${w} ${0.4*r} ${w} ${0.8*r} ${w} ${r}
            L ${w} ${h-r}
            C ${w} ${h-0.8*r} ${w} ${h-0.4*r} ${w-0.2*r} ${h-0.2*r}
            C ${w-0.4*r} ${h} ${w-0.8*r} ${h} ${w-r} ${h}
            L ${r} ${h}
            C ${0.8*r} ${h} ${0.4*r} ${h} ${0.2*r} ${h-0.2*r}
            C 0 ${h-0.4*r} 0 ${h-0.8*r} 0 ${h-r}
            L 0 ${r}
            C 0 ${0.8*r} 0 ${0.4*r} ${0.2*r} ${0.2*r}
            C ${0.4*r} 0 ${0.8*r} 0 ${r} 0 Z`;
    }
    ShapePath {
        fillColor: panel.color
        strokeWidth: -1
        PathSvg { path: panel.outline() }
    }
}
