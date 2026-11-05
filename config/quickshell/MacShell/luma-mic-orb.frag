#version 440
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
