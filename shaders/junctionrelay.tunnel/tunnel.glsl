// JR Tunnel — Sci-Fi Retro CGI Tunnel
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural wireframe tunnel — transparent between grid lines.
// Path bends like a pipe via curvature uniform.
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

    // ── 1. Shift vanishing point ─────────────────────────────────────────────
    // originX/originY move where the tunnel recedes to on screen.
    uv -= vec2(originX, originY);

    // ── 2. Tunnel rotation ──────────────────────────────────────────────────
    float rot = iTime * rotationSpeed;
    float cs  = cos(rot);
    float sn  = sin(rot);
    uv = vec2(uv.x * cs - uv.y * sn, uv.x * sn + uv.y * cs);

    // ── 3. Preliminary depth for curvature calculation ───────────────────────
    float r0 = length(uv);
    float d0 = depthScale / (r0 + 0.001);

    // ── 4. Path curvature — bend the tunnel like a pipe ────────────────────
    // Displace the UV centre based on depth so the tunnel traces a curved path.
    // curvature 0 = dead straight, 1 = strongly bent.
    uv.x += curvature * sin(d0 * 0.8 + iTime * speed * 0.5) * 0.3;
    uv.y += curvature * cos(d0 * 0.6 + iTime * speed * 0.3) * 0.2;

    // ── 5. Tunnel mapping from bent UV ─────────────────────────────────────
    float angle  = atan(uv.y, uv.x);
    float radius = length(uv);
    float depth  = depthScale / (radius + 0.001) + depthOffset;

    // ── 6. Animated tunnel coordinates ─────────────────────────────────────
    float tunnelZ = depth + iTime * speed;
    float tunnelA = angle * gridDensity / 3.14159265;

    // ── 7. Grid lines — distance to nearest grid edge ────────────────────────
    float distZ = abs(fract(tunnelZ) - 0.5) * 2.0;   // 0 at line, 1 between
    float distA = abs(fract(tunnelA) - 0.5) * 2.0;

    // Line width scales with radius so lines thin out toward the vanishing point
    float lwScale = clamp(radius * 2.5, 0.1, 1.0);
    float lw = lineWidth * 0.08 * lwScale;

    // Sharp neon edges
    float lineZ = 1.0 - smoothstep(0.0, lw, distZ);
    float lineA = 1.0 - smoothstep(0.0, lw, distA);
    float gridLine = max(lineZ, lineA);

    // ── 8. Soft glow around lines ────────────────────────────────────────────
    float glowFalloff = 12.0 / max(glowIntensity, 0.01);
    float glowZ = exp(-distZ * glowFalloff);
    float glowA = exp(-distA * glowFalloff);
    float glow  = max(glowZ, glowA) * glowIntensity * 0.4;

    // ── 9. Depth-based fade ──────────────────────────────────────────────────
    // Vanishing point (centre) fades to avoid infinite brightness;
    // extreme edges fade to keep the tunnel feeling bounded.
    float fade = smoothstep(0.0, 0.08, radius) * smoothstep(2.5, 0.3, radius);

    // ── 10. Combine line + glow ──────────────────────────────────────────────
    float intensity = (gridLine + glow) * fade;

    // Neon colour with a bright white core on hard line edges
    vec3 col = gridColor * intensity + vec3(gridLine * fade * 0.25);

    // Alpha follows intensity — fully transparent between lines
    float alpha = clamp(intensity, 0.0, 1.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), alpha);
}
