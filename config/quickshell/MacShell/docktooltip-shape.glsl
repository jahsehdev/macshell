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
