#version 440
#extension GL_GOOGLE_include_directive : require
// Liquid Glass — PORT of ryohsuke1231/liquid-glass (GNOME Shell) glass.frag
// onto MacShell's QML/Quickshell uniform set.
//
// ═══ DEEP GLASS REDESIGN (macOS Tahoe look) ══════════════════════════════════
// Same uniform buffer and same function names as before, so no QML changes are
// needed. What changed compared with the previous version:
//
//   DEPTH
//   * The lens band is no longer a fixed 22 px. It grows with the glass:
//     band = halfMin * BAND_FRACTION, clamped to [BAND_MIN, BAND_MAX]. Big
//     surfaces get a wide, deep bevel where the backdrop is visibly bent and
//     dragged along the edge (small surfaces stay at 22 px like before).
//   * The bend now reaches further into the glass (EDGE_LENS_FALLOFF 2.4 -> 1.75),
//     refraction is stronger (DISPLACEMENT_LINK 1.15 -> 1.35) and the cap on the
//     rim's sample shift is higher (96 -> 180 px).
//   * A gentle INTERIOR_BULGE magnifies the whole interior like a thick lens.
//   * Light mode is clearer: the extra white veil dropped from 0.22 to LIGHT_MILK (0.10).
//
//   BORDER
//   * The rim is now a THIN, crisp, bright line with a soft inner glow and a
//     faint outer halo, lit by a key light from the top left and a weaker fill
//     light from the bottom right (and never fully dark all round).
//   * A prismatic fringe (pink -> cyan -> warm yellow) sits just inside the edge
//     on the top right, driven by the `dispersion` uniform.
//   * Soft inner sheen under the top edge and a cool glow at the bottom right.
//
//   Dark mode now uses the same deep material. To get the old shallow dark glass
//   back, set DEEP_LENS_IN_DARK to false below.
//
// Every number that shapes the look is in the "DEEP GLASS TUNING" block.
//
// Build:  qsb --qt6 -o liquidglass.frag.qsb liquidglass.frag
// (MacBar.qml / MacDock.qml / MacWidgets.qml re-run qsb automatically on start
//  and cache the result; this sidecar .qsb is only the qsb-less fallback.)
//
// Old shader: https:// <local>   New base: https://github.com/ryohsuke1231/liquid-glass
// (MIT). What was ported, unchanged where possible:
//   * continuous "squircle" corners through a superellipse SDF whose distance
//     is divided by its gradient's length (rim/bevel/AA stay the same width all
//     round), corner exponent from cornerShape()
//   * superellipse dome profile h = H*(1-(1-t)^n)^(1/n), n = profile_shape_n 3.6
//   * surface normal from the height field's gradient taken along the SDF's
//     own direction (closed form sdRoundRectDir)
//   * refraction: refract((0,0,-1), n, 1/ior), ior 2.40,
//     displacement(px) = ray.xy/-ray.z * displacement_link, weighted by
//     (1 - depth/bevel)^EDGE_LENS_FALLOFF
//   * backdrop sampled on a rotated 4-tap grid (RGSS), spread wider near the
//     edge, plus 6 footprint taps along the refraction's compression
//   * chromatic dispersion as a fraction of the displacement (R out / B in)
//   * highlights keep the backdrop's hue via Oklab chroma transfer
//   * inner AO band, drop shadow from erfc(), dither, applySCB
//
// Upstream's multi-pass blur is NOT ported: MacShell feeds the shader a
// pre-blurred backdrop (Qt MultiEffect + the Appearance blur slider).
//
// Uniform semantics are unchanged:
//   thickness   -> displacement magnitude (the "Liquid" strength slider)
//   bezel       -> rim width scale (the thin line is clamp(bezel * 0.09, 1.6, 3) px)
//   dispersion  -> chroma fraction AND the strength of the prismatic fringe
//   tintMix     -> tint strength, tint colour from `dark`
//   saturation  -> applySCB saturation
//   rim         -> rim light intensity multiplier
//   grain       -> fine grain added after the lighting
//   magnify     -> vertical lens pre-warp of the sample position
//   rimTint / ringW (incl. negative "corner light") / flatInner / squircle /
//   shadowAmt / debug: as before.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

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
#ifdef SPOTLIGHT_GOOEY
    float pillWidth;
    float mergeRadius;
    vec4 button0;
    vec4 button1;
    vec4 button2;
    vec4 button3;
    vec4 button4;
