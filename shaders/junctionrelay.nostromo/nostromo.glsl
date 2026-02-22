// Nostromo — Sci-fi cassette futurism pixel shader
// Amber phosphor CRT + chunky scanlines + raster interference + data corruption glyphs
// Inspired by the USCSS Nostromo MU-TH-UR 6000 terminal aesthetic.
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

// ── Helpers ──────────────────────────────────────────────────────────────────

float hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth noise for organic interference
float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),               hash21(i + vec2(1, 0)), u.x),
        mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x),
        u.y);
}

// 5x7 bitmap font — digits 0-9, each row is a 5-bit mask (bit4 = leftmost).
float bitmapGlyph(int id, int cx, int cy)
{
    if (cx < 0 || cx > 4 || cy < 0 || cy > 6) return 0.0;

    const uint font[70] = uint[70](
        0x0Eu, 0x11u, 0x13u, 0x15u, 0x19u, 0x11u, 0x0Eu, // 0
        0x04u, 0x0Cu, 0x04u, 0x04u, 0x04u, 0x04u, 0x0Eu, // 1
        0x0Eu, 0x11u, 0x01u, 0x06u, 0x08u, 0x10u, 0x1Fu, // 2
        0x1Fu, 0x02u, 0x04u, 0x02u, 0x01u, 0x11u, 0x0Eu, // 3
        0x02u, 0x06u, 0x0Au, 0x12u, 0x1Fu, 0x02u, 0x02u, // 4
        0x1Fu, 0x10u, 0x1Eu, 0x01u, 0x01u, 0x11u, 0x0Eu, // 5
        0x06u, 0x08u, 0x10u, 0x1Eu, 0x11u, 0x11u, 0x0Eu, // 6
        0x1Fu, 0x01u, 0x02u, 0x04u, 0x08u, 0x08u, 0x08u, // 7
        0x0Eu, 0x11u, 0x11u, 0x0Eu, 0x11u, 0x11u, 0x0Eu, // 8
        0x0Eu, 0x11u, 0x11u, 0x0Fu, 0x01u, 0x02u, 0x0Cu  // 9
    );

    uint row = font[(id % 10) * 7 + cy];
    return ((row >> (4 - cx)) & 1u) != 0u ? 1.0 : 0.0;
}

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // ── 1. Barrel / CRT warp ──────────────────────────────────────────────────
    vec2 centered = uv * 2.0 - 1.0;
    vec2 warp     = centered * (1.0 + dot(centered, centered) * 0.06);
    vec2 warpedUV = warp * 0.5 + 0.5;

    // Black outside the warped boundary
    float inBounds = step(0.0, warpedUV.x) * step(warpedUV.x, 1.0)
                   * step(0.0, warpedUV.y) * step(warpedUV.y, 1.0);

    vec4 col = texture(iChannel0, warpedUV) * inBounds;

    // ── 2. Phosphor color grading — amber / Weyland-Yutani terminal ───────────
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));

    vec3 phosphor;
    phosphor.r = luma * 1.10;
    phosphor.g = luma * 0.80;
    phosphor.b = luma * 0.08;

    // Sickly green corona in bright areas
    phosphor.g += pow(luma, 2.2) * 0.25;

    col.rgb = phosphor;

    // ── 3. Chunky CRT scanlines ───────────────────────────────────────────────
    float scanRow  = floor(fragCoord.y * 0.5);
    float scanline = 0.72 + 0.28 * step(0.5, fract(scanRow * 0.5));
    col.rgb       *= scanline;

    // ── 4. Horizontal raster interference ripple ──────────────────────────────
    float ripple = sin(uv.y * 85.0 + iTime * 1.3) * 0.04
                 + sin(uv.y * 23.0 - iTime * 0.7) * 0.03;
    col.rgb      += ripple;

    // ── 5. Vertical sync roll — dim bar drifts up like an unsync'd monitor ────
    float rollPhase = fract(iTime * 0.07);
    float rollBar   = 1.0 - 0.18 * smoothstep(0.0, 0.04,
                          abs(fract(uv.y - rollPhase) - 0.5) - 0.46);
    col.rgb        *= rollBar;

    // ── 6. Data corruption glitch strip ──────────────────────────────────────
    // Fires for ~6% of an 8-second cycle; renders tiled bitmap digits
    float glitchCycle  = fract(iTime * 0.12);
    float glitchActive = step(0.92, glitchCycle);
    float glitchY      = hash11(floor(iTime * 0.12)) * 0.75 + 0.1;
    float glitchHeight = 0.04;
    float inStrip      = glitchActive
                       * step(glitchY, uv.y)
                       * step(uv.y, glitchY + glitchHeight);

    if (inStrip > 0.0)
    {
        int cellW   = 6;
        int cellH   = 9;
        int cellX   = int(mod(fragCoord.x, float(cellW)));
        int cellY   = int(mod(fragCoord.y - glitchY * iResolution.y, float(cellH)));
        int glyphId = int(hash21(vec2(floor(fragCoord.x / float(cellW)),
                                         floor(iTime * 6.0))) * 10.0);

        float bit = bitmapGlyph(glyphId, cellX, cellY);
        col.rgb   = mix(vec3(0.02, 0.01, 0.0),
                         vec3(1.0,  0.65, 0.05),
                         bit);
    }

    // ── 7. Slow phosphor grain / thermal noise ────────────────────────────────
    float grain = hash21(warpedUV + fract(iTime * 73.1)) - 0.5;
    col.rgb    += grain * 0.035;

    // ── 8. Heavy bezel vignette ───────────────────────────────────────────────
    vec2 vig  = warpedUV * (1.0 - warpedUV);
    float  vign = pow(vig.x * vig.y * 18.0, 0.5);
    col.rgb    *= mix(0.0, 1.0, vign);

    // ── 9. Phosphor green fringing on bright edges ────────────────────────────
    float brightness = dot(col.rgb, vec3(1, 1, 1));
    col.g           += brightness * 0.04;

    // ── 10. Gamma punch ───────────────────────────────────────────────────────
    col.rgb = pow(clamp(col.rgb, 0.0, 1.0), vec3(0.88));

    fragColor = vec4(col.rgb, 1.0);
}
