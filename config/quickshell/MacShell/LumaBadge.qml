pragma ComponentBehavior: Bound
import QtQuick

// Draw the generated artwork through a true circle on both GPU and software
// renderers. This needs no shader, capture surface or continuous animation.
Canvas {
    id: badge
    implicitWidth: 20
    implicitHeight: 20
    property url artwork: Qt.resolvedUrl("assets/luma-ai-circle.png")
    antialiasing: true
    Component.onCompleted: loadImage(artwork)
    onArtworkChanged: { loadImage(artwork); requestPaint(); }
    onImageLoaded: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (!isImageLoaded(artwork)) return;
        const diameter = Math.min(width, height);
        ctx.save();
        ctx.beginPath();
        ctx.arc(width / 2, height / 2, diameter / 2, 0, Math.PI * 2);
        ctx.closePath();
        ctx.clip();
        // Remove the generated canvas's small transparent outer margin.
        const size = diameter * 1.10;
        ctx.drawImage(artwork, (width - size) / 2, (height - size) / 2, size, size);
        ctx.restore();
    }
}
