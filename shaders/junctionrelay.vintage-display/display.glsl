// Vintage Display — Core CRT Simulation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Barrel warp → luminance → phosphor tint → scanlines → pixel grid → brightness.
// Converts the source texture to monochrome phosphor display output.
// All subsequent passes read this result via iChannel0.
//
// Inputs:  iChannel0 (source texture), iResolution
// Uniforms: phosphorColor, phosphorDrive, scanlineWeight, warpAmount, pixelGrid, brightness

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;

    // ── 1. Barrel / CRT warp ──────────────────────────────────────────────────
    // Configurable strength — 0.04 is subtle, 0.12 is pronounced.
    vec2 centered  = uv * 2.0 - 1.0;
    vec2 warp      = centered * (1.0 + dot(centered, centered) * warpAmount);
    vec2 warpedUV  = warp * 0.5 + 0.5;

    // Black outside the warped screen boundary
    float inBounds = step(0.0, warpedUV.x) * step(warpedUV.x, 1.0)
                   * step(0.0, warpedUV.y) * step(warpedUV.y, 1.0);

    vec3 col = texture(iChannel0, warpedUV).rgb * inBounds;

    // ── 2. Phosphor color grading ─────────────────────────────────────────────
    // Convert to luminance, apply drive curve, then re-tint with phosphorColor.
    // phosphorDrive < 1 darkens mids (high contrast), > 1 overdrives bright areas.
    float luma   = dot(col, vec3(0.299, 0.587, 0.114));
    float driven = pow(max(luma, 0.0), 1.0 / max(phosphorDrive, 0.01));
    col = phosphorColor * driven;

    // Phosphor corona — extra glow boost in high-luminance areas
    col += phosphorColor * pow(luma, 2.5) * 0.15;

    // ── 3. Scanlines ──────────────────────────────────────────────────────────
    // Alternating bright/dim row pairs. Weight 0 = no effect, 1 = full black rows.
    float scanRow  = floor(fragCoord.y * 0.5);
    float scanMask = 1.0 - scanlineWeight * (1.0 - step(0.5, fract(scanRow * 0.5)));
    col *= scanMask;

    // ── 4. Shadow mask / pixel grid ───────────────────────────────────────────
    // 3×3 phosphor dot pattern — smoothed at dot edges to simulate phosphor shape.
    float gx      = fract(fragCoord.x / 3.0);
    float gy      = fract(fragCoord.y / 3.0);
    float dotMask = smoothstep(0.0, 0.3, gx) * smoothstep(1.0, 0.7, gx)
                  * smoothstep(0.0, 0.3, gy) * smoothstep(1.0, 0.7, gy);
    col *= mix(1.0, dotMask * 0.7 + 0.3, pixelGrid);

    // ── 5. Brightness offset ──────────────────────────────────────────────────
    col += brightness;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
