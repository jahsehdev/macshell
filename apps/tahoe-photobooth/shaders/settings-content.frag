#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float reveal;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 uv = qt_TexCoord0;
    float settling = (1.0 - reveal) * (1.0 - reveal);
    vec2 pixel = 1.0 / max(itemSize, vec2(1.0));
    uv.x += sin(uv.y * 6.283) * 0.7 * settling * pixel.x;
    uv.y += sin(uv.x * 3.14159) * 0.35 * settling * pixel.y;
    vec2 blur = pixel * 0.5 * settling;
    vec4 color = texture(source, uv) * 0.5;
    color += texture(source, uv + blur) * 0.25;
    color += texture(source, uv - blur) * 0.25;
    fragColor = color * qt_Opacity;
}
