pragma ComponentBehavior: Bound
import QtQuick
import "Common" as Common

// A moving spectrum follows the selected region's perimeter. No rotating rectangle.
Canvas {
    id: glow
    property bool moving: true
    property real phase: 0
    property real cornerRadius: 12
    property var colors: ["#48bcff", "#6575ff", "#b765ff", "#ff70bb", "#ff9565", "#ffe5a0", "#48bcff"]
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPhaseChanged: requestPaint()
    Timer {
        interval: 33
        repeat: true
        running: glow.visible && glow.moving && !Common.DesktopPreferences.reduceMotion
        onTriggered: glow.phase = (glow.phase + 0.009) % 1
    }
    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const inset = 10, w = width - inset * 2, h = height - inset * 2;
        if (w <= 0 || h <= 0) return;
        const r = Math.min(cornerRadius, w / 2, h / 2);
        const steps = 160;
        // Parametric rounded-rectangle perimeter, including curved corners.
        const lengths = [w-2*r, Math.PI*r/2, h-2*r, Math.PI*r/2, w-2*r, Math.PI*r/2, h-2*r, Math.PI*r/2];
        const total = lengths.reduce((a,b) => a+b,0);
        function point(t) {
            let d=t*total, k=0;
            while (k<7 && d>lengths[k]) { d-=lengths[k]; k++; }
            const u=lengths[k]>0 ? d/lengths[k] : 0;
            if (k===0) return [inset+r+d,inset];
            if (k===2) return [inset+w,inset+r+d];
            if (k===4) return [inset+w-r-d,inset+h];
            if (k===6) return [inset,inset+h-r-d];
            const a=(-Math.PI/2)+(k-1)/2*Math.PI/2+u*Math.PI/2;
            const cx=(k===1 || k===3) ? inset+w-r : inset+r;
            const cy=(k===1 || k===7) ? inset+r : inset+h-r;
            return [cx+r*Math.cos(a),cy+r*Math.sin(a)];
        }
        ctx.lineCap="round";
        for (let layer=0;layer<3;layer++) {
            ctx.lineWidth=[15,8,2.5][layer]; ctx.globalAlpha=[0.09,0.22,1][layer];
            for (let i=0;i<steps;i++) {
                const t=i/steps, p=point(t), q=point((i+1)/steps);
                const hue=((t+phase)%1)*(colors.length-1), n=Math.floor(hue), f=hue-n;
                const a=Qt.color(colors[n]), b=Qt.color(colors[n+1]);
                ctx.strokeStyle=Qt.rgba(a.r+(b.r-a.r)*f,a.g+(b.g-a.g)*f,a.b+(b.b-a.b)*f,1);
                ctx.beginPath();ctx.moveTo(p[0],p[1]);ctx.lineTo(q[0],q[1]);ctx.stroke();
            }
        }
        ctx.globalAlpha=1;
    }
}
