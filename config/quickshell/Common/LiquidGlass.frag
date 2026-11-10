#version 440
#extension GL_GOOGLE_include_directive : require
// One source of truth for MacShell Liquid Glass. The previous deep-glass
// material is restored below. Build flags adapt uniform layouts and contours;
// every refractive surface calls shadeGlass(), including notch and sliders.
// Text, voice and toggle coats are overlays over that shared material.
// Rebuild: python scripts/build-glass-shaders.py

#if defined(GLASS_TEXT)
// The lock screen clock's material, after iOS 26 / macOS 26:
//
//   Solid (mode 0) — Apple's vibrancy: the digits are the wallpaper behind them pushed most of the way to the tint
//                     colour (white by default), so they glow with a hint of the background's colour. Crisp, no rim.
//   Glass (mode 1) — Liquid Glass: clear, slightly frosted digits with real thickness. The wallpaper is bent at the
//                     rounded edges (strongest right at the edge), a bright glint runs along the edges facing the light
//                     and a softer one on the opposite side (light passing through the glass), a fine darker line just
//                     inside the edge gives the glass its definition. `lightDir` follows the pointer, like tilting a phone.
//
// `mask` = sharp glyph coverage; `hmap` = a lightly blurred copy whose slope finds the rim.
// Build:  /usr/lib/qt6/bin/qsb --qt6 -o glasstext.frag.qsb glasstext.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // this item in px
    vec2 srcSize;       // backdrop texture size in px (logical)
    vec2 srcOffset;     // this item's top-left inside the backdrop, px
    float mode;         // 0 solid … 1 glass (animatable: styles cross-fade)
    float intensity;    // solid: how far toward the tint (0.55‥0.95); glass: frost amount (0 clear … 1 milky)
    float refract;      // glass: backdrop shift at the very edge, px
    float bevel;        // rim slope scale
    vec4 tint;          // tint colour (white = none)
    vec2 lightDir;      // direction the light comes FROM (screen space, normalised)
};

layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;
layout(binding = 3) uniform sampler2D hmap;

float H(vec2 uv) { return texture(hmap, uv).a; }
vec3 bgAt(vec2 p, float lod) { return textureLod(src, clamp(p / srcSize, vec2(0.001), vec2(0.999)), lod).rgb; }

void main()
{
    vec2 uv = qt_TexCoord0;
    float a = texture(mask, uv).a;
    if (a <= 0.002) { fragColor = vec4(0.0); return; }

    // rim from the slope of the softened glyphs: 0 in the flat middle of a stroke, 1 at the edge
    vec2 d = 1.5 / itemSize;
    vec2 g = vec2(H(uv + vec2(d.x, 0.0)) - H(uv - vec2(d.x, 0.0)),
                  H(uv + vec2(0.0, d.y)) - H(uv - vec2(0.0, d.y)));
    float slope = length(g);
    float rim = clamp(slope * bevel, 0.0, 1.0);
    vec2 n = slope > 1e-5 ? -g / slope : vec2(0.0);     // points out of the glyph
    vec2 p = uv * itemSize + srcOffset;
    vec3 tintC = tint.rgb;

    // ── Solid: vibrancy ──
    vec3 bgS = bgAt(p, 2.0);
    float ls = dot(bgS, vec3(0.299, 0.587, 0.114));
    bgS = mix(vec3(ls), bgS, 1.35);                      // keep the wallpaper's hue in it
    vec3 solid = mix(bgS, tintC, clamp(intensity, 0.0, 1.0)) + 0.04;

    // ── Glass ──
    // edge bending: a rounded edge bends the light most where it is steepest
    float bend = rim * rim * (3.0 - 2.0 * rim);
    vec2 shift = n * refract * bend;
    float lod = 0.6 + 2.2 * intensity;
    vec3 bg;
    bg.r = bgAt(p - shift * 1.08, lod).r;
    bg.g = bgAt(p - shift, lod).g;
    bg.b = bgAt(p - shift * 0.92, lod).b;
    float lg = dot(bg, vec3(0.299, 0.587, 0.114));
    bg = mix(vec3(lg), bg, 1.2);
    vec3 glass = bg * 1.05 + 0.05;
    glass = mix(glass, mix(vec3(1.0), tintC, 0.85), 0.10 + 0.55 * intensity);   // frost (and tint)
    glass = mix(glass, glass * tintC, 0.35 * (1.0 - tintC.r * tintC.g * tintC.b));  // coloured glass when tinted
    float facing = dot(n, normalize(lightDir));
    float edge = pow(rim, 2.2);
    glass += edge * pow(max(facing, 0.0), 1.5) * 0.85;              // glint on the lit edges
    glass += edge * pow(max(-facing, 0.0), 2.0) * 0.30;             // light through the glass, far side
    glass += pow(rim, 5.0) * 0.18;                                  // a hairline all round
    glass -= smoothstep(0.35, 0.75, rim) * (1.0 - smoothstep(0.75, 1.0, rim)) * 0.10;  // definition line inside the edge

    vec3 col = mix(solid, glass, clamp(mode, 0.0, 1.0));
    fragColor = vec4(clamp(col, 0.0, 1.0) * a, a) * qt_Opacity;
}

#elif defined(GLASS_COAT)
// Liquid-glass coat for the iOS 26 toggle knob (SSwitch in MacDock.qml).
//
// Build:  qsb --qt6 -o knobglass.frag.qsb knobglass.frag
//
// The coat is drawn *over* the white capsule. On a solid accent track the cues
// that actually read as glass are the ones that brighten or tint the white pill:
//   * a capsule SDF for coverage and for the distance-to-edge
//   * a broad vertical gradient: clear at the top, accent-tinted at the bottom
//   * a fresnel rim, brightest along the top edge
//   * a caustic highlight + trailing shade that sweeps across while it travels
// Everything is scaled by `glass` (0..1) so the coat can fade in and out, and the
// output is premultiplied, matching the other shaders in this config.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // knob size in px
    float radius;       // capsule radius (itemSize.y / 2)
    vec4 tint;          // accent colour of the track (rgb, unused alpha)
    float glass;        // 0 = no coat, 1 = full glass
    float sweep;        // specular band position, roughly -0.3 .. 1.3
    float press;        // 1 while the knob is held
    float squircle;
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    vec2 v = max(q, 0.0);
    float n = 2.0 + 2.0 * clamp(squircle, 0.0, 1.0);
    return pow(pow(v.x,n)+pow(v.y,n),1.0/n) + min(max(q.x,q.y),0.0) - r;
}

void main() {
    vec2  sz = max(itemSize, vec2(1.0));
    vec2  hs = sz * 0.5;
    vec2  p  = qt_TexCoord0 * sz;
    float r  = clamp(radius, 0.0, hs.y);

    float d   = sdRoundBox(p - hs, hs, r);              // < 0 inside the capsule
    float cov = 1.0 - smoothstep(-0.75, 0.75, d);       // antialiased coverage
    if (cov <= 0.0 || glass <= 0.0) { fragColor = vec4(0.0); return; }

    float inside   = clamp(-d, 0.0, 1.0e6);                      // px, inward from the edge
    float edge     = 1.0 - smoothstep(0.0, 2.4, inside);         // 1 right at the border
    float upness   = clamp(1.0 - p.y / sz.y, 0.0, 1.0);          // 1 at the top
    float downness = clamp((p.y / sz.y - 0.45) / 0.55, 0.0, 1.0);

    // broad material gradient: clear at the top, accent-tinted towards the bottom
    float bodyA  = smoothstep(0.34, 1.0, p.y / sz.y) * 0.24;
    // thin rims: bright along the top curve, weighted down along the bottom one
    float rimTop = edge * upness * upness * 0.75;
    float rimBot = edge * downness * 0.42;
    // accent bleed all around, so the glass picks up the track colour
    float bleedA = edge * 0.13;

    // caustic: a bright core with a faint tinted shade trailing behind it.
    // On a white pill a pure white highlight is invisible on its own, so the pair
    // of light + shade is what reads as light moving through glass.
    float t     = (p.x / sz.x - (p.y / sz.y - 0.5) * 0.42 - sweep) * 5.0;
    float core  = exp(-t * t);
    float trail = exp(-pow(t - 1.7, 2.0));
    float specA = core * (0.50 + 0.22 * press);
    float shadeA = trail * 0.13;

    vec3  c = vec3(0.0);
    float a = 0.0;

    #define OVER(col, alpha) { c = (col) * (alpha) + c * (1.0 - (alpha)); \
                              a = (alpha) + a * (1.0 - (alpha)); }

    OVER(tint.rgb, bleedA);                                   // accent bleed on the rim
    OVER(mix(tint.rgb, vec3(1.0), 0.62), 0.10);               // thin milky film over the whole pill
    OVER(mix(tint.rgb, vec3(0.62), 0.35), bodyA);             // tinted body towards the bottom
    OVER(mix(tint.rgb, vec3(0.28), 0.45), shadeA);            // caustic shade
    OVER(vec3(1.0), specA);                                   // caustic core
    OVER(vec3(1.0), rimTop);                                  // top fresnel rim
    OVER(mix(tint.rgb, vec3(0.30), 0.55), rimBot);            // glass thickness at the bottom

    fragColor = vec4(c, clamp(a, 0.0, 1.0)) * cov * glass * qt_Opacity;
}