#endif
};

layout(binding = 1) uniform sampler2D src;

#include "../Common/DarkGlass.glsl"

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
#ifdef SPOTLIGHT_GOOEY
// Same glass material, with a single animated capsule/metaball silhouette.
// Build: qsb --qt6 -D SPOTLIGHT_GOOEY -o spotlightgooey.frag.qsb liquidglass.frag
#include "spotlightgooey.glsl"
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
vec3 sampleBackdropPx(vec2 samplePx, vec2 ext, vec2 spread)
{
    vec2 o1 = vec2( 0.375, -0.125) * spread;
    vec2 o2 = vec2( 0.125,  0.375) * spread;
    vec2 o3 = vec2(-0.375,  0.125) * spread;
    vec2 o4 = vec2(-0.125, -0.375) * spread;
    vec3 sum =
        texture(src, clamp((samplePx + o1 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx + o2 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx + o3 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx + o4 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb;
    if (dot(ext, ext) <= 0.0)
        return sum * 0.25;
    sum +=
        texture(src, clamp((samplePx + ext * 0.90 + o1 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx + ext * 0.55 + o2 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx + ext * 0.22 + o3 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx - ext * 0.22 + o4 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx - ext * 0.55 + o1 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb +
        texture(src, clamp((samplePx - ext * 0.90 + o2 + srcOffset) / srcSize, vec2(0.001), vec2(0.999))).rgb;
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

void main()
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

    // lens band: proportional to the glass (deep), or the old dark bevel
    float lensBand  = shallowDark ? darkGlassBevel(min(hs.x, hs.y)) : lensBandFor(min(hs.x, hs.y));
    float lensScale = shallowDark ? 1.0 : lensScaleFor(lensBand);

    // ── masks ──
    float edgeFeather = max(EDGE_SMOOTHING, 0.75);
    float outsideTransition = smoothstep(-edgeFeather, edgeFeather, d);
    float insideMask  = 1.0 - outsideTransition;
    float outsideMask = outsideTransition;

    if (debug > 0.5) {
        vec4 s = texture(src, clamp((p + srcOffset) / srcSize, vec2(0.001), vec2(0.999)));
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

#ifdef SPOTLIGHT_BORDER_ONLY
    // Spotlight keeps its refractive body and one inset border. No shadow,
    // inner glow, outer halo or second outline, including during the gooey morph.
    vec2 borderNormal = sdRoundRectDir(localPos, hs, corner);
    float borderLight = pow(max(dot(borderNormal, L_KEY), 0.0), 1.65)
                      + 0.94 * pow(max(dot(borderNormal, L_FILL), 0.0), 1.65);
    float borderAA = max(fwidth(d) * 0.5, 0.001);
    float borderWidth = clamp(abs(ringW), 0.5, 1.0);
    float borderMask = smoothstep(-borderWidth - borderAA, -borderWidth + borderAA, d);
    vec3 borderColor = mix(baseColor, vec3(0.96, 0.98, 1.0), 0.48);
    float borderOpacity = clamp((0.18 + borderLight * 0.50) * clamp(rim / 0.45, 0.0, 1.5), 0.0, 0.65);
    vec3 cleanColor = mix(baseColor, borderColor, borderMask * borderOpacity);
    float cleanNoise = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    cleanColor = clamp(cleanColor + cleanNoise * grain + ditherLSB(p), 0.0, 1.0);
    fragColor = vec4(cleanColor * insideMask, insideMask) * qt_Opacity;
    return;
#endif

#ifdef DOCK_THIN_BORDER
    // Dock only: a fine inset stroke with opposing diagonal specular lights.
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
#endif

    // outward unit normal of the silhouette (2D) and how it faces the lights
    vec2 n2 = sdRoundRectDir(localPos, hs, corner);
    float keyFacing  = dot(n2, L_KEY);                       // -1 .. 1
    float keyF  = pow(max(keyFacing, 0.0), 1.5);
    float fillF = pow(max(dot(n2, L_FILL), 0.0), 1.5);
    float rimDir = RIM_BASE + RIM_KEY * keyF + RIM_FILL * fillF;

    float rimAmt      = clamp(rim, 0.0, 2.0);
    float rimStrength = rimAmt * 1.7;

    // colour of the rim / border: white, or (rimTint) a brighter shade of the glass here
    vec3 rimCol = mix(vec3(0.96, 0.98, 1.0), clamp(baseColor * 1.5 + 0.12, 0.0, 1.0), clamp(rimTint, 0.0, 1.0));

    // depth shading across the bevel: the side facing the key light is a touch
    // brighter, the far side a touch deeper
    float bevelMask = 1.0 - smoothstep(0.0, lensBand, depthPx);
    baseColor *= 1.0 + DEPTH_SHADE * bevelMask * keyFacing * 0.5;

    // ── inner AO band ──
    float aoMask = 1.0 - smoothstep(0.0, max(AO_RADIUS, 0.001), -d);
    float aoIntensity = AO_INTENSITY * (1.0 - clamp(flatInner, 0.0, 1.0));
    vec3 lightDir = normalize(vec3(cos(lightAngleRad), -sin(lightAngleRad), 0.38)); // light from the top
    float lightMask = pow(abs(dot(normal, lightDir)), max(RIM_DIRECTIONAL_POWER, 1.0));
    baseColor *= 1.0 - aoMask * aoIntensity * (1.0 - lightMask);

    // ── border light ──
    // 1. thin crisp line on the edge
    float rimWidthF = clamp(bezel * 0.09, 1.6, 3.0);
    float edgeBand  = 1.0 - smoothstep(0.0, max(rimWidthF, 0.001), abs(d));
    // 2. soft glow just inside it
    float glowR  = clamp(lensBand * 0.20, RIM_GLOW_MIN, RIM_GLOW_MAX);
    float glowIn = exp(-depthPx / glowR) * (1.0 - smoothstep(glowR * 3.0, glowR * 5.0, depthPx));
    // 3. broad sheens: light under the top edge, cool glow on the bottom right
    float sheenWin = 1.0 - smoothstep(lensBand * 0.55, lensBand, depthPx);
    float topSheen = exp(-depthPx / (lensBand * 0.60)) * sheenWin * smoothstep(0.0, 0.8, -n2.y) * SHEEN_TOP;
    float brGlow   = exp(-depthPx / (lensBand * 0.45)) * sheenWin * pow(max(dot(n2, L_FILL), 0.0), 1.3) * GLOW_BR;

    // broad light keeps the hue of what is behind the glass
    float broadLight = clamp(glowIn * RIM_GLOW_GAIN * rimDir * rimStrength + topSheen * rimAmt, 0.0, 1.0);
    vec3 litColor = baseColor + broadLight - baseColor * broadLight;
    if (broadLight > 0.0)
        litColor = backdropHighlight(baseColor, litColor, broadLight);
    litColor = screenBlend(litColor, vec3(0.60, 0.88, 1.00) * brGlow * rimAmt);

    // the crisp line itself stays white (or the tinted rim colour)
    float coreA = clamp(edgeBand * rimDir * rimStrength * RIM_CORE_GAIN, 0.0, 1.0);
    litColor = screenBlend(litColor, rimCol * coreA);

    // prismatic fringe just inside the edge, strongest at the top right
    float prismT    = clamp(depthPx / max(lensBand * 0.5, 1.0), 0.0, 1.0);
    float prismMask = smoothstep(0.6, 3.0, depthPx) * (1.0 - smoothstep(lensBand * 0.15, lensBand * 0.55, depthPx));
    float prismDir  = pow(max(dot(n2, P_DIR1), 0.0), 1.4) + 0.30 * pow(max(dot(n2, P_DIR2), 0.0), 1.4);
    float prismAmt  = clamp(dispersion * 1.6, 0.0, 1.0) * PRISM_GAIN * prismDir * prismMask;
    litColor = screenBlend(litColor, prismColor(prismT) * prismAmt);

    float maxChannel = max(litColor.r, max(litColor.g, litColor.b));
    if (maxChannel > 1.0) litColor /= maxChannel;
    litColor = max(litColor, vec3(0.0));

    float alpha = insideMask;

    // thin border line along the very edge (ringW > 0)
    if (ringW > 0.0) {
        float t   = depthPx;
        float ring = 1.0 - smoothstep(ringW * 0.5, ringW * 0.5 + 1.0, t);
        float facing = dot(n2, normalize(vec2(-0.55, -0.83)));
        litColor = mix(litColor, rimCol, ring * (0.55 + 0.35 * clamp(facing * 0.5 + 0.5, 0.0, 1.0)));
    }

    // ringW < 0: "corner light" border — runs all the way round and fades out
    // only at the top-right and bottom-left corners, in a bright shade of the
    // backdrop colour behind that spot. Used by the Control Center.
    if (ringW < 0.0) {
        float rw   = -ringW;
        float ring = 1.0 - smoothstep(rw * 0.5, rw * 0.5 + 1.0, depthPx);
        float glow = exp(-depthPx / (rw * 2.2)) * 0.30;
        float fall = max(cornerRadius * 3.0, 26.0);
        float wTR  = pow(clamp(1.0 - length(q - vec2( hs.x, -hs.y)) / fall, 0.0, 1.0), 1.2);
        float wBL  = pow(clamp(1.0 - length(q - vec2(-hs.x,  hs.y)) / fall, 0.0, 1.0), 1.2);
        float cw   = 1.0 - max(wTR, wBL);
        vec3 ringCol = clamp(litColor * 2.0 + 0.18, 0.0, 1.0);
        litColor = mix(litColor, ringCol, clamp((ring + glow) * cw, 0.0, 1.0) * 0.95);
    }

    // fine triangular-distribution grain, same on every channel
    float gn = hash12(gl_FragCoord.xy) + hash12(gl_FragCoord.xy * 1.7 + 17.0) - 1.0;
    litColor += gn * grain;

    litColor = clamp(litColor, 0.0, 1.0);

    // the half of the border line (and its tight halo) that sits OUTSIDE the edge
    float dOut = max(d, 0.0);
    float outerCore = 1.0 - smoothstep(0.0, max(rimWidthF, 0.001), dOut);
    float outerHalo = exp(-dOut / 2.5);
    float outerA = clamp((outerCore * RIM_OUTER_GAIN + outerHalo * 0.18) * outsideMask * rimDir * rimStrength, 0.0, 1.0);

    // glass over (outer line over shadow), premultiplied alpha
    vec3  shadowRgb = vec3(0.03, 0.04, 0.08) * shadowAlpha;
    vec3  belowRgb  = rimCol * outerA + shadowRgb * (1.0 - outerA);
    float belowA    = outerA + shadowAlpha * (1.0 - outerA);
    vec3  finalRgb   = litColor * alpha + belowRgb * (1.0 - alpha);
    float finalAlpha = alpha + belowA * (1.0 - alpha);
    finalRgb = max(finalRgb + ditherLSB(p) * finalAlpha, vec3(0.0));

    fragColor = vec4(finalRgb, finalAlpha) * qt_Opacity;   // premultiplied alpha
}
