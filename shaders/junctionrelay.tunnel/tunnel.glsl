// JR Tunnel — Sci-Fi Retro CGI Tunnel
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural wireframe tunnel — transparent between grid lines.
// Origin moves the vanishing point; curvature bends the near end.
// Explicit ring-circle approach: each depth ring is a perfect circle
// at a shifted centre, matching the original Canvas tunnel renderer.
// Single pass, no texture required.
//
// Uniforms: gridColor, speed, gridDensity, lineWidth, glowIntensity,
//           rotationSpeed, curvature, depthScale, depthOffset,
//           originX, originY

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);

    // ── 1. Origin (screen-space, rotation-independent) ──────────────────────
    uv -= vec2(originX, originY);

    // ── 2. Rotation ─────────────────────────────────────────────────────────
    float rot = iTime * rotationSpeed;
    float cs  = cos(rot);
    float sn  = sin(rot);
    uv = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);

    // ── 3. Explicit ring search ─────────────────────────────────────────────
    //    Each ring at depth Z is a perfect circle:
    //      centre = (curvature * (1 − Z/maxZ) * 0.25,  0)
    //      radius = depthScale / Z
    //    Near rings shift more (like old Canvas code); far rings stay centred.

    float maxZ      = 12.0;
    float curveAmt  = curvature * 0.25;   // matches Canvas (width/4) in UV space
    float tScroll   = iTime * speed;

    float bestDist  = 1000.0;
    float bestZ     = 1.0;
    vec2  bestCtr   = vec2(0.0);

    for (float n = 0.0; n < 25.0; n += 1.0) {
        float ringN = floor(tScroll) + n;         // ring index
        float z     = ringN - tScroll + 1.0;      // actual depth for this ring
        if (z < 0.05 || z > maxZ) continue;

        float df   = clamp(1.0 - z / maxZ, 0.0, 1.0);
        vec2  ctr  = vec2(curveAmt * df, 0.0);
        float rR   = depthScale / z;
        float d    = abs(length(uv - ctr) - rR);

        if (d < bestDist) {
            bestDist = d;
            bestZ    = z;
            bestCtr  = ctr;
        }
    }

    // ── 4. Angular lines — interpolated centre for smooth radials ───────────
    //    Use straight-line depth as proxy to find which two rings we're between,
    //    then blend their centres so the angular coordinate is continuous.
    float r0      = length(uv);
    float proxyZ  = depthScale / (r0 + 0.001);
    float scrollZ = proxyZ + tScroll;
    float cellFr  = fract(scrollZ);
    float zLo     = floor(scrollZ) - tScroll;
    float zHi     = zLo + 1.0;
    float dfLo    = clamp(1.0 - max(zLo, 0.0) / maxZ, 0.0, 1.0);
    float dfHi    = clamp(1.0 - max(zHi, 0.0) / maxZ, 0.0, 1.0);
    vec2  ctrLo   = vec2(curveAmt * dfLo, 0.0);
    vec2  ctrHi   = vec2(curveAmt * dfHi, 0.0);
    vec2  blendC  = mix(ctrLo, ctrHi, cellFr);

    float angle   = atan((uv - blendC).y, (uv - blendC).x);
    float tunnelA = angle * gridDensity / 3.14159265;
    float distA   = abs(fract(tunnelA) - 0.5) * 2.0;

    // ── 5. Grid lines ──────────────────────────────────────────────────────
    float lwScale = clamp(r0 * 3.0, 0.05, 1.0);
    float lw      = lineWidth * 0.015 * lwScale;

    float ringLine    = 1.0 - smoothstep(0.0, lw, bestDist);
    float angularLine = 1.0 - smoothstep(0.0, lineWidth * 0.08, distA);
    float gridLine    = max(ringLine, angularLine);

    // ── 6. Glow ─────────────────────────────────────────────────────────────
    float glowFalloff = 12.0 / max(glowIntensity, 0.01);
    float glowR = exp(-bestDist * glowFalloff * 25.0);
    float glowA = exp(-distA * glowFalloff);
    float glow  = max(glowR, glowA) * glowIntensity * 0.4;

    // ── 7. Depth fade ───────────────────────────────────────────────────────
    float fade = smoothstep(0.0, 0.06, r0) * smoothstep(0.8, 0.15, r0);

    // ── 8. Combine ──────────────────────────────────────────────────────────
    float intensity = (gridLine + glow) * fade;
    vec3  col   = gridColor * intensity + vec3(gridLine * fade * 0.25);
    float alpha = clamp(intensity, 0.0, 1.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), alpha);
}
