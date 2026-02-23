// JR Transition Static — Static Generation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural CRT channel-change static — no texture required.
// Barrel warp → H-tear → multi-octave noise → dropout → roll bars
//   → scanlines → pixel grid → phosphor tint + optional colour noise.
//
// Uniforms: staticColor, warpAmount, scanlineWeight, pixelGrid,
//           rollSpeed, tearStrength, colorShift

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

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;

    // ── 1. CRT barrel warp ────────────────────────────────────────────────────
    vec2 centered  = uv * 2.0 - 1.0;
    vec2 warped    = centered * (1.0 + dot(centered, centered) * warpAmount);
    vec2 warpedUV  = warped * 0.5 + 0.5;
    float inBounds = step(0.0, warpedUV.x) * step(warpedUV.x, 1.0)
                   * step(0.0, warpedUV.y) * step(warpedUV.y, 1.0);

    // ── 2. Horizontal tear — displace UV before noise sampling ───────────────
    // ~10% of horizontal bands randomly jump left or right.
    float tearSeed   = floor(warpedUV.y * 50.0 + floor(iTime * 5.0));
    float tearActive = step(0.90, hash11(tearSeed));
    float tearDir    = hash11(tearSeed + 100.0) * 2.0 - 1.0;
    vec2  noiseUV    = warpedUV;
    noiseUV.x       += tearActive * tearStrength * tearDir;

    // Pixel-space coordinates for hash lookups
    vec2 p = noiseUV * iResolution.xy;

    // ── 3. Signal modulation factors ──────────────────────────────────────────
    // Quantize time to ~24 discrete steps per second — authentic noise frame rate.
    float t = floor(iTime * 24.0);

    // Horizontal band modulation — groups of ~5 rows share a brightness level.
    // Drifts over time so bands move organically through the frame.
    float rowKey = floor(noiseUV.y * iResolution.y / 5.0) * 0.317
                 + floor(iTime * 9.0) * 2.13;
    float rowMod = 0.15 + hash11(rowKey) * 1.1;

    // Signal dropout — occasional brief dark band (signal momentarily lost).
    float dropTime  = floor(iTime * 4.0);
    float dropY     = hash11(dropTime + 3.17) * 0.80 + 0.05;
    float dropH     = 0.01 + hash11(dropTime + 7.31) * 0.05;
    float dropFire  = step(0.65, hash11(dropTime + 0.51)); // ~35% chance
    float dropout   = 1.0 - dropFire
                    * step(dropY, noiseUV.y) * step(noiseUV.y, dropY + dropH)
                    * 0.88;

    // Vertical sync roll bars — two staggered bars drift upward.
    // rollSpeed=0 disables entirely.
    float roll1 = fract(iTime * rollSpeed);
    float roll2 = fract(iTime * rollSpeed * 0.71 + 0.43);
    float bar1  = 1.0 - 0.30 * smoothstep(0.0, 0.035,
                      abs(fract(noiseUV.y - roll1) - 0.5) - 0.465);
    float bar2  = 1.0 - 0.20 * smoothstep(0.0, 0.05,
                      abs(fract(noiseUV.y - roll2) - 0.5) - 0.45);
    float rollMod = mix(1.0, bar1 * bar2, step(0.001, rollSpeed));

    // ── 4. Multi-octave static noise ──────────────────────────────────────────
    // Fine grain — individual pixel noise, changes every quantized frame.
    float fine   = hash21(p + vec2(t * 1.73, t * 0.91));
    // Medium grain — 3×3 pixel clusters, slightly slower tempo.
    float medium = hash21(floor(p / 3.0) + vec2(t * 0.67, t * 1.19));

    float snow = clamp((fine * 0.65 + medium * 0.35) * rowMod, 0.0, 1.0);
    snow *= dropout * rollMod;

    // Bright sparks — hot pixels simulating electrical discharge.
    float sparkFrame = floor(iTime * 30.0);
    float spark      = step(0.997, hash21(floor(p / 2.0) + sparkFrame * 3.71));
    snow = min(snow + spark * 1.2, 1.0);

    // ── 5. Scanlines ──────────────────────────────────────────────────────────
    float scanRow  = floor(fragCoord.y * 0.5);
    float scanMask = 1.0 - scanlineWeight * (1.0 - step(0.5, fract(scanRow * 0.5)));
    snow *= scanMask;

    // ── 6. Shadow mask / pixel grid ───────────────────────────────────────────
    float gx       = fract(fragCoord.x / 3.0);
    float gy       = fract(fragCoord.y / 3.0);
    float dotMask  = smoothstep(0.0, 0.3, gx) * smoothstep(1.0, 0.7, gx)
                   * smoothstep(0.0, 0.3, gy) * smoothstep(1.0, 0.7, gy);
    float gridMask = mix(1.0, dotMask * 0.7 + 0.3, pixelGrid);
    snow *= gridMask;

    // ── 7. Phosphor tint + optional colour noise ──────────────────────────────
    // colorShift=0: monochrome static in the chosen phosphor colour.
    // colorShift=1: full per-channel RGB noise (bad cable / colour TV static).
    // Both paths share the same signal modulation so effects are consistent.
    vec3 colorFine = vec3(
        hash21(p + vec2(t * 2.31, 0.11)),
        hash21(p + vec2(t * 1.87, 0.53)),
        hash21(p + vec2(t * 1.51, 0.89))
    );
    vec3 colorSnow = clamp(colorFine * rowMod, 0.0, 1.0) * dropout * rollMod;
    colorSnow = min(colorSnow + spark, 1.0);
    colorSnow *= scanMask * gridMask;

    vec3 monoCol = staticColor * snow;
    vec3 col     = mix(monoCol, colorSnow, colorShift);

    // Phosphor corona — extra flare on the brightest static pixels.
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col += staticColor * pow(luma, 3.0) * 0.12;

    // ── 8. Apply screen boundary ──────────────────────────────────────────────
    col *= inBounds;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
