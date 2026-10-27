import "Common" as Corners
import QtQuick
import QtQuick.Effects

Item {
    id: art
    required property var wd
    property real r: 7
    Corners.ContinuousRectangle {
        id: artMask
        anchors.fill: parent
        radius: art.r
        visible: false
        layer.enabled: true
    }
    Corners.ContinuousRectangle {   // placeholder
        anchors.fill: parent
        radius: art.r
        visible: artImg.status !== Image.Ready
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(art.wd.ac, 1.25) }
            GradientStop { position: 1.0; color: Qt.darker(art.wd.ac, 1.25) }
        }
        Text {
            anchors.centerIn: parent
            text: "\u266B"
            color: art.wd.tinted ? art.wd.styleTint : Qt.rgba(1, 1, 1, 0.85)
            font.pixelSize: parent.height * 0.5
        }
    }
    Image {
        id: artImg
        anchors.fill: parent
        source: art.wd.artSrc
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 400
        sourceSize.height: 400
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        visible: artImg.status === Image.Ready
        source: artImg
        saturation: art.wd.tinted ? -1 : 0
        colorization: art.wd.tinted ? 1 : 0
        colorizationColor: art.wd.styleTint
        maskEnabled: true
        maskSource: artMask
    }
    Corners.ContinuousRectangle {   // hairline around the art
        anchors.fill: parent
        radius: art.r
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)
    }
}
