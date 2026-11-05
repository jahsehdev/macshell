#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 cropSize;
    float captureMargin;
    float strength;
    float tintOpacity;
    float liquidStrength;
    float rim;
    float grain;
    float wingSize;
    float radius;
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

void main() {
    vec2 uv = qt_TexCoord0;
    float alpha = shape(uv);
    if (alpha < 0.001) { fragColor = vec4(0); return; }
    vec2 px = 1.0 / max(ubuf.itemSize, vec2(1));
    vec2 p = uv * ubuf.itemSize;
    float d = bodyDistance(p);
    vec2 grad = vec2(bodyDistance(p + vec2(0.7, 0)) - bodyDistance(p - vec2(0.7, 0)),
                     bodyDistance(p + vec2(0, 0.7)) - bodyDistance(p - vec2(0, 0.7)));
    vec2 outward = length(grad) > 0.0001 ? normalize(grad) : vec2(0, 1);
    float depth = max(-d, 0.0);
    float bevel = clamp(min(ubuf.itemSize.x, ubuf.itemSize.y) * 0.18, 12.0, 28.0);
    float t = clamp(depth / bevel, 0.0, 1.0);
    float insideBody = 1.0 - smoothstep(-0.5, 0.5, d);
    float bevelMask = (1.0 - smoothstep(0.0, bevel, depth)) * insideBody;
    float optics = ubuf.strength * (ubuf.wingSize > 0.0 ? smoothstep(0.03, 0.22, uv.y) : 1.0);

    // A curved cross-section bends a real ray through the bevel, rather than
    // shifting only the outermost pixels. Magnification carries into the dome.
    float slope = (1.0 - t) / sqrt(max(t * (2.0 - t), 0.08));
    vec3 normal = normalize(vec3(outward * slope * 0.75, 1.0));
    vec3 ray = refract(vec3(0, 0, -1), normal, 1.0 / 1.47);
    float thickness = min(44.0, ubuf.itemSize.y * 0.3) * ubuf.liquidStrength;
    vec2 displacement = -ray.xy / max(abs(ray.z), 0.25) * thickness * bevelMask * optics;
    displacement = clamp(displacement, vec2(-48), vec2(48));
    vec2 dome = -(p - ubuf.itemSize * 0.5) * 0.035 * ubuf.liquidStrength * optics * (1.0 - bevelMask * 0.55);
    vec2 bent = p + dome + displacement;
    vec2 sampleUv = (bent + vec2(ubuf.captureMargin)) / ubuf.cropSize;
    vec2 chroma = displacement * min(0.025, 0.016 * ubuf.liquidStrength) / ubuf.cropSize;
    vec3 background = vec3(texture(src, sampleUv + chroma).r,
                           texture(src, sampleUv).g, texture(src, sampleUv - chroma).b);
    float clarity = 0.72 * bevelMask * (1.0 - ubuf.tintOpacity) * optics;
    background = mix(background, texture(clearSrc, sampleUv).rgb, clarity);
    // Retain the semi-glass contrast floor and black camera seam while the
    // shared material moves continuously from clear to frosted.
    float bodyTint = mix(0.52, 1.0, clamp(ubuf.tintOpacity, 0.0, 1.0));
    float tint = mix(0.97, bodyTint, smoothstep(0.12, 1.0, uv.y));
    tint = mix(1.0, tint, ubuf.strength);
    tint -= bevelMask * 0.10 * (1.0 - ubuf.tintOpacity) * optics;
    vec3 color = mix(background, vec3(0.018, 0.021, 0.023), tint);

    float left = shape(uv - vec2(px.x, 0)), right = shape(uv + vec2(px.x, 0));
    float top = shape(uv - vec2(0, px.y)), bottom = shape(uv + vec2(0, px.y));
    float edge = 1.0 - min(min(left, right), min(top, bottom));
    vec2 silhouetteNormal = vec2(left - right, top - bottom);
    vec2 lightNormal = length(silhouetteNormal) > 0.0001 ? normalize(silhouetteNormal) : outward;
    float key = max(dot(lightNormal, normalize(vec2(-0.65, -0.75))), 0.0);
    float fill = max(dot(lightNormal, normalize(vec2(0.7, 0.75))), 0.0);
    float facing = 0.12 + key * 0.60 + fill * 0.50;
    float innerArc = exp(-pow((depth - 2.0) / 0.85, 2.0)) * 0.35 * insideBody;
    float sheen = exp(-depth / 7.0) * 0.20 * insideBody;
    float seam = ubuf.wingSize > 0.0 ? smoothstep(0.0, 3.0, p.y) : 1.0;
    float reflection = (edge * 1.35 + innerArc + sheen) * facing * ubuf.rim * ubuf.strength * seam;
    // Refraction provides depth; do not paint a dark band inside the contour.
    color += vec3(0.83, 0.91, 1.0) * reflection;
    float noise = fract(sin(dot(uv * ubuf.itemSize, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
    color = clamp(color + noise * ubuf.grain * 0.12 * ubuf.strength, 0.0, 1.0);
    fragColor = vec4(color * alpha, alpha) * ubuf.qt_Opacity;
}
