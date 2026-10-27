import QtQuick

Item {
    id: dot
    property string value: "multicolor"
    width: 24; height: 24
    Canvas {
        anchors.fill: parent
        visible: dot.value === "multicolor"
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const r = width / 2;
            for (let i = 0; i < 120; i++) {
                ctx.beginPath();
                ctx.moveTo(r, r);
                ctx.arc(r, r, r - 0.5, i * Math.PI / 60, (i + 1.1) * Math.PI / 60);
                ctx.closePath();
                ctx.fillStyle = Qt.hsla(i / 120, 0.95, 0.52, 1).toString();
                ctx.fill();
            }
            const light = ctx.createRadialGradient(r, r, 0, r, r, r);
            light.addColorStop(0, "#aaffffff");
            light.addColorStop(1, "#00ffffff");
            ctx.fillStyle = light;
            ctx.beginPath(); ctx.arc(r, r, r - 0.5, 0, Math.PI * 2); ctx.fill();
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: dot.value !== "multicolor"
        radius: width / 2
        color: visible && dot.value !== "" ? dot.value : "transparent"
        border.width: 1
        border.color: "#24000000"
    }
}
