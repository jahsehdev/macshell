// Luma's input pill and expanding answer card share one liquid silhouette.
// A smooth minimum creates the neck; its gradient drives the glass refraction.
float lumaRoundedBox(vec2 p, vec4 box, float radiusPx)
{
    float r = min(radiusPx, min(box.z, box.w));
    vec2 q = abs(p - box.xy) - box.zw + vec2(r);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    vec2 at = p + b;
    float a = lumaRoundedBox(at, lumaInput, 22.0);
    float d = lumaRoundedBox(at, lumaBody, lumaBodyRadius);
    float k = max(lumaMergeRadius, 0.001);
    float h = max(k - abs(a - d), 0.0) / k;
    return min(a, d) - h * h * k * 0.25;
}

vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    const vec2 e = vec2(0.4, 0.0);
    vec2 gradient = vec2(
        sdRoundRect(p + e.xy, b, corner) - sdRoundRect(p - e.xy, b, corner),
        sdRoundRect(p + e.yx, b, corner) - sdRoundRect(p - e.yx, b, corner));
    return gradient / max(length(gradient), 0.0001);
}
