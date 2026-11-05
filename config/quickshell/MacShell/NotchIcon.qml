import QtQuick

// Local vector icons using the rounded-cap visual language of Lucide.
// These canvas paths are original; no icon font or network request is needed.
Canvas {
    id: icon
    property string kind: "music"
    property color ink: "#F5F5F7"
    property bool filled: false
    property real strokeWidth: 1.8
    implicitWidth: 22; implicitHeight: 22
    onKindChanged: requestPaint()
    onInkChanged: requestPaint()
    onFilledChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset(); c.scale(width / 24, height / 24);
        c.strokeStyle = ink; c.fillStyle = ink; c.lineWidth = strokeWidth;
        c.lineCap = "round"; c.lineJoin = "round";
        function line(points) { c.beginPath(); c.moveTo(points[0], points[1]); for (let i = 2; i < points.length; i += 2) c.lineTo(points[i], points[i + 1]); c.stroke(); }
        function circle(x, y, r, fill) { c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); if (fill) c.fill(); else c.stroke(); }
        function roundRect(x, y, w, h, r) { c.beginPath(); c.roundedRect(x, y, w, h, r, r); c.fill(); }
        function triangle(x, y, w, h, backwards) {
            c.beginPath();
            if (backwards) { c.moveTo(x + w - 1, y); c.quadraticCurveTo(x + w, y, x + w, y + 1); c.lineTo(x + w, y + h - 1); c.quadraticCurveTo(x + w, y + h, x + w - 1, y + h); c.lineTo(x + 0.5, y + h / 2 + 0.8); c.quadraticCurveTo(x - 0.5, y + h / 2, x + 0.5, y + h / 2 - 0.8); }
            else { c.moveTo(x + 1, y); c.quadraticCurveTo(x, y, x, y + 1); c.lineTo(x, y + h - 1); c.quadraticCurveTo(x, y + h, x + 1, y + h); c.lineTo(x + w - 0.5, y + h / 2 + 0.8); c.quadraticCurveTo(x + w + 0.5, y + h / 2, x + w - 0.5, y + h / 2 - 0.8); }
            c.closePath(); c.fill();
        }
        switch (kind) {
        case "play": triangle(7, 4.5, 12, 15, false); break;
        case "pause": roundRect(6, 4, 4, 16, 1.2); roundRect(14, 4, 4, 16, 1.2); break;
        case "previous": triangle(2, 6, 9, 12, true); triangle(12, 6, 9, 12, true); break;
        case "next": triangle(3, 6, 9, 12, false); triangle(13, 6, 9, 12, false); break;
        case "shuffle":
            // Horizontal landings keep the arrowheads level. A small break in
            // the descending path keeps the crossing clear at playback size.
            c.beginPath();c.moveTo(3,7);c.lineTo(6,7);c.bezierCurveTo(7.2,7,8.5,8,9.4,9.3);c.stroke();
            c.beginPath();c.moveTo(14.6,14.7);c.bezierCurveTo(15.5,16,16.8,17,18,17);c.lineTo(21,17);c.stroke();
            c.beginPath();c.moveTo(3,17);c.lineTo(6,17);c.bezierCurveTo(10.5,17,13.5,7,18,7);c.lineTo(21,7);c.stroke();
            line([18,4,21,7,18,10]);line([18,14,21,17,18,20]);break;
        case "repeat":case "repeatOne":
            c.beginPath();c.moveTo(4,10);c.lineTo(4,8);c.quadraticCurveTo(4,5,7,5);c.lineTo(21,5);c.stroke();line([17,1,21,5,17,9]);
            c.beginPath();c.moveTo(20,14);c.lineTo(20,16);c.quadraticCurveTo(20,19,17,19);c.lineTo(3,19);c.stroke();line([7,15,3,19,7,23]);
            if(kind==="repeatOne")line([10,10,12,9,12,15]);break;
        case "output":c.beginPath();c.arc(12,10,8,Math.PI*0.7,Math.PI*2.3);c.stroke();c.beginPath();c.arc(12,10,4,Math.PI*0.7,Math.PI*2.3);c.stroke();line([7,22,12,15,17,22,7,22]);break;
        case "more":circle(5,12,1.7,true);circle(12,12,1.7,true);circle(19,12,1.7,true);break;
        case "grid":for(let row=0;row<2;row++)for(let col=0;col<2;col++)roundRect(3+col*11,3+row*11,7,7,2);break;
        case "waveform":for(let i=0;i<5;i++){const h=[6,13,20,13,6][i];line([4+i*4,12-h/2,4+i*4,12+h/2]);}break;
        case "muted":line([3,9,7,9,12,5,12,19,7,15,3,15,3,9]);line([16,9,22,15]);line([22,9,16,15]);break;
        case "home":line([3,11,12,3,21,11]);line([5,10,5,21,10,21,10,15,14,15,14,21,19,21,19,10]);break;
        case "monitor":c.beginPath();c.roundedRect(2,3,20,14,2,2);c.stroke();line([12,17,12,21]);line([7,21,17,21]);break;
        case "chevron": line([9, 6, 15, 12, 9, 18]); break;
        case "chevronLeft": line([15, 6, 9, 12, 15, 18]); break;
        case "close": line([6, 6, 18, 18]); line([18, 6, 6, 18]); break;
        case "plus": circle(12,12,9,false); line([12,8,12,16]); line([8,12,16,12]); break;
        case "download": line([12,3,12,19]);line([6,13,12,19,18,13]);break;
        case "tick": line([5,12,10,17,20,6]);break;
        case "checkmark": line([5,12,10,17,20,6]); break;
        case "stats": line([3,21,21,21]);line([6,16,6,10]);line([12,16,12,3]);line([18,16,18,7]);break;
        case "statsOverview": c.beginPath();c.roundedRect(3,3,18,10,2,2);c.stroke();circle(5,19,1.5,true);circle(12,19,1.5,true);circle(19,19,1.5,true);break;
        case "statsCompare": c.beginPath();c.roundedRect(3,3,7,18,2,2);c.stroke();c.beginPath();c.roundedRect(14,3,7,18,2,2);c.stroke();break;
        case "statsCpu": c.beginPath();c.roundedRect(6,6,12,12,2,2);c.stroke();c.beginPath();c.roundedRect(9,9,6,6,1,1);c.stroke();for(let p=8;p<=16;p+=4){line([p,2,p,5]);line([p,19,p,22]);line([2,p,5,p]);line([19,p,22,p]);}break;
        case "statsRam": c.beginPath();c.roundedRect(3,5,18,13,2,2);c.stroke();for(let p=6;p<=18;p+=4)line([p,18,p,22]);c.beginPath();c.roundedRect(6,8,4,7,1,1);c.stroke();c.beginPath();c.roundedRect(14,8,4,7,1,1);c.stroke();break;
        case "statsGpu": line([12,2,21,7,12,12,3,7,12,2]);line([3,7,3,17,12,22,21,17,21,7]);line([12,12,12,22]);break;
        case "statsDisk": c.beginPath();c.roundedRect(3,5,18,16,3,3);c.stroke();line([3,15,21,15]);line([8,9,16,9]);line([7,18,11,18]);circle(17,18,0.8,true);break;
        case "statsBattery": c.beginPath();c.roundedRect(2,6,18,12,3,3);c.stroke();line([22,10,22,14]);line([7,12,15,12]);break;
        case "statsNetwork": line([8,4,8,20]);line([4,8,8,4,12,8]);line([16,4,16,20]);line([12,16,16,20,20,16]);break;
        case "statsTemp": c.beginPath();c.moveTo(9,14);c.lineTo(9,5);c.bezierCurveTo(9,1,15,1,15,5);c.lineTo(15,14);c.bezierCurveTo(21,19,15,25,9,22);c.bezierCurveTo(5,20,5,16,9,14);c.closePath();c.stroke();line([12,6,12,17]);circle(12,18,1.5,true);line([18,7,21,7]);line([18,11,21,11]);break;
        case "check": circle(12,12,10,true); c.strokeStyle="#FFFFFF"; c.lineWidth=2.2; line([7.5,12,10.5,15,16.5,8.5]); break;
        case "circle": circle(12,12,8,false); break;
        case "reset": c.beginPath(); c.arc(12,12,8,-0.7,Math.PI*1.7); c.stroke(); line([19,3,19,8,14,8]); break;
        case "undo": line([8,4,3,9,8,14]); c.beginPath(); c.moveTo(4,9); c.lineTo(13,9); c.quadraticCurveTo(21,9,21,17); c.stroke(); break;
        case "edit": line([4,16,15,5,19,9,8,20,4,20,4,16]); line([13,7,17,11]); break;
        case "settings": line([4,6,20,6]); line([4,12,20,12]); line([4,18,20,18]); circle(9,6,2.4,true); circle(16,12,2.4,true); circle(8,18,2.4,true); break;
        case "lyrics":
            c.beginPath(); c.moveTo(8, 4); c.lineTo(17, 4); c.quadraticCurveTo(21, 4, 21, 8); c.lineTo(21, 13); c.quadraticCurveTo(21, 17, 17, 17); c.lineTo(10, 17); c.lineTo(5, 21); c.lineTo(5, 16); c.quadraticCurveTo(3, 15, 3, 12); c.lineTo(3, 8); c.quadraticCurveTo(3, 4, 8, 4); c.closePath();
            if (filled) { c.fill(); c.globalCompositeOperation = "destination-out"; } else c.stroke();
            circle(8, 10.5, 0.85, true); circle(12, 10.5, 0.85, true); circle(16, 10.5, 0.85, true);
            c.globalCompositeOperation = "source-over"; break;
        case "pomodoro":
        case "timer": circle(12, 13, 8, false); line([9, 2, 15, 2]); line([12, 8, 12, 13, 15, 15]); break;
        // Friendly outline family shared by live tools and their navigation.
        case "toolMusic":line([9,17,9,6,20,4,20,15]);line([9,10,20,8]);circle(6,17,3,false);circle(17,15,3,false);break;
        case "toolWater":
            c.beginPath();c.moveTo(12,3);c.bezierCurveTo(10,7,5,12,5,16);c.bezierCurveTo(5,24,19,24,19,16);c.bezierCurveTo(19,12,14,7,12,3);c.closePath();c.stroke();break;
        case "toolShelf":
            c.beginPath();c.moveTo(3,10);c.lineTo(3,19);c.quadraticCurveTo(3,21,5,21);c.lineTo(19,21);c.quadraticCurveTo(21,21,21,19);c.lineTo(21,10);c.stroke();line([12,3,12,15]);line([7,10,12,15,17,10]);break;
        case "toolTodo":
            c.beginPath();c.roundedRect(3,3,18,18,4,4);c.stroke();line([7,9,9,11,12,7]);line([15,9,18,9]);line([7,16,17,16]);break;
        case "toolFolder":
            c.beginPath();c.moveTo(3,7);c.lineTo(3,5);c.quadraticCurveTo(3,3,5,3);c.lineTo(10,3);c.lineTo(13,6);c.lineTo(19,6);c.quadraticCurveTo(21,6,21,8);c.lineTo(21,19);c.quadraticCurveTo(21,21,19,21);c.lineTo(5,21);c.quadraticCurveTo(3,21,3,19);c.closePath();c.stroke();break;
        case "toolCheck":circle(12,12,9,false);line([7.5,12,10.5,15,16.5,8.5]);break;
        // Rounded outline symbols for the Pomodoro phase family.
        case "pomoWork":
            c.beginPath();c.roundedRect(4,3,16,13,2.5,2.5);c.stroke();
            c.beginPath();c.moveTo(2,20);c.quadraticCurveTo(12,22,22,20);c.stroke();break;
        case "pomoRest":
            c.beginPath();c.moveTo(4,7);c.lineTo(16,7);c.lineTo(16,14);c.bezierCurveTo(16,21,4,21,4,14);c.closePath();c.stroke();
            c.beginPath();c.moveTo(16,8);c.bezierCurveTo(24,6,24,16,16,15);c.stroke();line([8,2,8,4]);line([12,2,12,4]);break;
        case "pomoLong":
            c.beginPath();c.moveTo(12,21);c.lineTo(12,13);c.bezierCurveTo(12,6,17,2,22,3);c.bezierCurveTo(22,10,17,14,12,13);c.stroke();
            c.beginPath();c.moveTo(12,17);c.bezierCurveTo(5,18,2,13,2,8);c.bezierCurveTo(9,8,12,11,12,17);c.stroke();break;
        case "pomoCustom":
            c.beginPath();c.moveTo(10,6);c.quadraticCurveTo(11,12,18,14);c.quadraticCurveTo(11,16,10,22);c.quadraticCurveTo(9,16,2,14);c.quadraticCurveTo(9,12,10,6);c.closePath();c.stroke();line([19,2,19,6]);line([17,4,21,4]);break;
        case "pomoPlay":line([8,4,20,12,8,20,8,4]);break;
        case "pomoPause":line([8,5,8,19]);line([16,5,16,19]);break;
        case "pomoSkip":line([5,5,16,12,5,19,5,5]);line([21,5,21,19]);break;
        case "briefcase":
            c.beginPath();c.roundedRect(3,7,18,14,2.5,2.5);c.stroke();line([8,7,8,4,16,4,16,7]);line([3,12,9,14,15,14,21,12]);line([10,12,14,12,14,16,10,16,10,12]);break;
        case "leaf":
            c.beginPath();c.moveTo(20,3);c.bezierCurveTo(8,2,2,7,5,15);c.bezierCurveTo(9,23,21,19,20,3);c.closePath();c.stroke();c.beginPath();c.moveTo(4,21);c.quadraticCurveTo(8,13,15,9);c.stroke();break;
        case "power":c.beginPath();c.arc(12,13,8,-Math.PI*0.35,Math.PI*1.35);c.stroke();line([12,2,12,11]);break;
        case "info":circle(12,12,9,false);line([12,11,12,17]);circle(12,7,0.8,true);break;
        case "bolt":line([13,2,5,13,11,13,10,22,19,10,13,10,13,2]);break;
        case "expand":line([9,3,3,3,3,9]);line([15,21,21,21,21,15]);line([3,3,9,9]);line([21,21,15,15]);break;
        case "collapse":line([3,9,9,9,9,3]);line([21,15,15,15,15,21]);line([3,3,9,9]);line([21,21,15,15]);break;
        case "focus": circle(12,12,8,false); circle(12,12,4,false); circle(12,12,1,true); break;
        case "cup": line([4,6,16,6,16,14]); c.beginPath(); c.moveTo(16,14); c.quadraticCurveTo(16,19,10,19); c.quadraticCurveTo(4,19,4,14); c.lineTo(4,6); c.stroke(); c.beginPath(); c.moveTo(16,7); c.bezierCurveTo(23,5,23,14,16,13); c.stroke(); line([8,1,8,3]); line([12,1,12,3]); break;
        case "water": c.beginPath(); c.moveTo(12,2); c.bezierCurveTo(9,7,5,11,5,15); c.arc(12,15,7,Math.PI,0,true); c.bezierCurveTo(19,11,15,7,12,2); c.closePath(); c.fill(); break;
        case "bell":
        case "bellOff": c.beginPath(); c.moveTo(5,17); c.quadraticCurveTo(7,15,7,10); c.bezierCurveTo(7,3,17,3,17,10); c.quadraticCurveTo(17,15,19,17); c.closePath(); c.stroke(); line([10,21,14,21]); if(kind==="bellOff")line([3,3,21,21]); break;
        case "folder": c.beginPath(); c.moveTo(2,7); c.lineTo(2,5); c.quadraticCurveTo(2,3,4,3); c.lineTo(9,3); c.lineTo(12,6); c.lineTo(20,6); c.quadraticCurveTo(22,6,22,8); c.lineTo(22,19); c.quadraticCurveTo(22,21,20,21); c.lineTo(4,21); c.quadraticCurveTo(2,21,2,19); c.closePath(); c.fill(); break;
        case "shelf": line([3,8,3,20,21,20,21,8]); line([8,11,12,15,16,11]); line([12,3,12,15]); break;
        case "copy": roundRect(8,7,12,14,2);line([15,3,4,3,4,16]);break;
        case "trash": line([4,6,20,6]);line([9,3,15,3]);c.beginPath();c.moveTo(6,6);c.lineTo(7,21);c.lineTo(17,21);c.lineTo(18,6);c.stroke();line([10,10,10,17]);line([14,10,14,17]);break;
        case "file": c.beginPath(); c.moveTo(5,2); c.lineTo(14,2); c.lineTo(20,8); c.lineTo(20,22); c.lineTo(5,22); c.closePath(); c.stroke(); line([14,2,14,8,20,8]); line([8,13,16,13]); line([8,17,14,17]); break;
        case "todo": roundRect(3,4,4,4,1); roundRect(3,11,4,4,1); roundRect(3,18,4,4,1); line([11,6,21,6]); line([11,13,21,13]); line([11,20,18,20]); break;
        case "weather": circle(12,12,4,false);for(let i=0;i<8;i++){const a=i*Math.PI/4;line([12+Math.cos(a)*7,12+Math.sin(a)*7,12+Math.cos(a)*9.5,12+Math.sin(a)*9.5]);}break;
        case "calendar": c.beginPath();c.roundedRect(3,5,18,16,3,3);c.stroke();line([3,10,21,10]);line([8,3,8,7]);line([16,3,16,7]);for(let row=0;row<2;row++)for(let col=0;col<3;col++)circle(7+col*5,14+row*4,.65,true);break;
        case "bluetooth": line([7,7,17,17,12,22,12,2,17,7,7,17]); break;
        case "headphones": c.beginPath(); c.arc(12,11,8,Math.PI,0); c.stroke(); line([4,10,4,19,8,19,8,12,4,12]); line([20,10,20,19,16,19,16,12,20,12]); break;
        case "speaker": line([5,9,9,9,14,4,14,20,9,15,5,15,5,9]); c.beginPath(); c.arc(14,12,6,-0.8,0.8); c.stroke(); break;
        case "mouse": c.beginPath(); c.roundedRect(6,2,12,20,6,6); c.stroke(); line([12,3,12,9]); break;
        case "keyboard": c.beginPath(); c.roundedRect(2,5,20,14,2,2); c.stroke(); for(let row=0;row<2;row++)for(let col=0;col<5;col++)circle(5+col*3.5,9+row*4,0.7,true); line([7,16,17,16]); break;
        case "phone": c.beginPath(); c.roundedRect(6,2,12,20,3,3); c.stroke(); line([10,5,14,5]); circle(12,19,0.7,true); break;
        case "gamepad": c.beginPath(); c.moveTo(7,7); c.lineTo(17,7); c.bezierCurveTo(21,7,23,19,19,19); c.lineTo(15,15); c.lineTo(9,15); c.lineTo(5,19); c.bezierCurveTo(1,19,3,7,7,7); c.stroke(); line([6,11,10,11]); line([8,9,8,13]); circle(16,10,0.8,true); circle(19,12,0.8,true); break;
        case "recording": circle(12, 12, 8, false); circle(12, 12, 4, true); break;
        case "charging": line([13, 2, 5, 14, 11, 14, 10, 22, 19, 9, 13, 9, 13, 2]); break;
        case "brightness": circle(12, 12, 4, false); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; line([12 + Math.cos(a) * 7, 12 + Math.sin(a) * 7, 12 + Math.cos(a) * 9.5, 12 + Math.sin(a) * 9.5]); } break;
        case "volumeOff": line([3,9,7,9,12,5,12,19,7,15,3,15,3,9]); line([17,9,23,15]); line([23,9,17,15]); break;
        case "volume": line([3, 9, 7, 9, 12, 5, 12, 19, 7, 15, 3, 15, 3, 9]); c.beginPath(); c.arc(12, 12, 5, -0.8, 0.8); c.stroke(); c.beginPath(); c.arc(12, 12, 8, -0.8, 0.8); c.stroke(); break;
        default: line([10, 17, 10, 5, 20, 3, 20, 15]); circle(7, 17, 3, false); circle(17, 15, 3, false); break;
        }
    }
}
