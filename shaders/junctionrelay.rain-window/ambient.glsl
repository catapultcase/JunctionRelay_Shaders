// Rain Window — Ambient Light Post-Process (Pass 2: Lighting)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Scene-wide lighting, directional gradient, atmospheric haze, and exposure.
// At all defaults (white colors, 0 intensities, 0 exposure) output = input.
// Alpha pass-through: preserves clearing state from pass 0 for feedback.
//
// Inputs: iChannel0 (pass 1 output), iResolution
// Params: lightColor, lightIntensity, lightAngle, lightFocus,
//         atmosphereColor, atmosphereDensity, exposure

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 original = texture(iChannel0, uv);
    vec3 col = original.rgb;

    // ── Exposure ──────────────────────────────────────────────
    // EV-style: each +1.0 doubles brightness, each -1.0 halves it
    col *= pow(2.0, exposure);

    // ── Directional light gradient ───────────────────────────
    // lightAngle maps 0..1 to 0..2pi (full rotation)
    // lightFocus controls how much the gradient affects the scene
    float angle = lightAngle * 6.2832;
    vec2 lightDir = vec2(cos(angle), sin(angle));
    vec2 centered = uv - 0.5;
    // Project screen position onto light direction: 0=shadow side, 1=lit side
    float gradient = dot(centered, lightDir) + 0.5;
    gradient = clamp(gradient, 0.0, 1.0);
    // Mix between even (1.0 everywhere) and directional gradient
    float directional = mix(1.0, gradient, lightFocus);

    // ── Ambient light tint ───────────────────────────────────
    // Colored light filtering: col * lightColor removes wavelengths
    // the light source doesn't emit (physically correct colored lighting)
    vec3 lit = col * lightColor * directional;
    col = mix(col, lit, lightIntensity);

    // ── Atmospheric haze ─────────────────────────────────────
    // Colored fog/haze — denser toward edges (vignette-shaped depth proxy)
    float depth = length(centered) * 1.4;  // 0 at center, ~1 at corners
    float haze = atmosphereDensity * (0.3 + depth * 0.7);
    col = mix(col, atmosphereColor * 0.5, haze);

    // Preserve alpha (temporal clearing state for feedback)
    fragColor = vec4(col, original.a);
}
