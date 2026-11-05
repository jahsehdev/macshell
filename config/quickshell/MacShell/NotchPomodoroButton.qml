pragma ComponentBehavior: Bound
import QtQuick
import "NotchGeometry.js" as Geometry

// Solid button fill with reflected edge arcs from liquid-glass-buttons.html.
NotchToolButton {
    id: button
    property real rimStrength: 0.65
    background: Item {
        id: surface
        readonly property real radius: button.round ? Math.min(width, height) / 2 : Geometry.radius(button.cornerRadius, width, height)
        opacity: button.fill.a > 0.001 ? 1 : button.hovered || button.down || button.visualFocus ? 0.5 : 0
        scale: button.down ? 0.985 : 1
        onRadiusChanged: material.requestPaint()
        Canvas {
            id: material
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: button
                function onFillChanged() { material.requestPaint(); }
                function onRimStrengthChanged() { material.requestPaint(); }
            }
            onPaint: {
                const c = getContext("2d"), w = width, h = height;
                c.reset();
                if (w <= 0 || h <= 0) return;
                function outline(inset) {
                    const x = inset, y = inset, iw = Math.max(0, w - inset * 2), ih = Math.max(0, h - inset * 2);
                    const r = Math.max(0, Math.min(surface.radius - inset, iw / 2, ih / 2));
                    c.beginPath();
                    if (r <= 0) { c.rect(x, y, iw, ih); return; }
                    c.moveTo(x + r, y); c.lineTo(x + iw - r, y);
                    c.arc(x + iw - r, y + r, r, -Math.PI / 2, 0);
                    c.lineTo(x + iw, y + ih - r); c.arc(x + iw - r, y + ih - r, r, 0, Math.PI / 2);
                    c.lineTo(x + r, y + ih); c.arc(x + r, y + ih - r, r, Math.PI / 2, Math.PI);
                    c.lineTo(x, y + r); c.arc(x + r, y + r, r, Math.PI, Math.PI * 1.5); c.closePath();
                }
                c.save(); outline(0); c.clip();
                c.fillStyle = button.fill; c.fillRect(0, 0, w, h);
                // A continuous 165-degree gradient ring creates the two brighter edge arcs.
                const dx = Math.sin(Math.PI * 165 / 180), dy = -Math.cos(Math.PI * 165 / 180);
                const length = Math.abs(w * dx) + Math.abs(h * dy);
                const rim = c.createLinearGradient(w / 2 - dx * length / 2, h / 2 - dy * length / 2,
                    w / 2 + dx * length / 2, h / 2 + dy * length / 2);
                const positions = [0, 0.16, 0.42, 0.65, 0.91, 1], alphas = [239, 128, 18, 48, 217, 128];
                for (let i = 0; i < positions.length; i++) rim.addColorStop(positions[i], Qt.rgba(1, 1, 1, alphas[i] / 255 * button.rimStrength));
                c.lineWidth = Math.min(0.85, h * 0.02); c.strokeStyle = rim;
                outline(c.lineWidth / 2); c.stroke(); c.restore();
            }
        }
        Rectangle {
            anchors.fill: parent; radius: surface.radius
            color: button.down ? "#12000000" : button.hovered ? "#14FFFFFF" : "transparent"
        }
        Rectangle {
            anchors.fill: parent; radius: surface.radius; color: "transparent"
            visible: button.visualFocus; border.width: 1.5; border.color: "#DDEBFF"
        }
        Behavior on scale { enabled: !button.reducedMotion; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: !button.reducedMotion; NumberAnimation { duration: 100 } }
    }
}
