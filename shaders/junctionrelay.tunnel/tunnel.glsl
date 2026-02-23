// JR Tunnel — Sci-Fi Retro CGI Tunnel
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural wireframe tunnel — transparent between grid lines.
// Origin sets curve direction; curvature controls arc width.
// Classic polar-to-depth mapping with animated forward motion,
// neon grid lines, soft glow, and optional rotation.
// Single pass, no texture required.
//
// Uniforms: gridColor, speed, gridDensity, lineWidth, glowIntensity,
//           rotationSpeed, curvature, depthScale, depthOffset,
//           originX, originY

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Centre UV, normalise by shortest axis for aspect-correct shape
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);

    // ── 1. Tunnel rotation ────────────────────────────────────────────────────
    float rot = iTime * rotationSpeed;
    float cs  = cos(rot);
    float sn  = sin(rot);
    uv = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);

    // ── 2. Straight tunnel depth ──────────────────────────────────────────────
    // Compute depth from un-displaced UV so rings stay evenly spaced.
    float rStraight = length(uv);
    float depth     = depthScale / (rStraight + 0.001) + depthOffset;

    // ── 3. Curve — shift ring centres by depth (same principle as old Canvas) ─
    // depth is large at centre (far), small at edges (near).
    // depthNorm: 1 at near end (edges), 0 at far end (centre).
    float depthNorm  = clamp(1.0 - depth / 10.0, 0.0, 1.0);
    vec2  ringOffset = vec2(originX, originY) * curvature * depthNorm * 0.3;
    vec2  curvedUV   = uv - ringOffset;

    // ── 4. Angle and local radius from curved centres ─────────────────────────
    float angle  = atan(curvedUV.y, curvedUV.x);
    float radius = length(curvedUV);

    // ── 5. Animated tunnel coordinates (depth from step 2, angle from step 4) ─
    float tunnelZ = depth + iTime * speed;
    float tunnelA = angle * gridDensity / 3.14159265;

    // ── 6. Grid lines — distance to nearest grid edge ─────────────────────────
    float distZ = abs(fract(tunnelZ) - 0.5) * 2.0;   // 0 at line, 1 between
    float distA = abs(fract(tunnelA) - 0.5) * 2.0;

    // Line width scales with radius so lines thin out toward the vanishing point
    float lwScale = clamp(radius * 2.5, 0.1, 1.0);
    float lw = lineWidth * 0.08 * lwScale;

    // Sharp neon edges
    float lineZ = 1.0 - smoothstep(0.0, lw, distZ);
    float lineA = 1.0 - smoothstep(0.0, lw, distA);
    float gridLine = max(lineZ, lineA);

    // ── 7. Soft glow around lines ────────────────────────────────────────────
    float glowFalloff = 12.0 / max(glowIntensity, 0.01);
    float glowZ = exp(-distZ * glowFalloff);
    float glowA = exp(-distA * glowFalloff);
    float glow  = max(glowZ, glowA) * glowIntensity * 0.4;

    // ── 8. Depth-based fade ──────────────────────────────────────────────────
    // Vanishing point (centre) fades to avoid infinite brightness;
    // extreme edges fade to keep the tunnel feeling bounded.
    float fade = smoothstep(0.0, 0.08, radius) * smoothstep(2.5, 0.3, radius);

    // ── 9. Combine line + glow ──────────────────────────────────────────────
    float intensity = (gridLine + glow) * fade;

    // Neon colour with a bright white core on hard line edges
    vec3 col = gridColor * intensity + vec3(gridLine * fade * 0.25);

    // Alpha follows intensity — fully transparent between lines
    float alpha = clamp(intensity, 0.0, 1.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), alpha);
}
