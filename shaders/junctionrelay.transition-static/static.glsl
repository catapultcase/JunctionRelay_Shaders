// JR Transition Static — Channel Change Static
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural CRT channel-change static — no texture required.
// Multi-octave noise with row-band modulation, signal dropout, sync roll bars,
// horizontal tears, scanlines, shadow mask, vignette, and phosphor tint.
// Single pass — no bloom or barrel distortion (nothing to warp or diffuse).
//
// Uniforms: staticColor, scanlineWeight, pixelGrid, rollSpeed, tearStrength,
//           colorShift, vignetteAmount, flickerAmount

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

    // ── 1. Horizontal tear — displace UV before noise sampling ───────────────
    // ~10% of bands randomly jump left or right, carrying their noise with them.
    float tearSeed   = floor(uv.y * 50.0 + floor(iTime * 5.0));
    float tearActive = step(0.90, hash11(tearSeed));
    float tearDir    = hash11(tearSeed + 100.0) * 2.0 - 1.0;
    vec2  noiseUV    = uv;
    noiseUV.x       += tearActive * tearStrength * tearDir;

    vec2 p = noiseUV * iResolution.xy;

    // ── 2. Signal modulation ──────────────────────────────────────────────────
    // Quantize time to ~24fps for authentic analogue noise frame rate.
    float t = floor(iTime * 24.0);

    // Row-band modulation — groups of ~5 rows share a brightness level.
    // This is what gives real CRT static its banded texture, not just flat snow.
    float rowKey = floor(noiseUV.y * iResolution.y / 5.0) * 0.317
                 + floor(iTime * 9.0) * 2.13;
    float rowMod = 0.15 + hash11(rowKey) * 1.1;

    // Signal dropout — brief dark band simulating momentary signal loss.
    float dropTime = floor(iTime * 4.0);
    float dropY    = hash11(dropTime + 3.17) * 0.80 + 0.05;
    float dropH    = 0.01 + hash11(dropTime + 7.31) * 0.05;
    float dropout  = 1.0 - step(0.65, hash11(dropTime + 0.51))
                         * step(dropY, noiseUV.y) * step(noiseUV.y, dropY + dropH)
                         * 0.88;

    // Vertical sync roll bars — two staggered bars drifting upward.
    float roll1  = fract(iTime * rollSpeed);
    float roll2  = fract(iTime * rollSpeed * 0.71 + 0.43);
    float bar1   = 1.0 - 0.30 * smoothstep(0.0, 0.035,
                       abs(fract(noiseUV.y - roll1) - 0.5) - 0.465);
    float bar2   = 1.0 - 0.20 * smoothstep(0.0, 0.05,
                       abs(fract(noiseUV.y - roll2) - 0.5) - 0.45);
    float rollMod = mix(1.0, bar1 * bar2, step(0.001, rollSpeed));

    // ── 3. Multi-octave static noise ──────────────────────────────────────────
    float fine   = hash21(p + vec2(t * 1.73, t * 0.91));
    float medium = hash21(floor(p / 3.0) + vec2(t * 0.67, t * 1.19));
    float snow   = clamp((fine * 0.65 + medium * 0.35) * rowMod, 0.0, 1.0);
    snow *= dropout * rollMod;

    // Bright sparks — hot pixels simulating electrical discharge.
    float spark = step(0.997, hash21(floor(p / 2.0) + floor(iTime * 30.0) * 3.71));
    snow = min(snow + spark * 1.2, 1.0);

    // ── 4. Scanlines ──────────────────────────────────────────────────────────
    float scanRow  = floor(fragCoord.y * 0.5);
    float scanMask = 1.0 - scanlineWeight * (1.0 - step(0.5, fract(scanRow * 0.5)));
    snow *= scanMask;

    // ── 5. Shadow mask / pixel grid ───────────────────────────────────────────
    float gx      = fract(fragCoord.x / 3.0);
    float gy      = fract(fragCoord.y / 3.0);
    float dotMask = smoothstep(0.0, 0.3, gx) * smoothstep(1.0, 0.7, gx)
                  * smoothstep(0.0, 0.3, gy) * smoothstep(1.0, 0.7, gy);
    snow *= mix(1.0, dotMask * 0.7 + 0.3, pixelGrid);

    // ── 6. Phosphor tint + optional colour noise ──────────────────────────────
    vec3 colorFine = vec3(
        hash21(p + vec2(t * 2.31, 0.11)),
        hash21(p + vec2(t * 1.87, 0.53)),
        hash21(p + vec2(t * 1.51, 0.89))
    );
    vec3 colorSnow = clamp(colorFine * rowMod, 0.0, 1.0) * dropout * rollMod;
    colorSnow = min(colorSnow + spark, 1.0);
    colorSnow *= scanMask * mix(1.0, dotMask * 0.7 + 0.3, pixelGrid);

    vec3 col = mix(staticColor * snow, colorSnow, colorShift);

    // ── 7. Power supply flicker ───────────────────────────────────────────────
    float flicker = 1.0 - flickerAmount * (
        sin(iTime * 7.3) * 0.5 + sin(iTime * 17.1) * 0.3 + sin(iTime * 2.1) * 0.2
    );
    col *= flicker;

    // ── 8. Bezel vignette ─────────────────────────────────────────────────────
    vec2  vig  = uv * (1.0 - uv);
    float vign = pow(vig.x * vig.y * 18.0, 0.45);
    col       *= mix(1.0, vign, vignetteAmount);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
