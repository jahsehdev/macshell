import QtQuick

// Pane typography follows the selected Settings family and style.
Text {
    required property var t
    color: t.text2
    font.family: t.fam
    font.styleName: t.fontStyleName || ""
    font.pixelSize: 13
    wrapMode: Text.WordWrap
    lineHeight: 1.25
}
