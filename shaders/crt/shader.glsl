// CRT monitor — barrel distortion, phosphor subpixels, scanlines, bloom, flicker.
// Self-contained: driven entirely by iTime + UV, no extra cbuffers needed.
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime, iResolution

// ── Barrel distortion ────────────────────────────────────────────────────────
// Simulates the curved glass of a CRT tube

vec2 barrelDistort(vec2 uv, float k)
{
    vec2 centered = uv - 0.5;
    float r2      = dot(centered, centered);
    vec2 warped   = centered * (1.0 + k * r2);
    return warped + 0.5;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

float hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;

    // ── Barrel distortion ────────────────────────────────────────────────────
    float distortAmount = 0.15;
    vec2 curved = barrelDistort(uv, distortAmount);

    // Black outside the curved screen area
    if (curved.x < 0.0 || curved.x > 1.0 || curved.y < 0.0 || curved.y > 1.0)
    {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // ── Bloom / halation ─────────────────────────────────────────────────────
    // Simple 5-tap cross blur to simulate phosphor glow bleeding
    float bloomSpread = 2.0 / iResolution.x;
    vec3 bloom = vec3(0.0);
    bloom += texture(iChannel0, curved + vec2( bloomSpread, 0.0)).rgb;
    bloom += texture(iChannel0, curved + vec2(-bloomSpread, 0.0)).rgb;
    bloom += texture(iChannel0, curved + vec2(0.0,  bloomSpread)).rgb;
    bloom += texture(iChannel0, curved + vec2(0.0, -bloomSpread)).rgb;
    bloom += texture(iChannel0, curved).rgb;
    bloom /= 5.0;
    float bloomLuma = dot(bloom, vec3(0.299, 0.587, 0.114));
    float bloomMix  = pow(bloomLuma, 3.0) * 0.4;

    // ── Sample with RGB offset for chromatic fringing ────────────────────────
    float chromaOff = 0.5 / iResolution.x;
    float r = texture(iChannel0, curved + vec2( chromaOff, 0.0)).r;
    float g = texture(iChannel0, curved).g;
    float b = texture(iChannel0, curved + vec2(-chromaOff, 0.0)).b;
    vec3 col = vec3(r, g, b);

    // Mix in bloom
    col = mix(col, bloom, bloomMix);

    // ── Phosphor subpixel grid ───────────────────────────────────────────────
    // RGB vertical stripes simulating the shadow mask / aperture grille
    float px    = fragCoord.x;
    float sub   = mod(px, 3.0);
    vec3  mask  = vec3(0.7);
    if (sub < 1.0)      mask = vec3(1.0, 0.7, 0.7);
    else if (sub < 2.0) mask = vec3(0.7, 1.0, 0.7);
    else                mask = vec3(0.7, 0.7, 1.0);
    col *= mask;

    // ── Scanlines ────────────────────────────────────────────────────────────
    // Every other row is dimmer, weighted by brightness so darks get heavier lines
    float scanRow   = mod(fragCoord.y, 2.0);
    float scanBright = dot(col, vec3(0.299, 0.587, 0.114));
    float scanWeight = mix(0.55, 0.85, scanBright);
    float scanline   = mix(scanWeight, 1.0, step(1.0, scanRow));
    col *= scanline;

    // ── Warm CRT color shift ─────────────────────────────────────────────────
    // CRT phosphors tend slightly warm / amber
    col *= vec3(1.05, 1.0, 0.92);

    // ── Contrast boost ───────────────────────────────────────────────────────
    // CRTs had punchier contrast than LCDs
    col = pow(clamp(col, 0.0, 1.0), vec3(1.15));
    col = clamp(col * 1.1 - 0.03, 0.0, 1.0);

    // ── Frame flicker ────────────────────────────────────────────────────────
    // Subtle brightness variation per frame (60Hz refresh hum)
    float flicker = 0.97 + 0.03 * sin(iTime * 60.0 * 3.14159);
    col *= flicker;

    // ── Corner shadow / vignette ─────────────────────────────────────────────
    // Curved glass attenuates at the edges
    vec2 vig   = curved * (1.0 - curved);
    float vign = pow(vig.x * vig.y * 20.0, 0.5);
    col *= mix(0.3, 1.0, vign);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
