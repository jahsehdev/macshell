import QtQuick
import QtQuick.Shapes

Item {
    id: icon
    property string name: "camera"
    property color ink: "white"
    property bool solid: false
    readonly property bool filled: solid && (name === "camera" || name === "video")
    implicitWidth: 24; implicitHeight: 24
    Shape {
        width: 24; height: 24
        scale: Math.min(icon.width, icon.height) / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: icon.filled ? "transparent" : icon.ink; strokeWidth: icon.filled ? 0 : 1.65
            fillColor: icon.filled ? icon.ink : "transparent"
            fillRule: ShapePath.OddEvenFill
            capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: {
                    switch (icon.name) {
                    case "camera": return icon.filled
                        ? "M4 6H8L10 3H15L17 6H20Q23 6 23 9V19Q23 22 20 22H4Q1 22 1 19V9Q1 6 4 6Z M16.5 14A4.5 4.5 0 1 1 7.5 14A4.5 4.5 0 1 1 16.5 14Z M20 9.5A1 1 0 1 1 18 9.5A1 1 0 1 1 20 9.5Z"
                        : "M5 7H8L10 4H15L17 7H20Q22 7 22 9V19Q22 21 20 21H4Q2 21 2 19V9Q2 7 5 7 M16.3 13.5A4.3 4.3 0 1 1 7.7 13.5A4.3 4.3 0 1 1 16.3 13.5 M18 10H19";
                    case "burst": return "M3 3H9V9H3Z M15 3H21V9H15Z M3 15H9V21H3Z M15 15H21V21H15Z";
                    case "video": return icon.filled
                        ? "M4 5H14Q16 5 16 7V17Q16 19 14 19H4Q2 19 2 17V7Q2 5 4 5Z M18 9L23 6V18L18 15Z"
                        : "M4 5H14Q16 5 16 7V17Q16 19 14 19H4Q2 19 2 17V7Q2 5 4 5 M16 9L22 6V18L16 15";
                    case "back": return "M14 5L7 12L14 19";
                    case "play": return "M8 4L20 12L8 20Z";
                    case "folder": return "M3 6H9L11 8H21V20H3Z";
                    case "export": return "M12 15V2M7 7L12 2L17 7 M5 12H3V22H21V12H19";
                    case "trash": return "M4 6H20M9 6V3H15V6M6 6L7 22H17L18 6M10 10V18M14 10V18";
                    case "copy": return "M8 7H21V22H8Z M16 7V2H3V17H8";
                    case "settings": return "M4 5H20M4 12H20M4 19H20M8 2V8M16 9V15M10 16V22";
                    case "chevron": return "M6 9L12 15L18 9";
                    case "check": return "M5 12L10 17L20 6";
                    default: return "";
                    }
                }
            }
        }
    }
}
