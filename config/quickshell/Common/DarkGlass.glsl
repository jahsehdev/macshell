// Clear Liquid Glass for dark mode. Shared by the shell, menus, Launchpad and lock screen.
// Preserve backdrop colour, with a fine white rim and a positive-only soft glow.
float darkGlassBevel(float halfMin)
{
    // A wider bevel gives Dark more of the depth of the Light material.
    return clamp(halfMin * 0.28, 5.0, 14.0);
}

float darkGlassSaturation(float amount)
{
    return mix(1.0, amount, 0.70);
}

vec3 darkGlassBody(vec3 backdrop, float tint)
{
    // A subtle dark tint improves contrast for foreground text and icons.
    // Keep the backdrop visible and leave the lens depth and rim intact.
    float shade = 0.12 + clamp(tint, 0.0, 1.0) * 0.12;
    return mix(clamp(backdrop, 0.0, 1.0), vec3(0.055, 0.065, 0.085), shade);
}

vec2 darkGlassDisplacement(vec2 displacement, float halfMin)
{
    float reach = min(16.0, max(halfMin * 0.35, 1.5));
    return displacement * min(1.0, reach / max(length(displacement), 0.0001));
}

vec3 darkGlassLighting(vec3 base, float depth, vec2 outward, float rimAmount,
                       float borderWidth, float colourRim, float flatSurface)
{
    float facing = dot(outward, normalize(vec2(-0.65, -0.76)));
    float top = pow(max(facing, 0.0), 1.7);
    float bottom = pow(max(-facing, 0.0), 1.9);
    float distance = max(depth, 0.0);
    float hairline = exp(-distance / 0.62);
    float halo = exp(-distance / 3.2);
    float light = (hairline * (0.06 + 1.65 * top + 0.90 * bottom)
                 + halo * 0.065 * (0.2 + top + 0.65 * bottom)) * clamp(rimAmount, 0.0, 2.0);
    // Border-width settings never turn the highlight into a second broad rim.
    light += (1.0 - smoothstep(0.15, 0.95, distance))
           * min(abs(borderWidth), 1.0) * (0.035 + 0.06 * top + 0.04 * bottom);
    vec3 colour = mix(vec3(0.94, 0.98, 1.0), clamp(base * 0.35 + 0.65, 0.0, 1.0),
                      clamp(colourRim, 0.0, 1.0) * 0.15);
    // No inner AO, lower-edge darkening, or inset shadow, regardless of flatSurface.
    return base + (vec3(1.0) - base) * colour * clamp(light, 0.0, 0.75);
}