#elif defined(GLASS_VOICE)
// qsb --qt6 -o luma-mic-clear.frag.qsb luma-mic-orb.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float micVolume;
    float iTime;
    vec2 resolution;
};

vec3 spectrum(float t) {
    return 0.52 + 0.48 * cos(6.2831853 * (t + vec3(0.04, 0.37, 0.70)));
}

void main() {
    // Unit circle matches the shared glass exactly, without inset scaling.
    vec2 p = (qt_TexCoord0 - 0.5) * 2.0;
    float r = length(p);
    float pixel = 2.0 / max(min(resolution.x, resolution.y), 1.0);
    float coverage = 1.0 - smoothstep(1.0 - pixel, 1.0, r);
    if (coverage <= 0.0) { fragColor = vec4(0.0); return; }
    float v = clamp(micVolume, 0.0, 1.0);
    float t = iTime * 1.1;

    // Match the search capsule's black-to-clear vertical gradient. The lower
    // hemisphere exposes the sharp refracted backdrop, without a milky tint.
    float y = qt_TexCoord0.y;
    float cap = y < 0.25 ? mix(0.98, 0.86, smoothstep(0.0, 0.25, y))
              : y < 0.65 ? mix(0.86, 0.44, smoothstep(0.25, 0.65, y))
                         : mix(0.44, 0.03, smoothstep(0.65, 1.0, y));
    vec3 color = vec3(0.005, 0.009, 0.012);
    float alpha = cap;
    vec3 premultiplied = color * alpha;

    // Voice sits on the exact horizontal diameter. Edge taper keeps the line
    // centered while speech deforms its middle, leaving the sphere circular.
    float taper = pow(max(0.0, 1.0 - p.x * p.x), 0.8);
    float wave = v * 0.21 * taper * (0.66 * sin(p.x * 5.4 + t)
                                  + 0.34 * sin(p.x * 9.0 - t * 1.4));
    float dist = p.y - wave;
    float core = exp(-pow(dist / (0.014 + pixel * 0.34 + v * 0.015), 2.0));
    float glow = exp(-pow(dist / (0.055 + v * 0.065), 2.0));
    vec3 rainbow = spectrum(p.x * 0.56 + 0.12 * sin(t * 0.3));
    float glowAlpha = glow * (0.17 + 0.32 * v) * taper;
    premultiplied = rainbow * glowAlpha + premultiplied * (1.0 - glowAlpha);
    alpha = glowAlpha + alpha * (1.0 - glowAlpha);
    float lineAlpha = core * (0.76 + 0.22 * v) * (0.3 + 0.7 * taper);
    vec3 lineColor = mix(vec3(0.91, 0.97, 1.0), mix(rainbow, vec3(1.0), 0.7), v);
    premultiplied = lineColor * lineAlpha + premultiplied * (1.0 - lineAlpha);
    alpha = lineAlpha + alpha * (1.0 - lineAlpha);

    // Small, transparent highlights leave the background visible through glass.
    float rim = exp(-pow((1.0 - r) / (0.008 + pixel * 0.65), 2.0));
    float angle = atan(p.y, p.x);
    vec3 rimColor = mix(vec3(0.76, 0.87, 0.95), spectrum(angle / 6.2831853 + 0.16), v * 0.72);
    float rimAlpha = rim * (0.28 + 0.24 * v);
    premultiplied = rimColor * rimAlpha + premultiplied * (1.0 - rimAlpha);
    alpha = rimAlpha + alpha * (1.0 - rimAlpha);
    float glint = exp(-pow((p.x + 0.53) / 0.10, 2.0) - pow((p.y + 0.48) / 0.22, 2.0));
    float glintAlpha = glint * 0.24;
    premultiplied = vec3(0.80, 0.91, 1.0) * glintAlpha + premultiplied * (1.0 - glintAlpha);
    alpha = glintAlpha + alpha * (1.0 - glintAlpha);
    fragColor = vec4(premultiplied, alpha) * coverage * qt_Opacity;
}

#else
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

#if defined(GLASS_NOTCH)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 cropSize;
    float captureMargin;
    float strength;
    float wingSize;
    float radius;
    vec4 optics; // thickness, dispersion, magnify, saturation
    vec4 finish; // tint, rim, grain, residual blur
} ubuf;
layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D maskTex;
layout(binding = 3) uniform sampler2D clearSrc;

float shape(vec2 uv) {
    if (any(lessThan(uv, vec2(0))) || any(greaterThan(uv, vec2(1)))) return 0.0;
    return texture(maskTex, uv).a;
}

// Optical distance inside the body. The shared alpha mask remains authoritative
// for the attached shoulders and every frame of the open/close transition.
float bodyDistance(vec2 p) {
    vec2 halfSize = max(ubuf.itemSize * 0.5 - vec2(ubuf.wingSize, 0.0), vec2(1.0));
    float r = ubuf.wingSize > 0.0 && p.y < ubuf.itemSize.y * 0.5 ? 0.0 : ubuf.radius;
    vec2 q = abs(p - ubuf.itemSize * 0.5) - halfSize + vec2(r);
    return length(max(q, vec2(0))) + min(max(q.x, q.y), 0.0) - r;
}


float glassTintAmount;
float glassOpticalStrength;
#define itemSize ubuf.itemSize
#define glassSize itemSize
#define srcSize ubuf.cropSize
#define srcOffset vec2(ubuf.captureMargin)
#define qt_Opacity ubuf.qt_Opacity
#define pad 0.0
#define radius ubuf.radius
#define bezel 22.0
#define thickness (ubuf.optics.x * glassOpticalStrength)
#define dispersion (ubuf.optics.y * glassOpticalStrength)
#define blurPx ubuf.finish.w
#define tintMix glassTintAmount
#define saturation ubuf.optics.w
#define dark 1.0
#define debug 0.0
#define rim (ubuf.finish.y * ubuf.strength)
#define grain (ubuf.finish.z * ubuf.strength)
#define magnify (ubuf.optics.z * glassOpticalStrength)
#define shadowAmt 0.0
#define rimTint 0.0
#define ringW 0.0
#define flatInner 0.0
#define squircle 0.0
#elif defined(GLASS_SLIDER)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 srcSize;
    vec2 srcOffset;
    vec4 baseColor;
    float dark;
    float spread;
    vec4 optics; // thickness, dispersion, magnify, saturation
    vec4 finish; // tint, rim, grain, residual blur
};
layout(binding = 1) uniform sampler2D src;
#define glassSize itemSize
#define pad 0.0
#define radius (itemSize.y * 0.5)
#define bezel 8.0
#define thickness optics.x
#define dispersion optics.y
#define blurPx finish.w
#define tintMix finish.x
#define saturation optics.w
#define debug 0.0
#define rim finish.y
#define grain finish.z
#define magnify optics.z
#define shadowAmt 0.0
#define rimTint 0.0
#define ringW 0.0
#define flatInner 1.0
#define squircle 0.0
#elif defined(GLASS_BAR)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the Dock rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // width of the refracting rim, px
    float thickness;    // how far the rim shifts the backdrop, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // backdrop blur radius, px
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength (1 = original strength)
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = original, 0 = none) - appended last so older layouts stay compatible
    float rimTint;      // 0 = white rim (Dock / Menu Bar), 1 = rim + border take a brighter shade of the glass's own colour (widgets)
    float ringW;        // width in px of a thin border line along the very edge (0 = none)
    float flatInner;    // 1 = no inner edge shading (the darker inner rim); 0 = original. Appended last, unset = 0
};

