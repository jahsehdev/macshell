pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.MenuSeparator {
    id: separator
    padding: 4
    contentItem: Rectangle {
        implicitWidth: 188
        implicitHeight: 1
        color: separator.palette.mid
    }
}
