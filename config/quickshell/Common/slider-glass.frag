#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 srcSize;
    vec2 srcOffset;
    vec4 baseColor;
    float materialOpacity;
    float strength;
    float rim;
    float dark;
    float spread;
};
layout(binding = 1) uniform sampler2D src;

vec3 sampleScene(vec2 p) {
    vec4 sampleColor = texture(src, clamp(p / max(srcSize, vec2(1.0)), vec2(0.001), vec2(0.999)));
    return sampleColor.rgb + baseColor.rgb * (1.0 - sampleColor.a);
}
void main() {
    vec2 halfSize = itemSize * 0.5;
    vec2 local = qt_TexCoord0 * itemSize - halfSize;
    float radius = halfSize.y;
    vec2 nearest = vec2(clamp(local.x, -halfSize.x + radius, halfSize.x - radius), 0.0);
    vec2 toEdge = local - nearest;
    float sdf = length(toEdge) - radius;
    float aa = max(fwidth(sdf), 0.5);
    float alpha = 1.0 - smoothstep(-aa, aa, sdf);
    if (alpha < 0.001) { fragColor = vec4(0.0); return; }
    float depth = max(0.0, -sdf);
    float edge = 1.0 - smoothstep(0.0, radius * 0.8, depth);
    vec2 normal = toEdge / max(length(toEdge), 0.001);
    // A convex lens magnifies the track through its centre and pulls it around
    // the capsule edges. This remains visible on a small 32 x 21 px control.
    float optics = clamp(strength, 0.0, 2.5);
    float interior = smoothstep(0.0, radius * 0.7, depth);
    vec2 warped = local * spread;
    warped.x /= 1.0 + 0.12 * optics * interior;
    warped.y /= 1.0 + 0.75 * optics * interior;
    vec2 lens = -normal * pow(edge, 1.7) * min(radius * 0.24, 3.0) * optics;
    vec2 p = srcOffset + halfSize + warped + lens;
    float split = 0.07 * optics * edge;
    vec3 color = vec3(sampleScene(p + lens * split).r,
                      sampleScene(p).g,
                      sampleScene(p - lens * split).b);
    vec3 tint = mix(vec3(0.70, 0.73, 0.77), vec3(0.06, 0.09, 0.13), dark);
    color = mix(color, tint, 0.12 + clamp(materialOpacity, 0.0, 1.0) * 0.23);
    // Directional hairline, rather than a broad white halo around the lens.
    float hairline = 1.0 - smoothstep(0.25 / spread, 0.65 / spread, depth);
    float light = clamp(dot(normal, normalize(vec2(-0.45, -0.9))), 0.0, 1.0);
    vec3 edgeColor = mix(vec3(0.12, 0.17, 0.23), vec3(0.73, 0.82, 0.91), light);
    color = mix(color, edgeColor, hairline * (0.16 + min(rim, 0.6) * 0.20));
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha) * qt_Opacity;
}
