import "../Common" as Corners
import QtQuick
import QtQuick.Shapes

// ─────────────────────────────────────────────────────────────────────────────
//  Squircle — Apple's continuous (superellipse) corner.
//
//  Rectangle { radius: n } draws circular arcs and looks stiff. Every rounded
//  surface in this dock (dock capsule, icon masks, rims, labels, menu) is drawn
//  from sampled superellipse points instead:
//
//      x = cx + r·sign(cos t)·|cos t|^(2/n)      y = cy − r·sign(sin t)·|sin t|^(2/n)
//
//  with n = 2..4 from the shared Continuous Corner setting, sampled over
//  each 0→π/2 quarter, joined by straight edges, clockwise.
//
//  `ring: true` turns the path into the band between the outer contour and an
//  inset one — that is how the gradient liquid-glass rim is drawn. It is built
//  as ONE continuous polyline: outer contour clockwise, then the inner contour
//  counter-clockwise. The two junction segments land exactly on the band's own
//  left and right ends, so they are invisible, and the opposite winding gives
//  the hole under ShapePath.WindingFill. (ShapePath.OddEvenFill is unreliable
//  here: CurveRenderer ignores it and GeometryRenderer drops the path entirely.)
//
//  Strokes are centred on the path, so a stroked contour would be half-clipped
//  by the item bounds. Whenever strokeWidth > 0 the contour is inset by half the
//  stroke width automatically, which also makes a stroke read as a clean inner
//  edge when strokeWidth == 1.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── shape ────────────────────────────────────────────────────────────────
    property real radius: 0
    property real exponent: Corners.CornerTheme.exponent
    property int segmentsPerCorner: 48

    // ── paint ────────────────────────────────────────────────────────────────
    property color fillColor: "transparent"
    property Gradient fillGradient: null
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    // filled band between the outer contour and an inset one
    property bool ring: false
    property real ringInset: 0

    // CurveRenderer gives the cleanest edges on large, smooth curves.
    // Set false on weak GPUs — GeometryRenderer is the cheaper tessellator.
    property bool curveRenderer: true

    property var _points: []

    implicitWidth: 0
    implicitHeight: 0

    // Sample one closed contour, clockwise, starting on the top edge at the
    // right-hand end of the top-left corner.
    function _contour(w, h, r, seg, ox, oy) {
        const e = 2.0 / Math.max(0.2, exponent);
        r = Math.max(0, Math.min(r, Math.min(w, h) / 2.0));
        const q = Math.PI / 2;
        // cx, cy, tStart, tEnd   (t decreasing == clockwise)
        const corners = [
            [w - r, r, q, 0],
            [w - r, h - r, 0, -q],
            [r, h - r, -q, -Math.PI],
            [r, r, Math.PI, q]
        ];
        const out = new Array(4 * (seg + 1));
        let k = 0;
        for (let c = 0; c < 4; ++c) {
            const cx = corners[c][0] + ox;
            const cy = corners[c][1] + oy;
            const t0 = corners[c][2];
            const t1 = corners[c][3];
            for (let i = 0; i <= seg; ++i) {
                const t = t0 + (t1 - t0) * i / seg;
                const ct = Math.cos(t);
                const st = Math.sin(t);
                out[k] = Qt.point(
                    cx + r * Math.sign(ct) * Math.pow(Math.abs(ct), e),
                    cy - r * Math.sign(st) * Math.pow(Math.abs(st), e));
                ++k;
            }
        }
        return out;
    }

    property bool _ready: false

    function rebuild() {
        if (!_ready)
            return;
        // Qt clears the JS globals before it finishes tearing the item tree down,
        // so a rebuild triggered by a width/height change during destruction
        // throws. Nothing to draw at that point — swallow it silently.
        try {
            const seg = Math.max(2, Math.min(160, segmentsPerCorner | 0));
            let w = Math.max(0.01, width);
            let h = Math.max(0.01, height);
            let r = Corners.CornerTheme.panelRadius(width,height,radius,(exponent-2)/2);
            let ox = 0;
            let oy = 0;

            // keep a centred stroke fully inside the item bounds
            if (strokeWidth > 0) {
                const d = strokeWidth / 2;
                w = Math.max(0.01, w - 2 * d);
                h = Math.max(0.01, h - 2 * d);
                r = Math.max(0, r - d);
                ox = d;
                oy = d;
            }

            const outerPt = _contour(w, h, r, seg, ox, oy);
            const pts = [];
            // The contour array runs clockwise from the top edge's right end to
            // the top edge's left end, i.e. it *starts* right after the segment
            // that has to close the loop. Re-anchoring it at its own last point
            // and appending the whole array makes the loop start and end on the
            // same vertex, so the top edge is traversed instead of being the
            // implicit closing segment (which a PathPolyline does not draw).
            pts.push(outerPt[outerPt.length - 1]);
            for (let i = 0; i < outerPt.length; ++i)
                pts.push(outerPt[i]);

            if (ring && ringInset > 0) {
                const i2 = Math.min(ringInset, Math.max(0, Math.min(w, h) / 2 - 0.5));
                const inner = _contour(w - 2 * i2, h - 2 * i2, Math.max(0, r - i2), seg,
                                       ox + i2, oy + i2);
                // same contour counter-clockwise ⇒ the winding rule punches the
                // hole; it starts and ends on (r, inset), which is directly
                // below the outer loop's junction point, so the implicit close
                // of the whole path adds no visible edge.
                for (let k = inner.length - 1; k >= 0; --k)
                    pts.push(inner[k]);
                pts.push(inner[inner.length - 1]);
            }

            _points = pts;
            // NB: `polyline`, not `shapePath.polyline` — ids declared inside a
            // C++ list property (Shape's `data`) are not registered in the id
            // table, so the indirect lookup comes back undefined.
            polyline.path = pts;
        } catch (e) {
            // teardown, see above
        }
    }

    onWidthChanged: rebuild()
    onHeightChanged: rebuild()
    onRadiusChanged: rebuild()
    onExponentChanged: rebuild()
    onSegmentsPerCornerChanged: rebuild()
    onRingChanged: rebuild()
    onRingInsetChanged: rebuild()
    onStrokeWidthChanged: rebuild()
    Component.onCompleted: {
        _ready = true;
        rebuild();
    }

    Shape {
        id: shape

        anchors.fill: parent
        antialiasing: true
        preferredRendererType: root.curveRenderer ? Shape.CurveRenderer : Shape.GeometryRenderer

        ShapePath {
            id: shapePath

            fillColor: root.fillColor
            fillGradient: root.fillGradient
            fillRule: ShapePath.WindingFill
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                id: polyline
                path: []
            }
        }
    }
}
