import QtQuick

Canvas {
    id: icon
    property string kind: "grid"
    property color color: "white"
    implicitWidth: 22
    implicitHeight: 22
    antialiasing: true
    onKindChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset(); c.scale(width / 24, height / 24);
        c.strokeStyle = color; c.fillStyle = color; c.lineWidth = 1.6;
        c.lineCap = "round"; c.lineJoin = "round";
        function line(points) {
            c.beginPath(); c.moveTo(points[0], points[1]);
            for (var i = 2; i < points.length; i += 2) c.lineTo(points[i], points[i + 1]);
            c.stroke();
        }
        function circle(x, y, r, fill) { c.beginPath(); c.arc(x,y,r,0,2*Math.PI); if(fill)c.fill(); else c.stroke(); }
        function box(x,y,w,h,r) { c.beginPath(); c.roundedRect(x,y,w,h,r,r); c.stroke(); }
        switch (kind) {
        case "wifi":
            [5,9,13].forEach(function(r){c.beginPath();c.arc(12,19,r,-Math.PI*.75,-Math.PI*.25);c.stroke();}); circle(12,19,1.1,true); break;
        case "bluetooth": line([7,7,17,17,12,22,12,2,17,7,7,17]); break;
        case "airplane": line([12,2,12,22]);line([3,14,12,9,21,14]);line([8,21,12,18,16,21]); break;
        case "moon":
            circle(12,12,9,true); c.globalCompositeOperation="destination-out";circle(17,7,8,true);c.globalCompositeOperation="source-over"; break;
        case "sun":
            circle(12,12,4,false); for(var j=0;j<8;j++){var a=j*Math.PI/4;line([12+Math.cos(a)*7,12+Math.sin(a)*7,12+Math.cos(a)*10,12+Math.sin(a)*10]);} break;
        case "nightshift": c.beginPath();c.arc(12,14,5,Math.PI,2*Math.PI);c.stroke();line([3,14,21,14]);line([8,19,16,19]);line([12,3,12,6]);line([4,6,6,8]);line([20,6,18,8]);break;
        case "contrast": circle(12,12,9,false);c.beginPath();c.arc(12,12,9,-Math.PI/2,Math.PI/2);c.fill();break;
        case "coffee": box(4,9,12,11,3);c.beginPath();c.arc(17,13,3,-Math.PI/2,Math.PI/2);c.stroke();line([8,3,8,6]);line([12,3,12,6]);break;
        case "gamepad": box(2,6,20,13,5);line([5,12,11,12]);line([8,9,8,15]);circle(16,10,1,true);circle(19,14,1,true);break;
        case "record": circle(12,12,9,false);circle(12,12,5,true);break;
        case "note": line([10,18,10,5,20,3,20,16]);circle(7,18,3,true);circle(17,16,3,true);break;
        case "play": line([8,4,20,12,8,20,8,4]);break;
        case "speaker": line([3,9,7,9,12,4,12,20,7,15,3,15,3,9]);[5,9].forEach(function(r){c.beginPath();c.arc(12,12,r,-.7,.7);c.stroke();});break;
        case "camera": box(2,6,20,15,3);circle(12,13,4,false);line([8,3,16,3]);break;
        case "desktop": box(2,4,20,14,2);line([8,22,16,22]);line([12,18,12,22]);line([5,7,9,7]);break;
        case "lock": box(5,10,14,12,3);c.beginPath();c.arc(12,10,5,Math.PI,2*Math.PI);c.stroke();circle(12,15,1,true);line([12,16,12,18]);break;
        case "alarm": circle(12,14,8,false);line([12,9,12,14,16,16]);line([3,5,7,2]);line([17,2,21,5]);line([5,21,3,23]);line([19,21,21,23]);break;
        case "stopwatch": case "timer":
            circle(12,14,8,false);line([9,2,15,2]);line([12,2,12,6]);line([18,6,20,4]);line([12,9,12,14,kind === "timer" ? 8 : 16,kind === "timer" ? 10 : 11]);break;
        case "search": circle(10,10,6,false);line([15,15,21,21]);break;
        case "close": line([6,6,18,18]);line([18,6,6,18]);break;
        case "check": line([5,12,10,17,20,6]);break;
        case "menubar": box(2,4,20,16,3);line([3,9,21,9]);line([15,6.5,16,6.5]);line([18,6.5,19,6.5]);break;
        case "left": line([15,5,8,12,15,19]);break;
        case "right": line([9,5,16,12,9,19]);break;
        case "small": box(7,7,10,10,3);break;
        case "medium": box(3,7,18,10,4);break;
        case "large": box(3,3,18,18,5);break;
        default: [3,14].forEach(function(x){[3,14].forEach(function(y){box(x,y,7,7,1.5);});});
        }
    }
}
