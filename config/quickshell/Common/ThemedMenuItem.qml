pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.MenuItem {
    id: item
    implicitHeight: 29
    palette.windowText: !enabled ? (menu && menu.dark ? "#85858C" : "#929298")
        : highlighted ? "white" : (menu ? menu.foreground : "#242428")
    background: MenuHighlight {
        panelRadius: CornerTheme.menuRadius
        color: item.highlighted && item.enabled ? item.palette.highlight : "transparent"
    }
}
