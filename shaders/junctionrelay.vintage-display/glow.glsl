// Vintage Display — Phosphor Afterglow & Atmosphere (Pass 2)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Reads pass 1 output and applies the final atmosphere layer:
//   bloom → flicker → vignette → grain → warmth → gamma
//
// Star-pattern bloom (4 directions × 6 taps) simulates phosphor diffusion
// through the curved glass face. No luminance threshold — all lit pixels
// glow proportionally to their brightness.
//
// Inputs:  iChannel0 (pass 1 — signal output), iResolution, iTime
// Uniforms: glowStrength, glowSpread, vignetteAmount, flickerAmount, grainAmount, warmth

// ── Helpers ──────────────────────────────────────────────────────────────────

float hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv  = fragCoord.xy / iResolution.xy;
    vec3 col = texture(iChannel0, uv).rgb;

    // ── 1. Phosphor bloom — star-pattern multi-tap ────────────────────────────
    // 4 directions (H, V, 2 diagonals) × 6 taps each = 48 samples.
    // All pixels contribute to bloom proportionally — no threshold.
    // glowSpread controls radius; glowStrength controls additive weight.
    vec2 px = 1.0 / iResolution.xy;
    vec3 bloom = vec3(0.0, 0.0, 0.0);

    vec2 dirs[4];
    dirs[0] = vec2(1.0, 0.0);
    dirs[1] = vec2(0.0, 1.0);
    dirs[2] = vec2(0.707, 0.707);
    dirs[3] = vec2(0.707, -0.707);

    for (int d = 0; d < 4; d++) {
        vec2 dir = dirs[d] * px;
        for (int i = 1; i <= 6; i++) {
            float fi     = float(i);
            float weight = 1.0 / (1.0 + fi * 0.8);
            vec2 offset  = dir * fi * glowSpread;
            bloom += texture(iChannel0, uv + offset).rgb * weight;
            bloom += texture(iChannel0, uv - offset).rgb * weight;
        }
    }

    bloom /= 24.0;

    // Additive bloom — glow bleeds outward from bright areas
    col += bloom * glowStrength;

    // ── 2. Power supply flicker ───────────────────────────────────────────────
    // Slow combined-frequency oscillation simulates capacitor ripple.
    float flicker = 1.0 - flickerAmount * (
        sin(iTime * 7.3) * 0.5 + sin(iTime * 17.1) * 0.3 + sin(iTime * 2.1) * 0.2
    );
    col *= flicker;

    // ── 3. Bezel vignette ─────────────────────────────────────────────────────
    // Smooth darkening toward all four edges, like CRT shadow mask fall-off.
    vec2 vig   = uv * (1.0 - uv);
    float vign = pow(vig.x * vig.y * 18.0, 0.45);
    col       *= mix(1.0, vign, vignetteAmount);

    // ── 4. Film / phosphor grain ──────────────────────────────────────────────
    float grain = hash21(uv + fract(iTime * 73.1)) - 0.5;
    col += grain * grainAmount;

    // ── 5. Warmth — age yellowing / warm shift ────────────────────────────────
    // Multiplies by a warm tint: boosts red, dims blue. Simulates phosphor aging
    // and glass discolouration. At warmth=0 no effect; at 1 strong amber cast.
    vec3 warmTint = vec3(1.0 + warmth * 0.15, 1.0 + warmth * 0.02, 1.0 - warmth * 0.18);
    col = mix(col, col * warmTint, warmth);

    // ── 6. Gamma punch ────────────────────────────────────────────────────────
    col = pow(clamp(col, 0.0, 1.0), vec3(0.88, 0.88, 0.88));

    // Alpha from processed luminance so "Force transparent" reveals the source behind dark areas
    float outLuma = dot(col, vec3(0.299, 0.587, 0.114));
    fragColor = vec4(col, clamp(outLuma * 2.5, 0.0, 1.0));
}
