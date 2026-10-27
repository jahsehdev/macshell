import QtQuick
import QtQuick.Effects

// The bundled Dock shader renders even when the live Dock uses Normal Blur.
// Clear samples the sharp scene directly; Tinted only blurs the backdrop.
FocusScope {
    id: tile
    required property var t
    property bool tinted: false
    property bool selected: false
    property url shaderUrl: Qt.resolvedUrl("liquidglass-preview-v1.frag.qsb")
    readonly property string label: tinted ? "Tinted" : "Clear"
    signal clicked()
    width: 120
    height: 106
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: label
    Accessible.description: tinted ? "Maximum backdrop blur, without darkening the glass" : "Clear, refractive Liquid Glass"
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.onPressAction: clicked()
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Item {
        id: preview
        width: tile.width
        height: 78
        clip: true
        Image {
            id: scene
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/settings/appearance-preview.svg")
            sourceSize: Qt.size(240, 156)
            fillMode: Image.PreserveAspectCrop
            smooth: true
        }
        ShaderEffectSource {
            id: backdrop
            sourceItem: scene
            live: true
            visible: false
        }
        MultiEffect {
            id: blurredScene
            source: backdrop
            width: preview.width; height: preview.height
            blurEnabled: tile.tinted
            blurMax: 32
            // Scaled miniature of the 80 px preset, not a dark colour overlay.
            blur: tile.tinted ? 0.7 : 0
            autoPaddingEnabled: false
            visible: false
        }
        ShaderEffectSource {
            id: blurredBackdrop
            sourceItem: blurredScene
            live: true
            visible: false
        }
        Rectangle {
            x: 14; y: 23; width: 92; height: 34; radius: 17
            visible: tile.shaderUrl.toString() === "" || glass.status === ShaderEffect.Error
            color: tile.t.dark ? Qt.rgba(0.08, 0.08, 0.10, 0.3) : Qt.rgba(1, 1, 1, 0.35)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.5)
        }
        ShaderEffect {
            id: glass
            x: 14; y: 23; width: 92; height: 34
            visible: tile.shaderUrl.toString() !== ""
            fragmentShader: tile.shaderUrl
            property variant src: tile.tinted ? blurredBackdrop : backdrop
            property vector2d itemSize: Qt.vector2d(width, height)
            property vector2d glassSize: itemSize
            property vector2d srcSize: Qt.vector2d(preview.width, preview.height)
            property vector2d srcOffset: Qt.vector2d(x, y)
            property real pad: 0
            property real radius: 17
            property real bezel: 7
            property real thickness: 8.5
            property real dispersion: 0.03
            property real blurPx: tile.tinted ? 1.5 : 0
            property real tintMix: 0
            property real saturation: 1.25
            property real dark: tile.t.dark ? 1 : 0
            property real debug: 0
            property real rim: 0.55
            property real grain: 0
            property real magnify: 0.05
            property real shadowAmt: 0
            property real rimTint: 0
            property real ringW: 0
            property real flatInner: 0
            property real squircle: 0
        }
    }
    Rectangle {
        width: tile.width; height: preview.height; radius: 10
        color: "transparent"
        border.width: tile.selected || tile.activeFocus ? 3 : 1
        border.color: tile.selected || tile.activeFocus ? "#0a84ff" : tile.t.cardBorder
    }
    Text {
        y: 85
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.label
        color: tile.selected ? tile.t.text : tile.t.text2
        font.family: tile.t.fam
        font.pixelSize: 12
        font.weight: tile.selected ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { tile.forceActiveFocus(); tile.clicked(); }
    }
}
