#version 440
// Genie minimize/restore for MacMinimize.qml.
//
// The window screenshot is drawn inside a canvas that spans from the window's
// top-left down to the Dock icon. The fragment shader inverts the classic
// macOS "genie funnel" (see Harshil Shah, "Recreating the macOS Genie Effect"):
//
//   * the bottom edge of the window shrinks toward the icon and slides toward it,
//   * the top edge stays in place, then travels down after ~40% of the animation,
//   * the two sides are quadratic beziers between the narrow moving bottom edge
//     and the wide fixed top edge, which is what reads as the funnel.
//
// The mapping is analytic:
//   v     = position between the current top (0) and bottom (1) edge
//   q     = how far above the icon we are -> the side bezier parameter
//   left  = the left bezier x at this height
//   right = the right bezier x at this height
//   u     = (x - left) / (right - left)
// so a fragment shader can sample the source texture directly.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;       // canvas size in px
    vec4 win;            // window rect inside the canvas: x0, y0, x1, y1
    vec4 icon;           // Dock icon rect inside the canvas: x0, y0, x1, y1
    float progress;      // 0 = window at rest, 1 = swallowed by the icon
    float fadeAmount;    // 1 while minimizing (fade out at the end), 0 while restoring
};

layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float t = clamp(progress, 0.0, 1.0);

    // bottom edge narrows first (0 .. 0.5), then the whole window travels down (0.4 .. 1)
    float slide = smoothstep(0.0, 0.5, t);
    float tr = clamp((t - 0.4) / 0.6, 0.0, 1.0);
    tr = tr * tr * (3.0 - 2.0 * tr);

    float topY = mix(win.y, icon.y, tr);
    float botY = mix(win.w, icon.w, tr);

    if (p.y < topY || p.y > botY) {
        fragColor = vec4(0.0);
        return;
    }

    // vertical position inside the (shrinking) window
    float v = (p.y - topY) / max(botY - topY, 0.0001);

    // side bezier: 0 at the icon's top, 1 at the window's top
    float q = clamp((icon.y - p.y) / max(icon.y, 0.0001), 0.0, 1.0);
    float qe = q * q * (3.0 - 2.0 * q);

    float lbX = mix(win.x, icon.x, slide);   // bottom-left, slides to the icon
    float rbX = mix(win.z, icon.z, slide);   // bottom-right, slides to the icon
    float lX = mix(lbX, win.x, qe);          // curve up to the window's left edge
    float rX = mix(rbX, win.z, qe);          // curve up to the window's right edge

    if (p.x < lX || p.x > rX) {
        fragColor = vec4(0.0);
        return;
    }

    float u = (p.x - lX) / max(rX - lX, 0.0001);
    vec4 c = texture(src, clamp(vec2(u, v), vec2(0.0), vec2(1.0)));

    // the last sliver disappears into the icon
    float a = mix(1.0, 1.0 - smoothstep(0.85, 1.0, t), fadeAmount);
    fragColor = vec4(c.rgb, c.a * a) * qt_Opacity;
}
