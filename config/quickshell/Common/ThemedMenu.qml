pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Menu {
    id: menu
    property bool dark: IconStyle.systemDark
    property Item backdrop: null
    property url wallpaperSource: ""
    property size screenSize: Qt.size(1920, 1080)
    property point screenOrigin: Qt.point(0, 0)
    property color borderTint: "#8A9AB5"
    readonly property color foreground: dark ? "#F2F2F5" : "#242428"
    readonly property color separatorColor: dark ? "#30FFFFFF" : "#25000000"
    padding: CornerTheme.menuInset
    margins: 8
    popupType: Basic.Popup.Window
    focus: true
    font.family: "SF Pro Text"
    font.pixelSize: 13
    palette.windowText: foreground
    palette.text: foreground
    palette.buttonText: foreground
    palette.mid: separatorColor
    palette.highlight: ThemeColors.accentFor("shell")
    palette.highlightedText: "white"
    palette.disabled.windowText: dark ? "#85858C" : "#929298"
    delegate: ThemedMenuItem {}
    background: FrostedMenuSurface {
        id: material
        objectName: "themedMenuMaterial"
        implicitWidth: 228
        implicitHeight: 40
        radius: CornerTheme.menuRadius
        dark: menu.dark
        backdrop: menu.backdrop
        wallpaperSource: menu.wallpaperSource
        screenSize: menu.screenSize
        borderTint: menu.borderTint
        samplePosition: {
            menu.x; menu.y;
            if (menu.backdrop) return material.mapToItem(menu.backdrop, 0, 0);
            const origin = material.mapToGlobal(0, 0);
            return Qt.point(origin.x - menu.screenOrigin.x, origin.y - menu.screenOrigin.y);
        }
    }
}