layout(binding = 1) uniform sampler2D src;
#define squircle 0.0
#elif defined(GLASS_LOCK)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the Dock rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // width of the refracting rim, px
    float thickness;    // how far the rim shifts the backdrop, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // backdrop blur radius, px
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength (1 = original strength)
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = original, 0 = none) - appended last so older layouts stay compatible
    float squircle;
};

layout(binding = 1) uniform sampler2D src;
#define rimTint 0.0
#define ringW 0.0
#define flatInner 0.0
#elif defined(GLASS_MENU)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the Dock rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // width of the refracting rim, px
    float thickness;    // how far the rim shifts the backdrop, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // backdrop blur radius, px
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength (1 = original strength)
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = original, 0 = none) - appended last so older layouts stay compatible
    float rimTint;      // 0 = white rim (Dock / Menu Bar), 1 = rim + border take a brighter shade of the glass's own colour (widgets)
    float ringW;        // width in px of a thin border line along the very edge (0 = none)
    float flatInner;    // 1 = no inner edge shading (the darker inner rim); 0 = original. Appended last, unset = 0
    float bodyHeight;
    float tailHeight;
    float tailX;
    float tailWidth;
    float squircle;     // 0 = classic circular corners, 1 = superellipse (Lamé) continuous "squircle" corners. Unset = 0
};

layout(binding = 1) uniform sampler2D src;
#elif defined(GLASS_PORTAL)
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the Dock rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // width of the refracting rim, px
    float thickness;    // how far the rim shifts the backdrop, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // backdrop blur radius, px
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // specular edge highlight strength (1 = original strength)
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = original, 0 = none) - appended last so older layouts stay compatible
    float rimTint;      // 0 = white rim (Dock / Menu Bar), 1 = rim + border take a brighter shade of the glass's own colour (widgets)
    float ringW;        // width in px of a thin border line along the very edge (0 = none)
    float tailHeight;
    float pointerX;
    float tailAmount;
    float flatInner;    // 1 = no inner edge shading (the darker inner rim); 0 = original. Appended last, unset = 0
};

layout(binding = 1) uniform sampler2D src;
#define squircle 0.0
#else
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // whole shader item in px (glass + pad on every side)
    vec2 glassSize;     // the glass rectangle in px
    vec2 srcSize;       // backdrop texture size in px
    vec2 srcOffset;     // where the item's top-left sits inside the backdrop texture, px
    float pad;          // item padding around the glass (room for the drop shadow)
    float radius;       // corner radius, px
    float bezel;        // rim width scale, px (bezel * 0.09 -> rim_width)
    float thickness;    // refraction magnitude, px
    float dispersion;   // chromatic split (0 = none)
    float blurPx;       // nudges the backdrop taps' spread only (the real blur is the QML pre-pass)
    float tintMix;      // 0..1 amount of flat tint (the "translucency" slider)
    float saturation;   // backdrop saturation boost
    float dark;         // 0 = light mode, 1 = dark mode
    float debug;        // 1 = show the raw backdrop texture (magenta = texture is empty)
    float rim;          // rim light strength multiplier
    float grain;        // fine noise amplitude over the whole glass
    float magnify;      // vertical lens magnification of the whole slab
    float shadowAmt;    // drop-shadow strength (1 = upstream default, 0 = none)
    float rimTint;      // 0 = white rim, 1 = rim + border take a brighter shade of the glass's own colour
    float ringW;        // width in px of a thin border line along the very edge (0 = none); < 0 = corner light
    float flatInner;    // 1 = no inner AO band
    float squircle;     // 0 = circular corners, 1..: continuous superellipse corners (upstream corner_smoothing)
#ifdef DOCK_TOOLTIP
    float bodyHeight;
    float tailHeight;
    float tailX;
    float tailWidth;
    float pointerUp;
    vec4 backdropBounds; // local capture pixels: left, top, right, bottom
#endif
#ifdef SPOTLIGHT_GOOEY
    float pillWidth;
    float mergeRadius;
    vec4 button0;
    vec4 button1;
    vec4 button2;
    vec4 button3;
    vec4 button4;
#endif
#ifdef LUMA_GOOEY
    vec4 lumaInput;
    vec4 lumaBody;
    float lumaBodyRadius;
    float lumaMergeRadius;
#endif
};

layout(binding = 1) uniform sampler2D src;
#endif

vec4 glassTexture(vec2 uv) {
    vec4 color = texture(src, uv);
#ifdef GLASS_SLIDER
    color.rgb += baseColor.rgb * (1.0 - color.a);
#endif
    return color;
}

// Clear Liquid Glass for dark mode. Shared by the shell, menus, Launchpad and lock screen.
// Preserve backdrop colour, with a fine white rim and a positive-only soft glow.
float darkGlassBevel(float halfMin)
{
    // A wider bevel gives Dark more of the depth of the Light material.
    return clamp(halfMin * 0.28, 5.0, 14.0);
}

float darkGlassSaturation(float amount)
{
    return mix(1.0, amount, 0.70);
}

vec3 darkGlassBody(vec3 backdrop, float tint)
{
    // A subtle dark tint improves contrast for foreground text and icons.
    // Keep the backdrop visible and leave the lens depth and rim intact.
    float shade = 0.12 + clamp(tint, 0.0, 1.0) * 0.12;
    return mix(clamp(backdrop, 0.0, 1.0), vec3(0.055, 0.065, 0.085), shade);
}

vec2 darkGlassDisplacement(vec2 displacement, float halfMin)
{
    float reach = min(16.0, max(halfMin * 0.35, 1.5));
    return displacement * min(1.0, reach / max(length(displacement), 0.0001));
}

vec3 darkGlassLighting(vec3 base, float depth, vec2 outward, float rimAmount,
                       float borderWidth, float colourRim, float flatSurface)
{
    float facing = dot(outward, normalize(vec2(-0.65, -0.76)));
    float top = pow(max(facing, 0.0), 1.7);
    float bottom = pow(max(-facing, 0.0), 1.9);
    float distance = max(depth, 0.0);
    float hairline = exp(-distance / 0.62);
    float halo = exp(-distance / 3.2);
    float light = (hairline * (0.06 + 1.65 * top + 0.90 * bottom)
                 + halo * 0.065 * (0.2 + top + 0.65 * bottom)) * clamp(rimAmount, 0.0, 2.0);
    // Border-width settings never turn the highlight into a second broad rim.
    light += (1.0 - smoothstep(0.15, 0.95, distance))
           * min(abs(borderWidth), 1.0) * (0.035 + 0.06 * top + 0.04 * bottom);
    vec3 colour = mix(vec3(0.94, 0.98, 1.0), clamp(base * 0.35 + 0.65, 0.0, 1.0),
                      clamp(colourRim, 0.0, 1.0) * 0.15);
    // No inner AO, lower-edge darkening, or inset shadow, regardless of flatSurface.
    return base + (vec3(1.0) - base) * colour * clamp(light, 0.0, 0.75);
}


