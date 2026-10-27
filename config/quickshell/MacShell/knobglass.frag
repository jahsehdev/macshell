#version 440
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
