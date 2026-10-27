#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 captureSize;
    vec4 bodyRect;
    vec2 originCenter;
    float originRadius;
    float cornerRadius;
    float progress;
    float darkMode;
};
layout(binding = 1) uniform sampler2D source;

float roundedBox(vec2 p, vec2 halfSize, float radius) {
    vec2 d = abs(p) - halfSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}
float smoothUnion(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
float glassField(vec2 point) {
    vec2 size = max(bodyRect.zw, vec2(1.0));
    vec2 p = point - bodyRect.xy - size * 0.5;
    float radius = min(cornerRadius, min(size.x, size.y) * 0.5);
    // Low-frequency edge motion dies away completely at each endpoint.
    float liquid = sin(3.14159265 * progress);
    vec2 ripple = vec2(sin(p.y * 0.022 + progress * 5.0),
                       sin(p.x * 0.018 - progress * 4.0)) * liquid * 1.4;
    float body = roundedBox(p + ripple, size * 0.5, radius);
    // Smooth union of the original circular droplet with the growing menu makes
    // a soft neck, like blur + threshold, without a resolution-dependent blur mask.
    float droplet = originRadius * (1.0 - smoothstep(0.10, 0.62, progress));
    if (droplet > 0.01) {
        float circle = length(point - originCenter) - droplet;
        return smoothUnion(body, circle, max(0.01, liquid * 18.0));
    }
    return body;
}
vec3 sampleBackdrop(vec2 pixel) {
    return texture(source, clamp(pixel / captureSize, vec2(0.001), vec2(0.999))).rgb;
}
void main() {
    vec2 point = qt_TexCoord0 * captureSize;
    float d = glassField(point);
    float coverage = 1.0 - smoothstep(-0.75, 0.75, d);
    vec2 normal = vec2(glassField(point + vec2(0.5, 0.0)) - glassField(point - vec2(0.5, 0.0)),
                       glassField(point + vec2(0.0, 0.5)) - glassField(point - vec2(0.0, 0.5)));
    normal /= max(length(normal), 0.001);
    float motion = sin(3.14159265 * progress);
    float bezel = 1.0 - smoothstep(0.0, 14.0, -d);
    // Light refraction is confined to the rim, keeping the menu's centre quiet.
    vec2 pixel = point - normal * bezel * (1.4 + 1.1 * motion);
    float blur = 5.5 + motion;
    vec3 scene = sampleBackdrop(pixel) * 0.25;
    scene += (sampleBackdrop(pixel + vec2(blur, 0.0)) + sampleBackdrop(pixel - vec2(blur, 0.0))
        + sampleBackdrop(pixel + vec2(0.0, blur)) + sampleBackdrop(pixel - vec2(0.0, blur))) * 0.125;
    scene += (sampleBackdrop(pixel + vec2(blur, blur)) + sampleBackdrop(pixel - vec2(blur, blur))
        + sampleBackdrop(pixel + vec2(blur, -blur)) + sampleBackdrop(pixel + vec2(-blur, blur))) * 0.0625;
    vec3 tint = mix(vec3(0.965, 0.965, 0.98), vec3(0.17, 0.17, 0.19), darkMode);
    vec3 color = mix(scene, tint, mix(0.84, 0.76, darkMode));
    float rim = 1.0 - smoothstep(0.4, 1.7, -d);
    float shine = max(0.0, dot(normal, normalize(vec2(-0.5, -1.0))));
    color += rim * (0.06 + shine * 0.12) + bezel * shine * 0.02;
    float bodyY = clamp((point.y - bodyRect.y) / max(bodyRect.w, 1.0), 0.0, 1.0);
    color += (1.0 - bodyY) * mix(0.035, 0.018, darkMode);
    float alpha = coverage * qt_Opacity;
    fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
