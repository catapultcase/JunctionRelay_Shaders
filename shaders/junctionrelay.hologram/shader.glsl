// Hologram pixel shader — cyan tint + scanlines + iTime-based flicker + edge glow.
// Ported from XSD-VR Bridge V4 POC.
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec4 col = texture(iChannel0, uv);

    // Cyan hologram tint
    col.rgb = vec3(col.r * 0.3, col.g * 0.9, col.b * 1.0);

    // Scanlines — darken every other pair of lines
    float scanline = step(0.5, fract(fragCoord.y * 0.25));
    col.rgb *= 0.7 + 0.3 * scanline;

    // Time-based flicker
    float flicker = 0.92 + 0.08 * sin(iTime * 8.0);
    col.rgb *= flicker;

    // Slight edge glow boost
    float edge = smoothstep(0.0, 0.15, uv.x) * smoothstep(0.0, 0.15, 1.0 - uv.x);
    edge *= smoothstep(0.0, 0.15, uv.y) * smoothstep(0.0, 0.15, 1.0 - uv.y);
    col.rgb *= 0.6 + 0.4 * edge;

    fragColor = col;
}
