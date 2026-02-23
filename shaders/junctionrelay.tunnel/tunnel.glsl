// JR Tunnel — Sci-Fi Retro CGI Tunnel
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural wireframe tunnel — transparent between grid lines.
// Cross-section blends from square to circle via curvature uniform.
// Classic polar-to-depth mapping with animated forward motion,
// neon grid lines, soft glow, and optional rotation.
// Single pass, no texture required.
//
// Uniforms: gridColor, speed, gridDensity, lineWidth, glowIntensity,
//           rotationSpeed, curvature, depthScale, depthOffset

// ── Main ─────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Centre UV, normalise by shortest axis for aspect-correct shape
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);

    // ── 1. Tunnel rotation ───────────────────────────────────────────────────
    float rot = iTime * rotationSpeed;
    float cs  = cos(rot);
    float sn  = sin(rot);
    uv = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);

    // ── 2. Cross-section shape ───────────────────────────────────────────────
    // Blend between Chebyshev distance (square) and Euclidean distance (circle).
    // curvature 0 = perfect square, 1 = perfect circle.
    float angle    = atan(uv.y, uv.x);
    float circleR  = length(uv);
    float squareR  = max(abs(uv.x), abs(uv.y));
    float radius   = mix(squareR, circleR, curvature);

    // ── 3. Tunnel mapping — depth = scale / radius ───────────────────────────
    // depthScale controls how deep the corridor stretches.
    // depthOffset shifts the camera start position along the tunnel.
    float depth = depthScale / (radius + 0.001) + depthOffset;

    // ── 4. Animated tunnel coordinates ───────────────────────────────────────
    float tunnelZ = depth + iTime * speed;
    float tunnelA = angle * gridDensity / 3.14159265;

    // ── 5. Grid lines — distance to nearest grid edge ────────────────────────
    float distZ = abs(fract(tunnelZ) - 0.5) * 2.0;   // 0 at line, 1 between
    float distA = abs(fract(tunnelA) - 0.5) * 2.0;

    // Line width scales with radius so lines thin out toward the vanishing point
    float lwScale = clamp(radius * 2.5, 0.1, 1.0);
    float lw = lineWidth * 0.08 * lwScale;

    // Sharp neon edges
    float lineZ = 1.0 - smoothstep(0.0, lw, distZ);
    float lineA = 1.0 - smoothstep(0.0, lw, distA);
    float gridLine = max(lineZ, lineA);

    // ── 6. Soft glow around lines ────────────────────────────────────────────
    float glowFalloff = 12.0 / max(glowIntensity, 0.01);
    float glowZ = exp(-distZ * glowFalloff);
    float glowA = exp(-distA * glowFalloff);
    float glow  = max(glowZ, glowA) * glowIntensity * 0.4;

    // ── 7. Depth-based fade ──────────────────────────────────────────────────
    // Vanishing point (centre) fades to avoid infinite brightness;
    // extreme edges fade to keep the tunnel feeling bounded.
    float fade = smoothstep(0.0, 0.08, radius) * smoothstep(2.5, 0.3, radius);

    // ── 8. Combine line + glow ───────────────────────────────────────────────
    float intensity = (gridLine + glow) * fade;

    // Neon colour with a bright white core on hard line edges
    vec3 col = gridColor * intensity + vec3(gridLine * fade * 0.25);

    // Alpha follows intensity — fully transparent between lines
    float alpha = clamp(intensity, 0.0, 1.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), alpha);
}
