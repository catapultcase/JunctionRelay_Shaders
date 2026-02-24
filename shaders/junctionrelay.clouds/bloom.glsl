// Clouds — Bloom Post-Process (Pass 2)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Star-pattern bloom on sunlit cloud edges from pass 0.
// 4 directions (H, V, 2 diagonals) x 6 taps = 24 reads + 1 center + 1 original = 26.
// Warm tint controlled by bloomWarmth.
// Alpha pass-through.
//
// Inputs: iChannel0 (pass 0 output), iResolution
// Params: bloomThreshold, bloomIntensity, bloomSpread, bloomWarmth

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 original = texture(iChannel0, uv);
    vec3 col = original.rgb;

    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float brightness = max(lum - bloomThreshold, 0.0);
    vec3 bright = col * (brightness / max(lum, 0.001));

    vec2 px = 1.0 / iResolution.xy;
    vec3 bloom = vec3(0.0);

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

    vec3 warmTint = mix(vec3(1.0), vec3(1.08, 1.02, 0.94), bloomWarmth);
    bloom *= warmTint;

    vec3 result = col + bloom * bloomIntensity;

    fragColor = vec4(result, original.a);
}
