import QtQuick

Canvas {
    id: ring
    property real value: 0
    property real line: 5
    property color ink: "#30D77B"
    property color track: "#24352B"
    onValueChanged: requestPaint()
    onInkChanged: requestPaint()
    onTrackChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"), r = Math.max(0, Math.min(width, height) / 2 - line / 2 - 1);
        c.reset(); c.lineWidth = line; c.lineCap = "round";
        c.strokeStyle = track; c.beginPath(); c.arc(width/2, height/2, r, 0, Math.PI*2); c.stroke();
        if (value > 0) { c.strokeStyle = ink; c.beginPath(); c.arc(width/2, height/2, r, -Math.PI/2, -Math.PI/2 + Math.PI*2*Math.min(1,value)); c.stroke(); }
    }
}
