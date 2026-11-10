// Artwork fades in alpha into the shared glass rather than into a painted divider.
import QtQuick
import QtQuick.Effects
import "Common" as Common

Item {
    id: cover
    property url source: ""
    property real radius: 28
    readonly property bool ready: image.status === Image.Ready
    Item {
        id: content
        width: cover.width; height: cover.height
        visible: false
        Image {
            id: image
            width: parent.width * 0.72; height: parent.height
            source: cover.source
            sourceSize: Qt.size(600, 600)
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
            asynchronous: true
            smooth: true
        }
    }
    Common.ContinuousRectangle {
        id: mask
        width: cover.width; height: cover.height
        radius: cover.radius
        layer.enabled: true
        visible: false
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "white" }
            GradientStop { position: 0.25; color: "white" }
            GradientStop { position: 0.38; color: "#e6ffffff" }
            GradientStop { position: 0.50; color: "#80ffffff" }
            GradientStop { position: 0.62; color: "#20ffffff" }
            GradientStop { position: 0.72; color: "transparent" }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    MultiEffect {
        anchors.fill: parent
        source: content
        visible: cover.ready
        maskEnabled: true; maskSource: mask
        maskThresholdMin: 0.5; maskSpreadAtMin: 1
    }
}
