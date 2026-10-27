// Included only in the SPOTLIGHT_GOOEY variant of liquidglass.frag.
// Every distance/normal lookup sees the union, so internal seams disappear
// and the connecting necks refract the same backdrop as the search pill.
float gooeyUnion(float a, float b)
{
    float k = max(mergeRadius, 0.001);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float gooeyEllipse(vec2 p, vec4 shape)
{
    vec2 q = abs((p - shape.xy) / shape.zw);
    float n = 2.0; // Circular buttons, including while they stretch during opening.
    float extent = pow(pow(q.x, n) + pow(q.y, n), 1.0 / n);
    return (extent - 1.0) * min(shape.z, shape.w);
}

float sdRoundRect(vec2 p, vec2 b, vec2 corner)
{
    vec2 at = p + b;
    float r = min(b.y, pillWidth * 0.5);
    vec2 q = abs(at - vec2(pillWidth * 0.5, b.y)) - vec2(pillWidth * 0.5, b.y) + vec2(r);
    vec2 positive = max(q, 0.0);
    float n = 2.0 + 2.0 * clamp(squircle, 0.0, 1.0);
    float d = pow(pow(positive.x, n) + pow(positive.y, n), 1.0 / n) + min(max(q.x, q.y), 0.0) - r;
    d = gooeyUnion(d, gooeyEllipse(at, button0));
    d = gooeyUnion(d, gooeyEllipse(at, button1));
    d = gooeyUnion(d, gooeyEllipse(at, button2));
    d = gooeyUnion(d, gooeyEllipse(at, button3));
    return gooeyUnion(d, gooeyEllipse(at, button4));
}

vec2 sdRoundRectDir(vec2 p, vec2 b, vec2 corner)
{
    const vec2 e = vec2(0.4, 0.0);
    vec2 gradient = vec2(
        sdRoundRect(p + e.xy, b, corner) - sdRoundRect(p - e.xy, b, corner),
        sdRoundRect(p + e.yx, b, corner) - sdRoundRect(p - e.yx, b, corner));
    return gradient / max(length(gradient), 0.0001);
}
