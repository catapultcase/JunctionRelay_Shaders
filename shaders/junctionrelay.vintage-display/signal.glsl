// Vintage Display — Signal Degradation (Pass 1)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Reads pass 0 output and applies RF/analogue signal degradation:
//   H-tear → sample → ghost → ripple → sync roll → static → glitch strips
//
// Inputs:  iChannel0 (pass 0 — display output), iResolution, iTime
// Uniforms: staticAmount, rippleStrength, rollSpeed, glitchRate, ghostOffset, tearStrength

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

// 5×7 bitmap font — digits 0-9, each row is a 5-bit mask (bit4 = leftmost).
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

    // ── 1. Horizontal tear — UV displacement before sampling ──────────────────
    // ~8% of horizontal bands randomly displaced left or right.
    float tearSeed   = floor(uv.y * 40.0 + floor(iTime * 4.0));
    float tearActive = step(0.92, hash11(tearSeed));
    float tearDir    = hash11(tearSeed + 100.0) * 2.0 - 1.0;
    uv.x            += tearActive * tearStrength * tearDir;

    // ── 2. Sample pass 0 output ───────────────────────────────────────────────
    vec3 col = texture(iChannel0, uv).rgb;

    // ── 3. Signal ghosting — blends a horizontally shifted echo ───────────────
    // Primary echo to the right; secondary faint pre-echo to the left.
    vec3 ghostR = texture(iChannel0, uv + vec2(ghostOffset, 0.0)).rgb;
    vec3 ghostL = texture(iChannel0, uv - vec2(ghostOffset * 0.5, 0.0)).rgb;
    float ghostMix = min(ghostOffset * 12.0, 0.35);
    col = col * (1.0 - ghostMix) + ghostR * ghostMix * 0.75 + ghostL * ghostMix * 0.25;

    // ── 4. Horizontal raster interference ripple ──────────────────────────────
    // Two overlapping sine bands for organic interference look.
    float ripple = sin(uv.y * 85.0 + iTime * 1.3) * rippleStrength
                 + sin(uv.y * 23.0 - iTime * 0.7) * rippleStrength * 0.75;
    col += ripple;

    // ── 5. Vertical sync roll — dim bar drifts up like an unsynced monitor ────
    // rollSpeed=0 disables. Higher values make the bar scroll faster.
    float rollPhase = fract(iTime * rollSpeed);
    float rollBar   = 1.0 - 0.18 * smoothstep(0.0, 0.04,
                          abs(fract(uv.y - rollPhase) - 0.5) - 0.46);
    col *= mix(1.0, rollBar, step(0.001, rollSpeed));

    // ── 6. Static snow — random noise overlay ─────────────────────────────────
    float snow = hash21(uv + fract(iTime * 137.5)) - 0.5;
    col += snow * staticAmount;

    // ── 7. Data corruption glitch strip ───────────────────────────────────────
    // Fires periodically based on glitchRate. Renders tiled bitmap digits
    // in the phosphor hue sampled from the surrounding image.
    // Rate maps to cycle fraction: higher rate = shorter off-cycle, more strips.
    float glitchCycleLen  = max(1.0 - glitchRate * 1.8, 0.1);
    float glitchCycle     = fract(iTime * 0.12);
    float glitchActive    = step(glitchCycleLen, glitchCycle);
    float glitchY         = hash11(floor(iTime * 0.12)) * 0.75 + 0.1;
    float glitchHeight    = 0.04;
    float inStrip         = glitchActive
                          * step(glitchY, uv.y)
                          * step(uv.y, glitchY + glitchHeight);

    if (inStrip > 0.0)
    {
        // Derive phosphor hue from the image so glyphs match the selected color
        vec3 hueRef  = texture(iChannel0, vec2(0.5, 0.5)).rgb;
        float hueMax = max(max(hueRef.r, hueRef.g), hueRef.b);
        vec3 hue     = hueRef / max(hueMax, 0.1);

        int cellW   = 6;
        int cellH   = 9;
        int cellX   = int(mod(fragCoord.x, float(cellW)));
        int cellY   = int(mod(fragCoord.y - glitchY * iResolution.y, float(cellH)));
        int glyphId = int(hash21(vec2(floor(fragCoord.x / float(cellW)),
                                     floor(iTime * 6.0))) * 10.0);

        float bit = bitmapGlyph(glyphId, cellX, cellY);
        col       = mix(hue * 0.03, hue * 0.85, bit);
    }

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