// ═══ DEEP GLASS TUNING ═══════════════════════════════════════════════════════
// ── depth ────────────────────────────────────────────────────────────────────
const float BAND_MIN          = 22.0;   // px: narrowest lens band (the old fixed band)
const float BAND_MAX          = 76.0;   // px: widest lens band (big surfaces)
const float BAND_FRACTION     = 0.34;   // band = halfMin * this, clamped to [BAND_MIN, BAND_MAX]
const float EDGE_LENS_FALLOFF = 1.75;   // lower = the bend reaches further into the glass
const float EDGE_LENS_REACH   = 180.0;  // hard px cap on the rim's sample shift
const float DEPTH_EXPONENT    = 0.90;   // how much a wider band scales the displacement (1 = fully)
const float DISPLACEMENT_LINK = 1.50;   // thickness -> displacement scale (upstream 1.15)
const float INTERIOR_BULGE    = 0.045;  // whole-interior magnification (0 = flat, 0.08 = strong)
const float CHROMA_GAIN       = 2.0;    // colour separation at the rim
const float CHROMA_MAX_PX     = 8.0;    // never split R/B further than this
const float LIGHT_MILK        = 0.48;   // light mode: luminous white veil with the backdrop still visible
const bool  DEEP_LENS_IN_DARK = true;   // false = keep the old shallow dark material
// ── border ───────────────────────────────────────────────────────────────────
const float RIM_BASE          = 0.34;   // line brightness all round (never fully dark)
const float RIM_KEY           = 0.85;   // extra brightness facing the key light (top left)
const float RIM_FILL          = 0.55;   // extra brightness facing the fill light (bottom right)
const float RIM_CORE_GAIN     = 1.00;   // the thin bright line
const float RIM_GLOW_GAIN     = 0.30;   // soft glow just inside the line
const float RIM_OUTER_GAIN    = 0.85;   // the half of the line that sits outside the edge
const float RIM_GLOW_MIN      = 4.0;    // px: inner glow radius range
const float RIM_GLOW_MAX      = 14.0;
const float PRISM_GAIN        = 0.60;   // prismatic fringe (pink / cyan / yellow) strength
const float SHEEN_TOP         = 0.10;   // soft light just under the top edge
const float GLOW_BR           = 0.16;   // cool glow along the bottom-right edge
const float DEPTH_SHADE       = 0.10;   // +-brightness across the bevel (lit side / far side)
// Screen-space light directions (y points down).
const vec2  L_KEY  = vec2(-0.623, -0.782);   // from the top left
const vec2  L_FILL = vec2( 0.623,  0.782);   // from the bottom right
const vec2  P_DIR1 = vec2( 0.750, -0.661);   // prismatic fringe: top right
const vec2  P_DIR2 = vec2(-0.707,  0.707);   // and faintly the bottom left

// ── other upstream constants ─────────────────────────────────────────────────
#define HIGHLIGHT_CHROMA_GAIN 1.25     // how much more than the backdrop a highlight is drawn

// PINNED upstream defaults (src/rendering/material.ts, schema defaults):
const float MAX_Z            = 88.0;  // dome height
const float PROFILE_SHAPE_N  = 3.6;   // dome shape
const float IOR              = 2.40;  // index of refraction (upstream default)
const float EDGE_SMOOTHING   = 0.5;   // feather width, px
const float RIM_DIRECTIONAL_POWER = 1.9;
const float LIGHT_ANGLE_DEG  = 90.0;  // light straight from the top
const float AO_INTENSITY     = 0.65;
const float AO_RADIUS        = 1.0;
const float SHADOW_RADIUS    = 50.0;  // capped to the pad room below
const float SHADOW_RGB_BASE  = 0.22;  // shadow_intensity upstream default

const float CONTRAST  = 1.08;  // slight punch around mid grey

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── shape (ported) ───────────────────────────────────────────────────────────
// Corner of a box with half-extents b and corner radius r as (radius, exponent)
// of a superellipse; the exponent makes the corner meet the sides with zero
// curvature so rim and refraction do not crease there.
vec2 cornerShape(vec2 b, float r, float smoothing)
{
    // Same Lamé contour as Common/CornerMath.js and Hyprland rounding_power.
    // Even a full-radius button becomes a squircle when smoothing is enabled.
    return vec2(clamp(r, 0.0, min(b.x, b.y)), 2.0 + 2.0 * clamp(smoothing, 0.0, 1.0));
}

// Superellipse norm (|x|^n + |y|^n)^(1/n) of q >= 0, scaled to stay in range.
float superLength(vec2 q, float n)
{
    float m = max(q.x, q.y);
    if (m <= 0.0) return 0.0;
    vec2 u = q / m;
    return m * pow(pow(u.x, n) + pow(u.y, n), 1.0 / n);
}

// Signed distance to a rounded rectangle whose corners are superellipses:
// negative inside, 0 on the edge, divided by its gradient's length so the rim,
// the bevel and the anti-aliasing keep the same width all round.
#if defined(GLASS_NOTCH)
float sdRoundRect(vec2 p, vec2 b, vec2 corner) { return bodyDistance(p + b); }
vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner) {
    const vec2 e = vec2(0.5, 0.0);
    vec2 g = vec2(sdRoundRect(p+e.xy,b,corner)-sdRoundRect(p-e.xy,b,corner),
                  sdRoundRect(p+e.yx,b,corner)-sdRoundRect(p-e.yx,b,corner));
    return length(g) > 0.0001 ? normalize(g) : vec2(0.0, 1.0);
}
#elif defined(GLASS_MENU)
float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Superellipse ("squircle" / continuous corner) rounded box: |dx|^n + |dy|^n = r^n in each corner.
// n == 2 reproduces the circular round box above exactly; larger n (≈4…5) flattens the corner into
// the Lamé curve macOS uses for its continuous corners, so the rounding flows out of the straight
// edges instead of meeting them at a hard tangent point.
float roundBoxN(vec2 q, vec2 hs, float r, float n)
{
    vec2 d = abs(q) - (hs - r);
    vec2 m = max(d, 0.0);
    float k = pow(pow(m.x, n) + pow(m.y, n), 1.0 / n);
    return k + min(max(d.x, d.y), 0.0) - r;
}

// the shape's corner exponent for a 0..1 "squircle" amount (0 = circle, 1 = strong squircle)
float cornerN(float sq)
{
    return 2.0 + 2.0 * clamp(sq, 0.0, 1.0);
}

