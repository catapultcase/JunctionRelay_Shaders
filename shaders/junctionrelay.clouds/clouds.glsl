// Clouds — Flying Over a Cloud Plane (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Camera above a cloud plane, looking down at an angle — flying over clouds.
// Density = height threshold + FBM. Flat bottoms, billowing tops.
// Each cloud formation is different because FBM varies across the xz plane.
// Directional derivative lighting (one extra sample toward sun per step).

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

float fbm5(vec3 p) {
    float f;
    f  = 0.5000 * noise3(p); p *= 2.02;
    f += 0.2500 * noise3(p); p *= 2.03;
    f += 0.1250 * noise3(p); p *= 2.01;
    f += 0.0625 * noise3(p); p *= 2.02;
    f += 0.03125 * noise3(p);
    return f;
}

float fbm4(vec3 p) {
    float f;
    f  = 0.5000 * noise3(p); p *= 2.02;
    f += 0.2500 * noise3(p); p *= 2.03;
    f += 0.1250 * noise3(p); p *= 2.01;
    f += 0.0625 * noise3(p);
    return f;
}

float fbm3(vec3 p) {
    float f;
    f  = 0.5000 * noise3(p); p *= 2.02;
    f += 0.2500 * noise3(p); p *= 2.03;
    f += 0.1250 * noise3(p);
    return f;
}

// ── Cloud Density ────────────────────────────────────────────
// height threshold + FBM. Clouds exist where density > 0.
// p.y increasing = higher altitude = less density (cloud tops are wispy).

float mapCloud(vec3 p, int lod) {
    vec3 q = p + vec3(iTime * 0.3, 0.0, iTime * 0.1);

    float f;
    if (lod >= 5) f = fbm5(q);
    else if (lod >= 4) f = fbm4(q);
    else f = fbm3(q);

    // Density: 0.2 - height + noise * 3
    // At cloud base (y ~ -3): 0.2 + 3 + 3*f = always dense
    // At cloud top (y ~ 0.6): 0.2 - 0.6 + 3*f = only where fbm > 0.13
    // FBM range ~0-0.97, so 3*f ~ 0-2.9 → strong variation at cloud tops
    float den = 0.2 - p.y + 3.0 * f;

    return clamp(den, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    // Sun
    vec3 sunDir = normalize(vec3(-0.7, 0.0, -0.7));

    // Camera: above the clouds, looking down at an angle
    vec3 ro = vec3(0.0, 1.5, -5.0 + iTime * 0.5);
    vec3 ta = vec3(0.0, -0.5, ro.z + 5.0);

    // Simple look-at camera matrix
    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(vec3(0.0, 1.0, 0.0), cw));
    vec3 cv = cross(cw, cu);
    vec3 rd = normalize(p.x * cu + p.y * cv + 1.5 * cw);

    // Sky background
    float sunDot = clamp(dot(sunDir, rd), 0.0, 1.0);
    vec3 sky = vec3(0.6, 0.71, 0.75) - rd.y * 0.2 * vec3(1.0, 0.5, 1.0) + 0.15 * 0.5;
    sky += 0.2 * vec3(1.0, 0.6, 0.1) * pow(sunDot, 8.0);

    // Slab bounds
    float yBot = -3.0;
    float yTop = 0.6;
    float tBot = (yBot - ro.y) / rd.y;
    float tTop = (yTop - ro.y) / rd.y;

    float tMin = min(tBot, tTop);
    float tMax = max(tBot, tTop);
    tMin = max(tMin, 0.0);

    vec4 sum = vec4(0.0);

    if (tMin < tMax && tMax > 0.0) {
        // Dither
        float t = tMin + 0.1 * hash(dot(fragCoord, vec2(12.9898, 78.233)));

        for (int i = 0; i < 64; i++) {
            if (t > tMax || sum.a > 0.99) break;

            float dt = max(0.05, 0.02 * t);
            vec3 pos = ro + t * rd;

            // LOD
            int lod = 5 - int(clamp(log2(1.0 + t * 0.5), 0.0, 2.0));

            float den = mapCloud(pos, lod);

            if (den > 0.01) {
                // Directional derivative lighting
                float denSun = mapCloud(pos + 0.3 * sunDir, lod);
                float dif = clamp((den - denSun) / 0.25, 0.0, 1.0);

                vec3 lin = vec3(0.65, 0.65, 0.75) * 1.1 + 0.8 * vec3(1.0, 0.6, 0.3) * dif;
                vec4 col = vec4(mix(vec3(1.0, 0.93, 0.84), vec3(0.25, 0.3, 0.4), den), den);
                col.xyz *= lin;

                // Fog at distance
                col.rgb = mix(col.rgb, sky, 1.0 - exp(-0.1 * t));

                // Opacity
                col.a = min(col.a * 8.0 * dt, 1.0);

                // Front-to-back premultiplied
                col.rgb *= col.a;
                sum += col * (1.0 - sum.a);
            }

            t += dt;
        }
    }

    // Composite
    vec3 col = sky * (1.0 - sum.a) + sum.rgb;

    // Sun glare
    col += vec3(0.2, 0.08, 0.04) * pow(sunDot, 3.0);

    fragColor = vec4(col, 1.0);
}
