// Rain Window — Bloom Post-Process (Pass 1)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Star-pattern bloom on specular highlights from pass 0 (rain simulation).
// 4 directions (H, V, 2 diagonals) x 6 taps = 24 reads + 1 center + 1 original = 26.
// Warm tint controlled by bloomWarmth — light through water absorbs blue.
// Additive composite at bloomIntensity strength.
// Alpha pass-through: preserves clearing state from pass 0 for feedback.
//
// Inputs: iChannel0 (pass 0 output), iResolution
// Custom params: bloomThreshold, bloomIntensity, bloomSpread, bloomWarmth

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 original = texture(iChannel0, uv);
    vec3 col = original.rgb;

    // Luminance threshold — extract bright specular highlights
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float brightness = max(lum - bloomThreshold, 0.0);
    vec3 bright = col * (brightness / max(lum, 0.001));

    // Star-pattern bloom: 4 directions x 6 taps
    vec2 px = 1.0 / iResolution.xy;
    vec3 bloom = vec3(0.0);

    // Direction vectors: horizontal, vertical, 2 diagonals
    vec2 dirs[4];
    dirs[0] = vec2(1.0, 0.0);
    dirs[1] = vec2(0.0, 1.0);
    dirs[2] = vec2(0.707, 0.707);
    dirs[3] = vec2(0.707, -0.707);

    for (int d = 0; d < 4; d++) {
        vec2 dir = dirs[d] * px;
        for (int i = 1; i <= 6; i++) {
            float fi = float(i);
            float weight = 1.0 / (1.0 + fi * 0.8);
            vec2 offset = dir * fi * bloomSpread;

            vec3 s1 = texture(iChannel0, uv + offset).rgb;
            vec3 s2 = texture(iChannel0, uv - offset).rgb;

            float l1 = dot(s1, vec3(0.299, 0.587, 0.114));
            float l2 = dot(s2, vec3(0.299, 0.587, 0.114));

            bloom += s1 * max(l1 - bloomThreshold, 0.0) * weight;
            bloom += s2 * max(l2 - bloomThreshold, 0.0) * weight;
        }
    }

    bloom /= 24.0;

    // Warm tint — interpolate from neutral (1,1,1) to warm (1.08, 1.02, 0.94)
    vec3 warmTint = mix(vec3(1.0), vec3(1.08, 1.02, 0.94), bloomWarmth);
    bloom *= warmTint;

    // Additive composite at configurable intensity
    vec3 result = col + bloom * bloomIntensity;

    // Pass through alpha from pass 0 (clearing state for temporal feedback).
    // The pipeline forces alpha=1.0 when opaque=true (manifest field).
    fragColor = vec4(result, original.a);
}