float triangleDistance(vec2 p, vec2 a, vec2 b, vec2 c)
{
    vec2 e0 = b-a, e1 = c-b, e2 = a-c;
    vec2 v0 = p-a, v1 = p-b, v2 = p-c;
    vec2 pq0 = v0-e0*clamp(dot(v0,e0)/dot(e0,e0),0.0,1.0);
    vec2 pq1 = v1-e1*clamp(dot(v1,e1)/dot(e1,e1),0.0,1.0);
    vec2 pq2 = v2-e2*clamp(dot(v2,e2)/dot(e2,e2),0.0,1.0);
    float s = sign(e0.x*e2.y-e0.y*e2.x);
    vec2 d = min(min(vec2(dot(pq0,pq0),s*(v0.x*e0.y-v0.y*e0.x)),
                     vec2(dot(pq1,pq1),s*(v1.x*e1.y-v1.y*e1.x))),
                     vec2(dot(pq2,pq2),s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}
float bubbleDistance(vec2 p)
{
    // body = rounded rect sized (glassSize.x, bodyHeight); its corner radius
    // comes from the `radius` uniform (clamped) instead of the tooltip's capsule.
    vec2 bhs = vec2(glassSize.x, bodyHeight) * 0.5;
    float body = roundBoxN(p - bhs, bhs - vec2(0.5), min(radius, min(bhs.x, bhs.y)) - 0.5, cornerN(squircle));
    float tail = triangleDistance(p,vec2(tailX-tailWidth,bodyHeight-2.0),
        vec2(tailX+tailWidth,bodyHeight-2.0),vec2(tailX,bodyHeight+tailHeight-2.0))-0.8;
    float k = 3.0;
    float h = clamp(0.5+0.5*(tail-body)/k,0.0,1.0);
    return mix(tail,body,h)-k*h*(1.0-h);
}


float sdRoundRect(vec2 p, vec2 b, vec2 corner) { return bubbleDistance(p + b); }
vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner) {
    const vec2 e = vec2(0.5, 0.0);
    vec2 g = vec2(sdRoundRect(p+e.xy,b,corner)-sdRoundRect(p-e.xy,b,corner),
                  sdRoundRect(p+e.yx,b,corner)-sdRoundRect(p-e.yx,b,corner));
    return length(g) > 0.0001 ? normalize(g) : vec2(0.0, 1.0);
}
#elif defined(GLASS_PORTAL)
float roundBox(vec2 q, vec2 hs, float r)
{
    vec2 d = abs(q) - (hs - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Portal contour adapter; the File/Edit optical material below is unchanged.
void tailEdge(vec2 p, vec2 a, vec2 b, inout float distance2, inout bool inside) {
    vec2 e=b-a, v=p-a;
    vec2 nearest=v-e*clamp(dot(v,e)/max(dot(e,e),0.0001),0.0,1.0);
    distance2=min(distance2,dot(nearest,nearest));
    if ((a.y>p.y)!=(b.y>p.y)) {
        float crossX=a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y);
        if(p.x<crossX)inside=!inside;
    }
}
vec2 tailCubic(vec2 a,vec2 b,vec2 c,vec2 d,float t) {
    float u=1.0-t;
    return u*u*u*a+3.0*u*u*t*b+3.0*u*t*t*c+t*t*t*d;
}
float portalDistance(vec2 q,vec2 hs,float r) {
    if(tailHeight<=0.001)return roundBox(q,hs,r);
    vec2 p=q+hs;
    float body=roundBox(q-vec2(0,tailHeight*0.5),hs-vec2(0,tailHeight*0.5),r);
    // Most pixels only need the original rounded-body distance.
    if(abs(p.x-pointerX)>12.0+max(bezel*1.45,32.0) || p.y>tailHeight+max(bezel*1.45,32.0))return body;
    float tip=mix(tailHeight,0.5,clamp(tailAmount,0.0,1.0));
    vec2 a=vec2(pointerX-12.0,tailHeight), b=vec2(pointerX-6.0,tailHeight);
    vec2 c=vec2(pointerX-4.0,tip), d=vec2(pointerX,tip), previous=a;
    float distance2=1e12;bool inside=false;
    for(int i=1;i<=8;++i){vec2 next=tailCubic(a,b,c,d,float(i)/8.0);tailEdge(p,previous,next,distance2,inside);previous=next;}
    a=d;b=vec2(pointerX+4.0,tip);c=vec2(pointerX+6.0,tailHeight);d=vec2(pointerX+12.0,tailHeight);
    for(int i=1;i<=8;++i){vec2 next=tailCubic(a,b,c,d,float(i)/8.0);tailEdge(p,previous,next,distance2,inside);previous=next;}
    // Extend the cap into the body so the union has no seam at the tail base.
    vec2 right=vec2(pointerX+12.0,tailHeight+26.0),left=vec2(pointerX-12.0,tailHeight+26.0);
    tailEdge(p,previous,right,distance2,inside);tailEdge(p,right,left,distance2,inside);tailEdge(p,left,vec2(pointerX-12.0,tailHeight),distance2,inside);
    return min(body,sqrt(distance2)*(inside?-1.0:1.0));
}


float sdRoundRect(vec2 p, vec2 b, vec2 corner) { return portalDistance(p, b, corner.x); }
vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner) {
    const vec2 e = vec2(0.5, 0.0);
    vec2 g = vec2(sdRoundRect(p+e.xy,b,corner)-sdRoundRect(p-e.xy,b,corner),
                  sdRoundRect(p+e.yx,b,corner)-sdRoundRect(p-e.yx,b,corner));
    return length(g) > 0.0001 ? normalize(g) : vec2(0.0, 1.0);
}
#elif defined(DOCK_TOOLTIP)
// Capsule + smooth tail; optics come from liquidglass.frag, as in System Settings.
float triangleDistance(vec2 p, vec2 a, vec2 b, vec2 c)
{
    vec2 e0 = b-a, e1 = c-b, e2 = a-c;
    vec2 v0 = p-a, v1 = p-b, v2 = p-c;
    vec2 pq0 = v0-e0*clamp(dot(v0,e0)/dot(e0,e0),0.0,1.0);
    vec2 pq1 = v1-e1*clamp(dot(v1,e1)/dot(e1,e1),0.0,1.0);
    vec2 pq2 = v2-e2*clamp(dot(v2,e2)/dot(e2,e2),0.0,1.0);
    float s = sign(e0.x*e2.y-e0.y*e2.x);
    vec2 d = min(min(vec2(dot(pq0,pq0),s*(v0.x*e0.y-v0.y*e0.x)),
                     vec2(dot(pq1,pq1),s*(v1.x*e1.y-v1.y*e1.x))),
                     vec2(dot(pq2,pq2),s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}
float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    // The shared material uses centred coordinates; the tooltip silhouette
    // uses its top-left. Reflect only the shape, never the backdrop image.
    p += b;
    if (pointerUp > 0.5) p.y = glassSize.y - p.y;
    vec2 hs = vec2(glassSize.x, bodyHeight) * 0.5;
    vec2 q = abs(p - hs) - (hs - vec2(bodyHeight * 0.5 - 0.5));
    float body = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - (bodyHeight * 0.5 - 0.5);
    float tail = triangleDistance(p, vec2(tailX-tailWidth,bodyHeight-2.0),
        vec2(tailX+tailWidth,bodyHeight-2.0),vec2(tailX,bodyHeight+tailHeight-2.0))-0.8;
    float k = 3.0;
    float h = clamp(0.5+0.5*(tail-body)/k,0.0,1.0);
    return mix(tail,body,h)-k*h*(1.0-h);
}
vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    const vec2 e = vec2(0.5, 0.0);
    return normalize(vec2(sdRoundRect(p+e.xy,b,corner)-sdRoundRect(p-e.xy,b,corner),
        sdRoundRect(p+e.yx,b,corner)-sdRoundRect(p-e.yx,b,corner))+vec2(1e-6));
}

#elif defined(SPOTLIGHT_GOOEY)
// Same glass material, with a single animated capsule/metaball silhouette.
// Build: qsb --qt6 -D SPOTLIGHT_GOOEY -o spotlightgooey.frag.qsb liquidglass.frag
// Included only in the SPOTLIGHT_GOOEY variant of liquidglass.frag.
// Every distance/normal lookup sees the union, so internal seams disappear
// and the connecting necks refract the same backdrop as the search pill.
float gooeyUnion(float a, float b)
{
    float k = max(mergeRadius, 0.001);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float gooeyEllipse(vec2 p, vec4 shape)
{
    vec2 q = abs((p - shape.xy) / shape.zw);
    float n = 2.0; // Circular buttons, including while they stretch during opening.
    float extent = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
    return (extent - 1.0) * min(shape.z, shape.w);
}

float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    vec2 at = p + b;
    float r = min(b.y, pillWidth * 0.5);
    vec2 q = abs(at - vec2(pillWidth * 0.5, b.y)) - vec2(pillWidth * 0.5, b.y) + vec2(r);
    vec2 positive = max(q, 0.0);
    float n = 2.0 + 2.0 * clamp(squircle, 0.0, 1.0);
    float d = pow(pow(positive.x, n) + pow(positive.y, n), 1.0 / n) + min(max(q.x, q.y), 0.0) - r;
    d = gooeyUnion(d, gooeyEllipse(at, button0));
    d = gooeyUnion(d, gooeyEllipse(at, button1));
    d = gooeyUnion(d, gooeyEllipse(at, button2));
    d = gooeyUnion(d, gooeyEllipse(at, button3));
    return gooeyUnion(d, gooeyEllipse(at, button4));
}

vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    const vec2 e = vec2(0.4, 0.0);
    vec2 gradient = vec2(
        sdRoundRect(p + e.xy, b, corner) - sdRoundRect(p - e.xy, b, corner),
        sdRoundRect(p + e.yx, b, corner) - sdRoundRect(p - e.yx, b, corner));
    return gradient / max(length(gradient), 0.0001);
}

#elif defined(LUMA_GOOEY)
// Luma's input pill and expanding answer card share one liquid silhouette.
// A smooth minimum creates the neck; its gradient drives the glass refraction.
float lumaRoundedBox(vec2 p, vec4 box, float radiusPx)
{
    float r = min(radiusPx, min(box.z, box.w));
    vec2 q = abs(p - box.xy) - box.zw + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    vec2 at = p + b;
    float a = lumaRoundedBox(at, lumaInput, 22.0);
    float d = lumaRoundedBox(at, lumaBody, lumaBodyRadius);
    float k = max(lumaMergeRadius, 0.001);
    float h = max(k - abs(a - d), 0.0) / k;
    return min(a, d) - h * h * k * 0.25;
}

vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    const vec2 e = vec2(0.4, 0.0);
    vec2 gradient = vec2(
        sdRoundRect(p + e.xy, b, corner) - sdRoundRect(p - e.xy, b, corner),
        sdRoundRect(p + e.yx, b, corner) - sdRoundRect(p - e.yx, b, corner));
    return gradient / max(length(gradient), 0.0001);
}

#else
float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    float r = corner.x;
    float n = corner.y;
    vec2 d = abs(p) - b + vec2(r);
    vec2 q = max(d, 0.0);
    float len = superLength(q, n);
    if (len <= 0.0)
        return max(d.x, d.y) - r;
    vec2 g = pow(q / len, vec2(n - 1.0));
    float gradLen = mix(1.0, length(g), clamp(len / max(r, 1.0e-3), 0.0, 1.0));
    return (len - r) / max(gradLen, 0.5);
}

// Unit gradient of sdRoundRect() at p in closed form: along a straight side
// that side's axis, in a corner the superellipse's normal.
vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    vec2 q = abs(p) - b + vec2(corner.x);
    if (max(q.x, q.y) < 0.0)
        return (q.x > q.y) ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
    vec2 u = max(q, 0.0) / max(max(q.x, q.y), 1.0e-6);
    return sign(p) * normalize(pow(u, vec2(corner.y - 1.0)) + vec2(1e-6));
}
#endif

// ── dome / lens (ported, now with a size-dependent band) ─────────────────────
// Width of the refractive bevel: proportional to the glass, never below the old
// fixed 22 px (unless the glass itself is smaller) and never above BAND_MAX.
float lensBandFor(float halfMin)
{
    float lo = max(min(BAND_MIN, halfMin), 1.0);
    float hi = max(lo, BAND_MAX);
    return clamp(halfMin * BAND_FRACTION, lo, hi);
}
float lensScaleFor(float band)
{
    return band / max(BAND_MIN, 1.0);
}

// Depth into the bevel, 0 at the edge to 1 at its inner end.
float normalizedDepth(float d, float band)
{
    return clamp(max(-d, 0.0) / max(band, 1.0), 0.0, 1.0);
}

// Superellipse profile: h = H * (1 - (1 - t)^n)^(1/n), t: edge = 0, center = 1.
float profileHeight(float t, float zScale)
{
    float n = max(PROFILE_SHAPE_N, 1.01);
    float inner = max(1.0 - pow(clamp(1.0 - t, 0.0, 1.0), n), 0.0);
    return pow(inner, 1.0 / n) * zScale;
}

// Surface height at p; the dome stops rising past `band`, and fades out over
// +-edge_smoothing px across the edge instead of stepping (a step would spike
// the finite difference and show as jagged refraction).
float getHeight(vec2 p, vec2 b, vec2 corner, float band, float zScale)
{
    float d = sdRoundRect(p, b, corner);
    float smoothZone = max(EDGE_SMOOTHING, 1.0);
    if (d > smoothZone) return 0.0;
    float h = profileHeight(normalizedDepth(d, band), zScale);
    return h * (1.0 - smoothstep(-smoothZone, smoothZone, d));
}

float gradientStep(vec2 resolution)
{
    float minRes = max(min(resolution.x, resolution.y), 1.0);
    return clamp(minRes / 560.0, 0.45, 1.20);
}

// Height gradient: grad(H) = H'(d) * grad(d); grad(d) is closed form, H'(d)
// one central difference along it.
vec2 heightGradient(vec2 p, vec2 b, vec2 corner, float band, float zScale, vec2 resolution)
{
    vec2 dir = sdRoundRectDir(p, b, corner);
    float e = gradientStep(resolution);
    float hOut = getHeight(p + dir * e, b, corner, band, zScale);
    float hIn  = getHeight(p - dir * e, b, corner, band, zScale);
    return dir * ((hOut - hIn) / (2.0 * e));
}

// ── backdrop sampling (ported, px-space) ─────────────────────────────────────
// Averages the blurred backdrop over this pixel's coverage in the source. The
// refraction compresses tens of source pixels into a few screen pixels near
// the edge, and point sampling that aliases; `ext` is half that footprint in
// px along the compression (vec2(0) keeps the plain four RGSS taps).
vec2 backdropUv(vec2 pixel)
{
#ifdef DOCK_TOOLTIP
    // Keep the lens on the same visible surface when the tooltip is over a
    // window. A deep edge bend must not pull wallpaper through that window.
    pixel = clamp(pixel, backdropBounds.xy, backdropBounds.zw);
#endif
#ifdef GLASS_SLIDER
    pixel = srcOffset + itemSize * 0.5
          + (pixel - srcOffset - itemSize * 0.5) * max(spread, 0.01);
#endif
    return clamp(pixel / max(srcSize, vec2(1.0)), vec2(0.001), vec2(0.999));
}

vec3 sampleBackdropPx(vec2 samplePx, vec2 ext, vec2 spread)
{
    vec2 o1 = vec2( 0.375, -0.125) * spread;
    vec2 o2 = vec2( 0.125,  0.375) * spread;
    vec2 o3 = vec2(-0.375,  0.125) * spread;
    vec2 o4 = vec2(-0.125, -0.375) * spread;
    vec3 sum =
        glassTexture( backdropUv(samplePx + o1 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx + o2 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx + o3 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx + o4 + srcOffset)).rgb;
    if (dot(ext, ext) <= 0.0)
        return sum * 0.25;
    sum +=
        glassTexture( backdropUv(samplePx + ext * 0.90 + o1 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx + ext * 0.55 + o2 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx + ext * 0.22 + o3 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx - ext * 0.22 + o4 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx - ext * 0.55 + o1 + srcOffset)).rgb +
        glassTexture( backdropUv(samplePx - ext * 0.90 + o2 + srcOffset)).rgb;
    return sum * 0.1;
}

