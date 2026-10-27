import QtQuick

ShaderEffect {
    property variant source
    property real appearance: IconStyle.effectMode
    property real dark: IconStyle.dark ? 1 : 0
    property color colorTint: IconStyle.tintColor
    fragmentShader: Qt.resolvedUrl("icon-style-v1.frag.qsb")
}
