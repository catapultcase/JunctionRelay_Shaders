// Vintage Display Light — Single-Pass CRT Simulation
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Pi-optimized single-pass variant of Vintage Display.
// Barrel warp, phosphor tint, scanlines, pixel grid, signal noise,
// sync roll, vignette, flicker, grain, warmth — all in one pass.
// 1 texture lookup per fragment. No bloom, no ghosting, no glitch strips.
//
// Inputs:  iChannel0 (source texture), iResolution, iTime
// Uniforms: phosphorColor, phosphorDrive, scanlineWeight, warpAmount,
//           pixelGrid, brightness, staticAmount, rippleStrength,
//           rollSpeed, vignetteAmount, flickerAmount, grainAmount, warmth

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
    vec2 uv = fragCoord.xy / iResolution.xy;

    // ── 1. Barrel / CRT warp ────────────────────────────────────────────────
    vec2 centered = uv * 2.0 - 1.0;
    vec2 warp     = centered * (1.0 + dot(centered, centered) * warpAmount);
    vec2 warpedUV = warp * 0.5 + 0.5;

    // Black outside the warped screen boundary
    float inBounds = step(0.0, warpedUV.x) * step(warpedUV.x, 1.0)
                   * step(0.0, warpedUV.y) * step(warpedUV.y, 1.0);

    vec3 col = texture(iChannel0, warpedUV).rgb * inBounds;

    // ── 2. Phosphor color grading ───────────────────────────────────────────
    float luma   = dot(col, vec3(0.299, 0.587, 0.114));
    float driven = pow(max(luma, 0.0), 1.0 / max(phosphorDrive, 0.01));
    col = phosphorColor * driven;

    // Phosphor corona — extra glow boost in high-luminance areas
    col += phosphorColor * pow(luma, 2.5) * 0.15;

    // ── 3. Scanlines ────────────────────────────────────────────────────────
    float scanRow  = floor(fragCoord.y * 0.5);
    float scanMask = 1.0 - scanlineWeight * (1.0 - step(0.5, fract(scanRow * 0.5)));
    col *= scanMask;

    // ── 4. Shadow mask / pixel grid ─────────────────────────────────────────
    float gx      = fract(fragCoord.x / 3.0);
    float gy      = fract(fragCoord.y / 3.0);
    float dotMask = smoothstep(0.0, 0.3, gx) * smoothstep(1.0, 0.7, gx)
                  * smoothstep(0.0, 0.3, gy) * smoothstep(1.0, 0.7, gy);
    col *= mix(1.0, dotMask * 0.7 + 0.3, pixelGrid);

    // ── 5. Brightness offset ────────────────────────────────────────────────
    col += brightness;

    // ── 6. Horizontal raster ripple ─────────────────────────────────────────
    float ripple = sin(uv.y * 85.0 + iTime * 1.3) * rippleStrength
                 + sin(uv.y * 23.0 - iTime * 0.7) * rippleStrength * 0.75;
    col += ripple;

    // ── 7. Vertical sync roll ───────────────────────────────────────────────
    float rollPhase = fract(iTime * rollSpeed);
    float rollBar   = 1.0 - 0.18 * smoothstep(0.0, 0.04,
                          abs(fract(uv.y - rollPhase) - 0.5) - 0.46);
    col *= mix(1.0, rollBar, step(0.001, rollSpeed));

    // ── 8. Static snow ──────────────────────────────────────────────────────
    float snow = hash21(uv + fract(iTime * 137.5)) - 0.5;
    col += snow * staticAmount;

    // ── 9. Power supply flicker ─────────────────────────────────────────────
    float flicker = 1.0 - flickerAmount * (
        sin(iTime * 7.3) * 0.5 + sin(iTime * 17.1) * 0.3 + sin(iTime * 2.1) * 0.2
    );
    col *= flicker;

    // ── 10. Bezel vignette ──────────────────────────────────────────────────
    vec2 vig   = uv * (1.0 - uv);
    float vign = pow(vig.x * vig.y * 18.0, 0.45);
    col       *= mix(1.0, vign, vignetteAmount);

    // ── 11. Film / phosphor grain ───────────────────────────────────────────
    float grain = hash21(uv + fract(iTime * 73.1)) - 0.5;
    col += grain * grainAmount;

    // ── 12. Warmth — age yellowing ──────────────────────────────────────────
    vec3 warmTint = vec3(1.0 + warmth * 0.15, 1.0 + warmth * 0.02, 1.0 - warmth * 0.18);
    col = mix(col, col * warmTint, warmth);

    // ── 13. Gamma punch ─────────────────────────────────────────────────────
    col = pow(clamp(col, 0.0, 1.0), vec3(0.88));

    // Alpha from processed luminance so "Force transparent" reveals the source behind dark areas
    float outLuma = dot(col, vec3(0.299, 0.587, 0.114));
    fragColor = vec4(col, clamp(outLuma * 2.5, 0.0, 1.0));
}
