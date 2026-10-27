.pragma library

// One Lamé curve for fills, masks, borders, glass and compositor settings.
// |x/rx|^n + |y/ry|^n = 1; n=2 is circular, n=4 is a squircle.
function exponent(amount) { return 2 + 2 * Math.max(0, Math.min(1, amount)); }

// Share normalized corner samples between surfaces instead of repeating the
// trigonometry for every rectangle. Bound the cache during Dock slider drags.
var samples = {};
var sampleKeys = [];
function unitSamples(count, n) {
    var key=count+":"+n;
    if (samples[key]) return samples[key];
    var result=[], e=2/n;
    for (var c=0;c<4;++c) {
        for (var i=0;i<=count;++i) {
            var angle=-Math.PI/2+c*Math.PI/2+i*Math.PI/2/count;
            var co=Math.cos(angle),si=Math.sin(angle);
            result.push([Math.sign(co)*Math.pow(Math.abs(co),e),Math.sign(si)*Math.pow(Math.abs(si),e)]);
        }
    }
    if (sampleKeys.length>=8) delete samples[sampleKeys.shift()];
    sampleKeys.push(key);samples[key]=result;
    return result;
}

function points(width, height, radius, amount, inset, segments) {
    inset = inset || 0;
    var w = Math.max(0, width - 2 * inset), h = Math.max(0, height - 2 * inset);
    var r = Math.max(0, Math.min(radius - inset, Math.min(w, h) / 2));
    if (w <= 0 || h <= 0) return [];
    if (r <= 0.001) return [Qt.point(inset, inset), Qt.point(width-inset, inset),
        Qt.point(width-inset, height-inset), Qt.point(inset, height-inset), Qt.point(inset, inset)];
    var count = Math.max(16, Math.min(96, segments || 48));
    var unit=unitSamples(count,exponent(amount));
    var corners = [[w-r,r,-Math.PI/2,0], [w-r,h-r,0,Math.PI/2],
        [r,h-r,Math.PI/2,Math.PI], [r,r,Math.PI,3*Math.PI/2]];
    var result = [];
    for (var c=0; c<4; ++c) {
        var corner = corners[c];
        for (var i=0; i<=count; ++i) {
            var p=unit[c*(count+1)+i];
            result.push(Qt.point(inset+corner[0]+r*p[0],inset+corner[1]+r*p[1]));
        }
    }
    result.push(result[0]);
    return result;
}

function path(width, height, radius, amount, inset, segments) {
    var contour=points(width,height,radius,amount,inset,segments);
    if (!contour.length) return "";
    var out="M "+contour[0].x+" "+contour[0].y;
    for (var i=1; i<contour.length; ++i) out+=" L "+contour[i].x+" "+contour[i].y;
    return out+" Z";
}

function trace(ctx, width, height, radius, amount, inset) {
    var contour=points(width,height,radius,amount,inset);
    ctx.beginPath();
    if (!contour.length) return;
    ctx.moveTo(contour[0].x,contour[0].y);
    for (var i=1; i<contour.length; ++i) ctx.lineTo(contour[i].x,contour[i].y);
    ctx.closePath();
}

// A continuous body plus the existing rounded tooltip/menu pointer.
function tailPath(width, bodyHeight, radius, tailHeight, tailX, tailHalfWidth, amount, inset) {
    var seg=48, contour=points(width,bodyHeight,radius,amount,inset,seg);
    if (!contour.length) return "";
    var b=bodyHeight-inset, bottom=bodyHeight+tailHeight-inset;
    var out="M "+contour[0].x+" "+contour[0].y;
    for (var i=1; i<contour.length; ++i) {
        if (i===2*(seg+1)) {
            out+=" L "+(tailX+tailHalfWidth)+" "+b
                +" C "+(tailX+tailHalfWidth*0.55)+" "+b+" "+(tailX+2)+" "+bottom+" "+tailX+" "+bottom
                +" C "+(tailX-2)+" "+bottom+" "+(tailX-tailHalfWidth*0.55)+" "+b+" "+(tailX-tailHalfWidth)+" "+b;
        }
        out+=" L "+contour[i].x+" "+contour[i].y;
    }
    return out+" Z";
}
