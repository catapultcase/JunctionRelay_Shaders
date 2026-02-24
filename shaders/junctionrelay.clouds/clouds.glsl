// Clouds — Proof of Concept: One Volumetric Cloud (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// ONE cloud: a noisy sphere ray-marched with directional derivative lighting.
// Proves the volumetric concept before expanding to a full cloudscape.
//
// Technique: ray march through bounding sphere, density = sphere SDF + FBM,
// lighting = one extra density sample toward sun (directional derivative).

// ── Noise ────────────────────────────────────────────────────

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float noise3(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;
    return mix(mix(mix(hash(n +   0.0), hash(n +   1.0), f.x),
                   mix(hash(n +  57.0), hash(n +  58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    float f;
    f  = 0.5000 * noise3(p); p *= 2.02;
    f += 0.2500 * noise3(p); p *= 2.03;
    f += 0.1250 * noise3(p); p *= 2.01;
    f += 0.0625 * noise3(p);
    return f;
}

// ── Cloud Density ────────────────────────────────────────────
// Sphere SDF + FBM = cloud shape. Positive inside, zero outside.

float cloudDen(vec3 p) {
    float sphere = 1.0 - length(p);
    float n = fbm(p * 3.0 + vec3(0.0, 0.0, iTime * 0.1));
    return clamp(sphere + n * 1.5 - 0.5, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    // Sky gradient background (no texture needed for POC)
    vec3 bg = vec3(0.6, 0.71, 0.75) - vec2(p.y * 0.2, p.y * 0.1).xyy;

    // Camera: 3 units back, looking at origin
    vec3 ro = vec3(0.0, 0.0, -3.0);
    vec3 rd = normalize(vec3(p, 2.0));

    // Sun direction (upper right)
    vec3 sun = normalize(vec3(1.0, 0.5, -0.5));

    // Ray-sphere intersection (bounding sphere radius 2.0)
    float b = dot(ro, rd);
    float c = dot(ro, ro) - 4.0;
    float h = b * b - c;

    vec4 sum = vec4(0.0);

    if (h > 0.0) {
        float sq = sqrt(h);
        float tNear = max(-b - sq, 0.0);
        float tFar = -b + sq;

        float dt = (tFar - tNear) / 40.0;
        float t = tNear + dt * 0.5;

        for (int i = 0; i < 40; i++) {
            if (sum.a > 0.99) break;

            vec3 pos = ro + t * rd;
            float den = cloudDen(pos);

            if (den > 0.01) {
                // One sample toward sun for lighting
                float denSun = cloudDen(pos + sun * 0.3);
                float dif = clamp((den - denSun) / 0.6, 0.0, 1.0);

                // Ambient + directional
                vec3 lin = vec3(0.55, 0.6, 0.7) + vec3(1.0, 0.8, 0.5) * dif;

                // Cloud color: bright cream at edges, grey-blue in dense core
                vec3 baseCol = mix(vec3(1.0, 0.95, 0.85), vec3(0.3, 0.35, 0.45), den);
                vec4 col = vec4(baseCol * lin, den);

                // Opacity per step
                col.a *= 0.5;

                // Premultiplied alpha front-to-back
                col.rgb *= col.a;
                sum += col * (1.0 - sum.a);
            }

            t += dt;
        }
    }

    // Composite cloud over background
    vec3 col = bg * (1.0 - sum.a) + sum.rgb;

    fragColor = vec4(col, sum.a);
}
