.pragma library
.import "NotchGeometry.js" as Geometry

// One path for both the solid surface and the glass alpha mask.
function trace(c, w, h, mode, progress, music, scale) {
    scale = typeof scale === "number" && isFinite(scale) ? Math.max(0,scale) : 1;
    c.beginPath();
    if (mode === "attached") {
        var wing = Math.min(Geometry.wing(mode, progress, music)*(1+(scale-1)*progress), Math.max(0,w/2));
        var r = Math.min(h / 2, Math.max(0,(w-2*wing)/2), 12*(1-progress) + Geometry.panelRadius*scale*progress);
        c.moveTo(0, 0); c.quadraticCurveTo(wing, 0, wing, wing);
        var arc = 0.55228475 * r;
        c.lineTo(wing, h - r); c.bezierCurveTo(wing, h-r+arc, wing+r-arc, h, wing+r, h);
        c.lineTo(w-wing-r, h); c.bezierCurveTo(w-wing-r+arc, h, w-wing, h-r+arc, w-wing, h-r);
        c.lineTo(w - wing, wing); c.quadraticCurveTo(w - wing, 0, w, 0);
    } else {
        // Compact floating surfaces are capsules at every size. As they open,
        // blend back to the expanded panel's corner radius and curvature.
        var radius = Math.min(w / 2, h / 2, (h / 2) * (1 - progress) + Geometry.panelRadius * scale * progress);
        var k = 0.55228475;
        c.moveTo(radius, 0); c.lineTo(w - radius, 0);
        c.bezierCurveTo(w - radius + k * radius, 0, w, radius - k * radius, w, radius);
        c.lineTo(w, h - radius);
        c.bezierCurveTo(w, h - radius + k * radius, w - radius + k * radius, h, w - radius, h);
        c.lineTo(radius, h);
        c.bezierCurveTo(radius - k * radius, h, 0, h - radius + k * radius, 0, h - radius);
        c.lineTo(0, radius);
        c.bezierCurveTo(0, radius - k * radius, radius - k * radius, 0, radius, 0);
    }
    c.closePath();
}

// Build the GPU content mask from the exact same outline as the surface.
// A native Shape follows every geometry update without a delayed Canvas frame.
function path(w, h, mode, progress, music, scale) {
    var parts=[];
    var pen={
        beginPath:function(){parts=[];},
        moveTo:function(x,y){parts.push("M "+x+","+y);},
        lineTo:function(x,y){parts.push("L "+x+","+y);},
        quadraticCurveTo:function(cx,cy,x,y){parts.push("Q "+cx+","+cy+" "+x+","+y);},
        bezierCurveTo:function(ax,ay,bx,by,x,y){parts.push("C "+ax+","+ay+" "+bx+","+by+" "+x+","+y);},
        closePath:function(){parts.push("Z");}
    };
    trace(pen,w,h,mode,progress,music,scale);
    return parts.join(" ");
}
