import QtQuick
import QtQuick.Shapes

// Small vector symbols, sharing one coordinate system at every display scale.
Item {
    id: icon
    property string kind: "search"
    property color color: "white"
    property bool filled: false
    implicitWidth: 24
    implicitHeight: 24
    Item {
        width: 24; height: 24
        scale: Math.min(icon.width, icon.height) / 24
        transformOrigin: Item.TopLeft
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: icon.color
                strokeWidth: icon.kind === "material" ? 1.4 : 1.7
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"
                PathSvg {
                    path: icon.kind === "share" ? "M12 15V2 M8 6L12 2L16 6 M8 9H6Q4 9 4 11V20Q4 22 6 22H18Q20 22 20 20V11Q20 9 18 9H16"
                        : icon.kind === "tabs" ? "M8 7V4Q8 2 10 2H20Q22 2 22 4V14Q22 16 20 16H17 M4 7H14Q17 7 17 10V20Q17 22 14 22H4Q2 22 2 20V10Q2 7 4 7"
                        : icon.kind === "material" ? "M7 16H4Q2 16 2 14V5Q2 3 4 3H15Q17 3 17 5V7 M9 7H19Q22 7 22 10V18Q22 21 19 21H9Q6 21 6 18V10Q6 7 9 7"
                        : "M17 17L22 22 M19 10.5A8.5 8.5 0 1 1 2 10.5A8.5 8.5 0 1 1 19 10.5"
                }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: icon.filled ? icon.color : "transparent"
                PathSvg { path: "M9 7H19Q22 7 22 10V18Q22 21 19 21H9Q6 21 6 18V10Q6 7 9 7" }
            }
        }
    }
}
