#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 win;
    vec4 icon;
    float progress;
    float effect;
    float direction;
};
layout(binding=1) uniform sampler2D src;
vec2 orient(vec2 p) {
    if (direction > 1.5) return vec2(-p.y,p.x); // right
    if (direction > 0.5) return vec2(p.y,-p.x); // left
    return p;
}
vec4 orientedRect(vec4 r) {
    vec2 a=orient(r.xy), b=orient(r.zw);
    return vec4(min(a,b),max(a,b));
}
void main() {
    vec2 p=orient(qt_TexCoord0*itemSize);
    vec4 w=orientedRect(win), i=orientedRect(icon);
    float t=clamp(progress,0.,1.);
    vec2 uv;
    if (effect > .5) {
        vec4 r=mix(w,i,t);
        uv=(p-r.xy)/max(r.zw-r.xy,vec2(.001));
    } else {
        float drawIn=smoothstep(0.,.62,t);
        float travel=smoothstep(.35,1.,t);
        float top=mix(w.y,i.y,travel);
        float bottom=mix(w.w,i.w,drawIn);
        float v=(p.y-top)/max(.001,bottom-top);
        float bend=smoothstep(0.,1.,clamp(v,0.,1.));
        float l=mix(mix(w.x,i.x,travel),mix(w.x,i.x,drawIn),bend);
        float r=mix(mix(w.z,i.z,travel),mix(w.z,i.z,drawIn),bend);
        uv=vec2((p.x-l)/max(.001,r-l),v);
    }
    if (any(lessThan(uv,vec2(0.))) || any(greaterThan(uv,vec2(1.)))) { fragColor=vec4(0.); return; }
    if (direction > 1.5) uv=vec2(uv.y,1.-uv.x);
    else if (direction > .5) uv=vec2(1.-uv.y,uv.x);
    fragColor=texture(src,uv)*(1.-smoothstep(.92,1.,t))*qt_Opacity;
}
