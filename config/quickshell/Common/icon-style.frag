#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float appearance;
    float dark;
    vec4 colorTint;
};
layout(binding=1) uniform sampler2D source;

vec3 rgb(vec4 p) { return p.rgb / max(p.a, 0.001); }
void main() {
    vec2 uv = qt_TexCoord0;
    vec4 p = texture(source, uv);
    vec3 c = rgb(p);
    float l = dot(c, vec3(0.2126,0.7152,0.0722));
    if (appearance < 0.5) { fragColor = p * qt_Opacity; return; }
    // Estimate the outer plate independently of the central app glyph.
    vec4 a = texture(source, vec2(0.5,0.12));
    vec4 b = texture(source, vec2(0.12,0.5));
    vec4 d = texture(source, vec2(0.88,0.5));
    vec4 e = texture(source, vec2(0.5,0.88));
    vec4 border = (a+b+d+e)*0.25;
    vec3 plate = rgb(border);
    float separation = clamp(length(c-plate)*1.7,0.0,1.0);
    float alpha = p.a;
    if (appearance < 1.5) {
        float whitePlate = smoothstep(0.55,0.9,dot(plate,vec3(0.2126,0.7152,0.0722)));
        float mask = (1.0-smoothstep(0.12,0.58,length(c-plate))) * whitePlate;
        c = mix(c*0.85,vec3(0.13,0.14,0.17) + c*0.06,mask*0.96);
    } else if (appearance < 2.5) {
        // Translucent silver plate, brighter embossed glyph; wallpaper shows through.
        float glyph = smoothstep(0.12,0.8,separation);
        vec3 silver = mix(vec3(0.76,0.82,0.88),vec3(0.22,0.27,0.34),dark);
        c = mix(silver,vec3(mix(0.97,0.86,dark)),glyph);
        c += (1.0-uv.y)*0.045;
        alpha *= mix(0.30,0.85,glyph);
    } else {
        float glyph = smoothstep(0.08,0.75,separation);
        vec3 ink = mix(colorTint.rgb,vec3(1.0),0.25) * (0.70+0.30*l);
        c = mix(vec3(0.075,0.085,0.105),ink,glyph);
    }
    fragColor = vec4(clamp(c,0.0,1.0)*alpha,alpha)*qt_Opacity;
}
