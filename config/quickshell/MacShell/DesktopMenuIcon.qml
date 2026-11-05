import QtQuick
import QtQuick.Shapes

// Consistent outline symbols for the desktop's file, background and widget menus.
Item {
    id: icon
    property string action: ""
    property color color: "#77777c"
    readonly property var paths: ({
        open: "M14 3h7v7M21 3 11 13M10 5H5Q3 5 3 7v12q0 2 2 2h12q2 0 2-2v-5",
        folder: "M3 6q0-2 2-2h5l3 3h7q2 0 2 2v10q0 2-2 2H4q-2 0-2-2V6Z",
        rename: "M4 16 16 4q2-2 4 0t0 4L8 20l-5 1ZM14 6l4 4M4 16l4 4",
        trash: "M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7",
        customize: "M3 3h9l9 9q1 1 0 2l-7 7q-1 1-2 0l-9-9ZM9 7a2 2 0 1 1-4 0 2 2 0 1 1 4 0",
        mkdir: "M3 6q0-2 2-2h5l3 3h7q2 0 2 2v10q0 2-2 2H4q-2 0-2-2V6ZM12 10v8m-4-4h8",
        widgets: "M3 3h7v7H3ZM14 3h7v7h-7ZM3 14h7v7H3ZM14 14h7v7h-7Z",
        cleanup: "M3 4h3v3H3ZM10 5h11M3 11h3v3H3ZM10 12h11M3 18h3v3H3ZM10 19h11",
        wallpaper: "M3 3h18v18H3ZM3 17l6-7 5 6 3-3 4 4M17 7h.01",
        small: "M7 7h10v10H7Z",
        medium: "M3 7h18v10H3Z",
        large: "M3 3h18v18H3Z",
        xl: "M2 2h20v20H2ZM6 6h12v12H6Z",
        removeWidget: "M22 12a10 10 0 1 1-20 0 10 10 0 1 1 20 0M7 12h10"
    })
    implicitWidth: 14; implicitHeight: 14
    Item {
        width: 24; height: 24
        scale: Math.min(icon.width, icon.height) / 24
        transformOrigin: Item.TopLeft
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            ShapePath {
                strokeColor: icon.color; strokeWidth: 1.7
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: icon.paths[icon.action] || "" }
            }
        }
    }
}