// +-0.5/255 of noise before the 8-bit output; a shallow blurred gradient would
// otherwise band.
float ditherLSB(vec2 p)
{
    return (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
}

// erfc(x) for x >= 0 (Abramowitz and Stegun 7.1.27, error below 5e-4).
float erfcPositive(float x)
{
    float p = 1.0 + x * (0.278393 + x * (0.230389 + x * (0.000972 + x * 0.078108)));
    float p2 = p * p;
    return 1.0 / (p2 * p2);
}

// ── colour (ported) ──────────────────────────────────────────────────────────
// sRGB-encoded colour to Oklab, a 2.2 gamma standing in for the sRGB curve.
vec3 toOklab(vec3 c)
{
    vec3 lin = pow(max(c, vec3(0.0)), vec3(2.2));
    vec3 lms = vec3(
        dot(lin, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
        dot(lin, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
        dot(lin, vec3(0.0883024619, 0.2817188376, 0.6299787005)));
    lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
    return vec3(
        dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
        dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
        dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660)));
}

vec3 oklabToLinear(vec3 lab)
{
    vec3 lms = vec3(
        dot(lab, vec3(1.0, 0.3963377774, 0.2158037573)),
        dot(lab, vec3(1.0, -0.1055613458, -0.0638541728)),
        dot(lab, vec3(1.0, -0.0894841775, -1.2914855480)));
    lms = lms * lms * lms;
    return vec3(
        dot(lms, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
        dot(lms, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
        dot(lms, vec3(-0.0041960863, -0.7034186147, 1.7076147010)));
}

float gamutRoom(float from, float delta)
{
    if (delta > 1.0e-6) return (1.0 - from) / delta;
    if (delta < -1.0e-6) return -from / delta;
    return 1.0;
}

// `lit` (base screen-blended with white) with the backdrop's hue put back, so
// the highlights light up in the colour of what is behind the glass instead of
// washing out to grey. Pulled towards the plain colour along a line of nearly
// constant luminance when out of gamut.
vec3 backdropHighlight(vec3 base, vec3 lit, float light)
{
    vec3 litLab = toOklab(lit);
    vec2 baseChroma = toOklab(base).yz * HIGHLIGHT_CHROMA_GAIN;
    litLab.yz = mix(litLab.yz, baseChroma, clamp(light * 4.0, 0.0, 1.0));

    vec3 from = pow(max(lit, vec3(0.0)), vec3(2.2));
    vec3 delta = oklabToLinear(litLab) - from;
    float t = min(min(gamutRoom(from.r, delta.r), gamutRoom(from.g, delta.g)),
                  min(gamutRoom(from.b, delta.b), 1.0));
    return pow(clamp(from + delta * max(t, 0.0), 0.0, 1.0), vec3(1.0 / 2.2));
}

// Brightness, contrast around mid grey, and saturation with Rec.601 luma.
vec3 applySCB(vec3 color, float c, float s)
{
    color = mix(vec3(0.5), color, max(c, 0.0));
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    return max(mix(vec3(luma), color, max(s, 0.0)), vec3(0.0));
}

// Screen blend of `add` over `base` (cannot blow out a bright backdrop).
vec3 screenBlend(vec3 base, vec3 add)
{
    return vec3(1.0) - (vec3(1.0) - base) * (vec3(1.0) - clamp(add, 0.0, 1.0));
}

// Prismatic fringe colour: t = 0 at the edge, 1 deeper inside.
// pink -> cyan -> warm yellow, like the light split along a thick glass edge.
vec3 prismColor(float t)
{
    vec3 a = vec3(1.00, 0.42, 0.86);
    vec3 b = vec3(0.30, 0.88, 1.00);
    vec3 c = vec3(1.00, 0.93, 0.55);
    return (t < 0.5) ? mix(a, b, t * 2.0) : mix(b, c, (t - 0.5) * 2.0);
}

void shadeGlass()
{
    vec2 p  = qt_TexCoord0 * itemSize;
    vec2 hs = glassSize * 0.5;
    vec2 centerPx = vec2(pad) + hs;
    vec2 q  = p - centerPx;
    // local_pos relative to the glass centre (upstream `local_pos`)
    vec2 localPos = q;
    bool shallowDark = (dark > 0.5) && !DEEP_LENS_IN_DARK;
    float materialMagnify = shallowDark ? 0.0 : magnify;
    float bulge = shallowDark ? 0.0 : INTERIOR_BULGE;

    float cornerRadius = min(radius, min(hs.x, hs.y));
    vec2 corner = cornerShape(hs, cornerRadius, squircle);
    float d = sdRoundRect(localPos, hs, corner);

#ifdef FROSTED_MENU
    // Menu vibrancy is a flat, pre-blurred backdrop, never a lens. Keep this
    // separate from the optical profile used by Control Center and Spotlight.
    float coverage = 1.0 - smoothstep(-0.75, 0.75, d);
    vec4 backdrop = glassTexture(backdropUv(p + srcOffset));
    vec3 base = backdrop.rgb / max(backdrop.a, 0.001);
    float luma = dot(base, vec3(0.299, 0.587, 0.114));
    base = mix(vec3(luma), base, 0.85);
    vec3 tint = mix(vec3(0.98), vec3(0.105, 0.105, 0.115), dark);
    base = mix(base, tint, mix(0.68, 0.76, dark));
    float shadowDistance = sdRoundRect(localPos - vec2(0.0, 3.0), hs, corner);
    float shadow = exp(-max(shadowDistance, 0.0) / 4.0) * 0.22
        * (1.0 - coverage) * shadowAmt;
    float alpha = coverage + shadow;
    fragColor = vec4(base * coverage, alpha) * qt_Opacity;
    return;
#endif

    // lens band: proportional to the glass (deep), or the old dark bevel
    float lensBand  = shallowDark ? darkGlassBevel(min(hs.x, hs.y)) : lensBandFor(min(hs.x, hs.y));
    float lensScale = shallowDark ? 1.0 : lensScaleFor(lensBand);

    // ── masks ──
    float edgeFeather = max(EDGE_SMOOTHING, 0.75);
    float outsideTransition = smoothstep(-edgeFeather, edgeFeather, d);
    float insideMask  = 1.0 - outsideTransition;
    float outsideMask = outsideTransition;


    if (debug > 0.5) {
        vec4 s = glassTexture( backdropUv(p + srcOffset));
        fragColor = (s.a < 0.01 ? vec4(1.0, 0.0, 1.0, 1.0) : vec4(s.rgb / max(s.a, 1e-3), 1.0)) * insideMask * qt_Opacity;
        return;
    }

    // Drop shadow room: the pad is the only room the actor has outside the
    // glass, so upstream's 50px shadow radius is capped to ~95% of it.
    float shadowReach = max(min(SHADOW_RADIUS, max(pad, 0.0) * 0.95), 5.0);
    if (shallowDark) shadowReach = max(shadowReach * 0.55, 3.0);

    // Beyond the shadow's reach nothing is drawn.
    if (d >= max(shadowReach, edgeFeather)) {
        fragColor = vec4(0.0);
        return;
    }

    // Light-mode "milk": the bright white pill look — extra white tinting on
    // top of the translucency slider, so the glass reads bright and milky while
    // the rim keeps refracting (dark mode: 0 = unchanged).
    float lightMilk = (1.0 - clamp(dark, 0.0, 1.0)) * LIGHT_MILK;

    // Deep inside, the dome is flat: telescopes to tinted backdrop + dither.
    // Only taken while the vertical lens pre-warp is idle (it shifts samples
    // inside everywhere). The interior bulge is applied here too.
    float interiorThreshold = max(lensBand + gradientStep(glassSize) + max(EDGE_SMOOTHING, 1.0),
                                  max(max(AO_RADIUS, 3.0), abs(ringW) + 1.0));
    if (materialMagnify < 0.003 && -d >= interiorThreshold) {
        vec2 bulgedI = centerPx + (p - centerPx) * (1.0 - bulge);
        vec2 spreadI = vec2(0.75 * (1.0 + blurPx * 0.03));
        vec3 base = sampleBackdropPx(bulgedI, vec2(0.0), spreadI);
        base = applySCB(base, shallowDark ? 1.02 : CONTRAST,
                       shallowDark ? darkGlassSaturation(saturation) : saturation);
        vec3 tintC = mix(vec3(1.0), vec3(0.09, 0.09, 0.10), clamp(dark, 0.0, 1.0));
        base = shallowDark ? darkGlassBody(base, tintMix)
                           : mix(base, tintC, clamp(tintMix + lightMilk, 0.0, 1.0));
        float noise = shallowDark
            ? (hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0) * grain * 0.2
            : hash12(p) * grain;
        base = max(base + ditherLSB(p) + noise, vec3(0.0));
        fragColor = vec4(base, 1.0) * qt_Opacity;
        return;
    }

    // ── drop shadow (erfc profile, directional, cool tint) ──
    float lightAngleRad = radians(LIGHT_ANGLE_DEG);
    vec2  lightDir2D = vec2(cos(lightAngleRad), -sin(lightAngleRad)); // up for the shadow formula
    vec2  shadowDir  = -lightDir2D;                                   // shadows fall down

    vec2 outwardDir = (length(localPos) > 1.0e-4) ? normalize(localPos) : vec2(0.0, 1.0);
    float lightAlignment = max(dot(outwardDir, shadowDir), 0.0);
    float dirRadius    = 0.85 + lightAlignment * 0.15;
    float dirIntensity = 0.85 + lightAlignment * 0.15;

    float radiusEnable       = smoothstep(0.0, 0.75, shadowAmt);
    float effectiveRadius    = max(min(shadowReach * dirRadius, max(shadowReach, 5.0)), 0.001);
    float effectiveIntensity = SHADOW_RGB_BASE * dirIntensity * radiusEnable;
    if (shallowDark) effectiveIntensity *= 0.45;

    float shadow_t = clamp(d / effectiveRadius, 0.0, 1.0);
    float edgeShadow = 0.18 * erfcPositive(shadow_t * 2.619) +
                       1.17 * erfcPositive(shadow_t * 0.895);
    float shadowWindow = 1.0 - shadow_t * shadow_t;
    shadowWindow = shadowWindow * shadowWindow * shadowWindow;
    float shadowAlpha = clamp(edgeShadow * shadowWindow * outsideMask * effectiveIntensity, 0.0, 1.0);
    if (shadowAlpha > 0.0)
        shadowAlpha = max(shadowAlpha + ditherLSB(p + vec2(37.0, 17.0)), 0.0);

    // ── glass surface ──
    vec2 gradH  = heightGradient(localPos, hs, corner, lensBand,
                                shallowDark ? 14.0 : MAX_Z * lensScale, glassSize);
    vec3 normal = normalize(vec3(-gradH.x, -gradH.y, 1.0));

    // refraction (only inside)
    vec2 dispPx = vec2(0.0);
    if (d < 0.0) {
        vec3 viewDirIn = vec3(0.0, 0.0, -1.0);
        float eta = 1.0 / (shallowDark ? 1.45 : max(IOR, 1.001));
        vec3 ray = refract(viewDirIn, normal, eta);
        if (length(ray) > 0.0001) {
            float safe_z = max(-ray.z, 0.15);
            dispPx = ray.xy / safe_z * (thickness * DISPLACEMENT_LINK);
            if (shallowDark) dispPx *= 0.42;
        }
    }

    // lens shaping: the displacement bends one way across the whole bevel,
    // and a wider bevel bends proportionally more
    float depthPx = max(-d, 0.0);
    float edgeT   = clamp(1.0 - depthPx / lensBand, 0.0, 1.0);
    float lensShape = pow(edgeT, EDGE_LENS_FALLOFF);
    dispPx *= lensShape * pow(max(lensScale, 1.0e-3), DEPTH_EXPONENT);
    if (shallowDark) dispPx = darkGlassDisplacement(dispPx, min(hs.x, hs.y));

    float dispLenPx = length(dispPx);
    if (dispLenPx > 1.0e-4) {
        float capPx = min(EDGE_LENS_REACH, 0.5 * max(min(itemSize.x, itemSize.y), 1.0));
        if (dispLenPx > capPx) dispPx *= capPx / dispLenPx;
        dispLenPx = min(dispLenPx, capPx);
    }

    // analytic footprint along the compression
    float shapeRate = EDGE_LENS_FALLOFF * pow(edgeT, EDGE_LENS_FALLOFF - 1.0) / lensBand;
    float footprintPx = 2.0 * dispLenPx * (shapeRate + 1.0 / lensBand);
    vec2 dispDirPx = dispPx / max(dispLenPx, 1.0e-4);
    vec2 footprintExt = (footprintPx > 2.0 && dispLenPx > 0.0)
        ? dispDirPx * (min(footprintPx, 96.0) * 0.5) : vec2(0.0);

    // RGSS spread: wider near the edge, nudged by the residual-blur knob
    float edgeProximity = 1.0 - smoothstep(0.0, edgeFeather * 4.0, -d);
    vec2 spread = vec2(mix(0.75, 2.5, edgeProximity) * (1.0 + blurPx * 0.03));

    // pre-warp of the sample position: the whole interior is magnified a little
    // (INTERIOR_BULGE, like a thick lens) and, for the dock, the old vertical
    // lens pre-warp (`magnify`) is kept on top.
    float yScale = max(1.0 - bulge - materialMagnify * 1.5, 0.2);
    vec2 warped = centerPx + (p - centerPx) * vec2(1.0 - bulge, yScale);

    // chromatic dispersion, R out / B in, as a fraction of the displacement
    vec2 chromaVec = dispPx * clamp(dispersion, 0.0, 1.0) * CHROMA_GAIN;
    float chromaLen = length(chromaVec);
    if (chromaLen > CHROMA_MAX_PX) chromaVec *= CHROMA_MAX_PX / chromaLen;
    if (shallowDark) chromaVec *= 0.25;
    bool chromaActive = dot(chromaVec, chromaVec) > 1.0e-4;

    vec3 refractedRgb;
    if (chromaActive) {
        refractedRgb = vec3(
            sampleBackdropPx(warped + dispPx - chromaVec, footprintExt, spread).r,
            sampleBackdropPx(warped + dispPx,             footprintExt, spread).g,
            sampleBackdropPx(warped + dispPx + chromaVec, footprintExt, spread).b);
    } else {
        refractedRgb = sampleBackdropPx(warped + dispPx, footprintExt, spread);
    }

    vec3 baseColor = applySCB(refractedRgb, shallowDark ? 1.02 : CONTRAST,
                             shallowDark ? darkGlassSaturation(saturation) : saturation);
    if (shallowDark) {
        vec3 clean = darkGlassBody(baseColor, tintMix);
        clean = darkGlassLighting(clean, depthPx, sdRoundRectDir(localPos, hs, corner),
                                  rim, ringW, rimTint, flatInner);
        float noise = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
        clean = clamp(clean + noise * grain * 0.2, 0.0, 1.0);
        float shadowContribution = shadowAlpha * (1.0 - insideMask);
        float alpha = insideMask + shadowContribution;
        vec3 rgb = clean * insideMask + vec3(0.03, 0.04, 0.08) * shadowContribution;
        fragColor = vec4(max(rgb + ditherLSB(p) * alpha, vec3(0.0)), alpha) * qt_Opacity;
        return;
    }
    vec3 tintC = mix(vec3(1.0), vec3(0.09, 0.09, 0.10), clamp(dark, 0.0, 1.0));
    baseColor = mix(baseColor, tintC, clamp(tintMix + lightMilk, 0.0, 1.0));

    // Every contour uses the Dock's fine inset stroke and diagonal specular lights.
    // The silhouette normal keeps the highlights continuous around corners;
    // position makes them strongest at top-left and bottom-right, fading
    // along the long edges instead of outlining the whole dock in white.
    vec2 dockNormal = sdRoundRectDir(localPos, hs, corner);
    float along = clamp(localPos.x / max(hs.x, 1.0), -1.0, 1.0);
    float keyPosition = 1.0 - smoothstep(-0.70, 0.65, along);
    float fillPosition = smoothstep(-0.65, 0.70, along);
    float keyLight = pow(max(dot(dockNormal, L_KEY), 0.0), 1.65)
                   * mix(0.18, 1.0, keyPosition);
    float fillLight = pow(max(dot(dockNormal, L_FILL), 0.0), 1.65)
                    * mix(0.18, 1.0, fillPosition);
    float specular = clamp(keyLight + fillLight * 0.94, 0.0, 1.0);
    float lightStrength = clamp(rim / 0.55, 0.0, 1.5);

    float borderAA = max(fwidth(d) * 0.5, 0.001);
    float borderMask = smoothstep(-0.50 - borderAA, -0.50 + borderAA, d);
    // Preserve the glass colour in a half-pixel highlight instead of a white outline.
    vec3 reflectionColor = mix(vec3(1.0, 0.98, 0.96), vec3(0.90, 0.96, 1.0), fillLight);
    vec3 borderColor = mix(baseColor, reflectionColor, 0.48);
    float borderOpacity = clamp((0.035 + specular * 0.88) * lightStrength, 0.0, 0.72);
    // Tight reflection inside the glass; no light is added outside the shape.
    float reflection = exp(-depthPx / 1.1) * specular * 0.018 * lightStrength;
    vec3 dockColor = screenBlend(baseColor, borderColor * reflection);
    dockColor = mix(dockColor, borderColor, borderMask * borderOpacity);
    float dockNoise = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    dockColor = clamp(dockColor + dockNoise * grain + ditherLSB(p), 0.0, 1.0);
    fragColor = vec4(dockColor * insideMask, insideMask) * qt_Opacity;
    return;
}

void main() {
#ifdef GLASS_NOTCH
    float alpha = shape(qt_TexCoord0);
    if (alpha < 0.001) { fragColor = vec4(0.0); return; }
    float seam = ubuf.wingSize > 0.0 ? smoothstep(0.03, 0.22, qt_TexCoord0.y) : 1.0;
    glassOpticalStrength = ubuf.strength * seam;
    glassTintAmount = mix(1.0, ubuf.finish.x, ubuf.strength);
    shadeGlass();
    // The Canvas mask owns attached shoulders and every intermediate frame.
    vec3 color = fragColor.a > 0.001 ? fragColor.rgb / fragColor.a : vec3(0.018, 0.021, 0.023);
    alpha *= qt_Opacity;
    fragColor = vec4(color * alpha, alpha);
#else
    shadeGlass();
#endif
}
#endif
