pragma ComponentBehavior: Bound
import QtQuick

// A weather scene, not a glass material. Static atmosphere is painted only on
// changes; precipitation gets its own small, bounded 30 fps canvas.
Item {
    id: scene
    objectName: "notchWeatherScene"
    property string kind: "sun"
    property bool day: true
    property bool ready: false
    property bool active: false
    property bool reducedMotion: false
    property real radius: 24
    readonly property bool storm: ready && kind === "storm"
    readonly property bool raining: ready && (kind === "rain" || storm)
    readonly property bool overcast: ready && ["cloud", "fog", "snow", "rain", "storm"].indexOf(kind) >= 0
    readonly property bool darkForecast: !day || overcast
    readonly property color skyTop: !ready ? "#38577B" : !day ? "#101D35" : storm ? "#202F43" : raining ? "#34495E" : overcast ? "#53677A" : "#2867A5"
    readonly property color skyBottom: !day ? "#283B56" : storm ? "#465565" : raining ? "#677987" : overcast ? "#8B9BA6" : "#96C3E2"
    readonly property bool animating: active && ready && !reducedMotion && raining
    property real elapsed: 0
    property real strikeAge: -1
    property real nextStrike: 3.5
    property int strikeSeed: 0
    onKindChanged: resetWeather()
    onAnimatingChanged: {
        if (!animating) { strikeAge = -1; elapsed = 0; nextStrike = 3.5; }
        precipitation.requestPaint();
    }
    function resetWeather() {
        strikeAge = -1; elapsed = 0; nextStrike = 3.5;
        atmosphere.requestPaint(); precipitation.requestPaint();
    }
    function noise(n) { const v = Math.sin(n * 127.1 + 311.7) * 43758.5453; return v - Math.floor(v); }

    Canvas {
        id: atmosphere
        objectName: "notchWeatherClouds"
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: scene
            function onSkyTopChanged() { atmosphere.requestPaint(); }
            function onSkyBottomChanged() { atmosphere.requestPaint(); }
            function onReadyChanged() { atmosphere.requestPaint(); }
            function onRadiusChanged() { atmosphere.requestPaint(); }
        }
        onPaint: {
            const c = getContext("2d"), w = width, h = height;
            c.reset(); if (w <= 0 || h <= 0) return;
            c.save(); c.beginPath(); c.roundedRect(0, 0, w, h, scene.radius, scene.radius); c.clip();
            const sky = c.createLinearGradient(0, 0, 0, h);
            sky.addColorStop(0, scene.skyTop); sky.addColorStop(0.48, scene.skyTop); sky.addColorStop(1, scene.skyBottom);
            c.fillStyle = sky; c.fillRect(0, 0, w, h);
            if (!scene.ready) { c.restore(); return; }
            // Volumetric cloud lobes: shaded undersides, softly lit crowns and
            // overlapping scales. No straight horizon or white rectangular band.
            function puff(x, y, rx, ry, light, opacity) {
                c.save(); c.translate(x, y); c.scale(rx, ry);
                const mist = c.createRadialGradient(-0.12, -0.24, 0.04, 0, 0, 1);
                const rgb = light ? (scene.darkForecast ? "148,165,180" : "255,255,255")
                                  : (scene.darkForecast ? "40,56,73" : "170,196,216");
                mist.addColorStop(0, "rgba(" + rgb + "," + opacity + ")");
                mist.addColorStop(0.48, "rgba(" + rgb + "," + opacity * 0.88 + ")");
                mist.addColorStop(0.78, "rgba(" + rgb + "," + opacity * 0.40 + ")");
                mist.addColorStop(1, "rgba(" + rgb + ",0)");
                c.fillStyle = mist; c.fillRect(-1, -1, 2, 2); c.restore();
            }
            if (scene.overcast) {
                for (let i = 0; i < 13; i++) {
                    const x = (i / 10 - 0.1) * w, y = (0.04 + scene.noise(i + 9) * 0.18) * h;
                    puff(x, y, w * 0.22, h * 0.40, false, scene.storm ? 0.72 : 0.45);
                    puff(x - 12, y - h * 0.19, w * 0.20, h * 0.25, true, 0.17);
                }
            }
            // The lower cloud banks cradle the forecast. Their irregular crowns
            // remain recognisable as clouds rather than a two-tone UI panel.
            for (let layer = 0; layer < 3; layer++) {
                for (let i = 0; i < 9; i++) {
                    const n = i + layer * 19;
                    const x = (i / 6 - 0.15) * w;
                    const y = h * (0.92 + layer * 0.12 - scene.noise(n + 5) * 0.12);
                    const rx = w * (0.17 + scene.noise(n + 8) * 0.10);
                    const ry = h * (0.25 + scene.noise(n + 1) * 0.16);
                    puff(x + 8, y + h * 0.05, rx * 1.1, ry, false, 0.68);
                    puff(x, y - h * 0.045, rx, ry * 0.85, true, scene.darkForecast ? 0.22 : 0.95);
                }
            }
            // A transparent ink veil keeps small text stable over cloud detail.
            if (scene.darkForecast) {
                const veil = c.createLinearGradient(0, h * 0.45, 0, h);
                veil.addColorStop(0, "#00121F30"); veil.addColorStop(1, "#B3121F30");
                c.fillStyle = veil; c.fillRect(0, 0, w, h);
            }
            c.restore();
        }
    }
    Timer {
        objectName: "notchWeatherRainTimer"
        interval: 33; repeat: true; running: scene.animating
        onTriggered: {
            scene.elapsed += interval / 1000;
            if (scene.storm && scene.elapsed >= scene.nextStrike) {
                scene.strikeAge = 0; scene.strikeSeed++;
                scene.nextStrike = scene.elapsed + 8 + scene.noise(scene.strikeSeed) * 5;
            } else if (scene.strikeAge >= 0) {
                scene.strikeAge += interval / 1000;
                if (scene.strikeAge > 1.2) scene.strikeAge = -1;
            }
            precipitation.requestPaint();
        }
    }
    Canvas {
        id: precipitation
        objectName: "notchWeatherPrecipitation"
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"), w = width, h = height;
            c.reset(); if (!scene.animating || w <= 0 || h <= 0) return;
            c.save(); c.beginPath(); c.roundedRect(0, 0, w, h, scene.radius, scene.radius); c.clip();
            // Depth layers vary fall speed and length. Deterministic offsets
            // avoid random jumps, and the scene never samples the text layer.
            const count = scene.storm ? 64 : 40;
            for (let i = 0; i < count; i++) {
                const depth = scene.noise(i + 13), speed = 90 + depth * 130;
                const y = (scene.noise(i + 24) * (h + 40) + scene.elapsed * speed) % (h + 40) - 20;
                const x = ((scene.noise(i + 71) * w - scene.elapsed * 13 * (1 + depth)) % w + w) % w;
                const length = 6 + depth * 11;
                c.strokeStyle = "rgba(199,222,242," + (0.12 + depth * 0.20) + ")";
                c.lineWidth = 0.65 + depth * 0.65; c.lineCap = "round";
                c.beginPath(); c.moveTo(x, y); c.lineTo(x - length * 0.20, y + length); c.stroke();
            }
            if (scene.storm && scene.strikeAge >= 0) {
                const reveal = Math.min(1, scene.strikeAge / 0.20);
                const alpha = Math.max(0, 1 - Math.max(0, scene.strikeAge - 0.20));
                const startX = w * (0.38 + scene.noise(scene.strikeSeed + 31) * 0.24);
                // Local cloud illumination only: no full-card flash or strobe.
                const glow = c.createRadialGradient(startX, h * 0.18, 0, startX, h * 0.18, h * 0.65);
                glow.addColorStop(0, "rgba(191,210,249," + alpha * 0.17 + ")");
                glow.addColorStop(1, "#00BFD2F9"); c.fillStyle = glow; c.fillRect(0, 0, w, h);
                function bolt(x, y, length, seed, branch) {
                    const steps = branch ? 5 : 11, visible = Math.floor(steps * reveal);
                    c.beginPath(); c.moveTo(x, y);
                    for (let j = 1; j <= visible; j++) {
                        const dx = (scene.noise(seed + j) - 0.5) * (branch ? 17 : 26);
                        x += dx + (branch ? 6 : -2); y += length / steps;
                        c.lineTo(x, y);
                    }
                    c.strokeStyle = "rgba(174,202,255," + alpha * 0.24 + ")"; c.lineWidth = branch ? 3 : 5; c.stroke();
                    c.strokeStyle = "rgba(224,237,255," + alpha * (branch ? 0.44 : 0.75) + ")"; c.lineWidth = branch ? 0.8 : 1.3; c.stroke();
                }
                bolt(startX, 2, h * 0.66, scene.strikeSeed * 17, false);
                if (reveal > 0.4) bolt(startX - 8, h * 0.22, h * 0.25, scene.strikeSeed * 23, true);
            }
            c.restore();
        }
    }
}
