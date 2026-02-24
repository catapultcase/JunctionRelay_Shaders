// Clouds — Flying Over a Cloud Plane (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Camera above a cloud plane, looking down at an angle — flying over clouds.
// Density = height falloff + FBM noise. Flat bottoms, billowing tops.
// Directional derivative lighting (one extra density sample toward sun).
//
// Uniforms: sunAngle, sunColor, shadowColor, skyColor, cloudCoverage, cloudSpeed, cloudSparseness

// ── 3D Hash ──────────────────────────────────────────────────
// Dot-product hash — no sin(), fully integer-inspired constants.

float hash3(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// ── 3D Value Noise ───────────────────────────────────────────
// Trilinear interpolation of hashed lattice corners.

float vnoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
            mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
        mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
            mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
        f.z);
}

// ── Fractional Brownian Motion ───────────────────────────────
// 5 octaves with slight frequency jitter to break grid alignment.
// Separate functions for LOD — fewer octaves at distance.

float fbm5(vec3 p) {
    float v = 0.0;
    v += 0.500 * vnoise(p); p *= 1.97;
    v += 0.250 * vnoise(p); p *= 2.06;
    v += 0.125 * vnoise(p); p *= 1.94;
    v += 0.063 * vnoise(p); p *= 2.11;
    v += 0.031 * vnoise(p);
    return v;
}

float fbm4(vec3 p) {
    float v = 0.0;
    v += 0.500 * vnoise(p); p *= 1.97;
    v += 0.250 * vnoise(p); p *= 2.06;
    v += 0.125 * vnoise(p); p *= 1.94;
    v += 0.063 * vnoise(p);
    return v;
}

float fbm3(vec3 p) {
    float v = 0.0;
    v += 0.500 * vnoise(p); p *= 1.97;
    v += 0.250 * vnoise(p); p *= 2.06;
    v += 0.125 * vnoise(p);
    return v;
}

// ── Cloud Density ────────────────────────────────────────────
// Altitude-based falloff + FBM gives flat bottoms, billowing tops.
// cloudCoverage shifts the threshold, cloudSpeed drives wind drift.

float mapCloud(vec3 p, int lod) {
    vec3 q = p + vec3(iTime * cloudSpeed * 0.6, 0.0, iTime * cloudSpeed * 0.2);
    q /= cloudSparseness;

    float f;
    if (lod >= 5) f = fbm5(q);
    else if (lod >= 4) f = fbm4(q);
    else f = fbm3(q);

    // Coverage: 0→scattered, 0.5→half sky, 1→overcast
    // Sparseness tightens the threshold so only the tallest noise peaks survive
    float sparseTighten = (cloudSparseness - 1.0) * 0.6;
    float threshold = (cloudCoverage - 0.5) * 3.0 - sparseTighten;

    // Density decreases with altitude — noise amplitude dominates at cloud tops
    float den = threshold - p.y * 0.8 + 3.5 * f;

    return clamp(den, 0.0, 1.0);
}

// ── Dither Hash ──────────────────────────────────────────────

float screenHash(vec2 co) {
    return fract(dot(sin(co * vec2(43.47, 73.19)), vec2(413.7, 297.1)));
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    // Sun direction from uniform
    float sAngle = sunAngle * 6.2832;
    vec3 sunDir = normalize(vec3(cos(sAngle), 0.0, sin(sAngle)));

    // Camera — flies forward at cloudSpeed
    vec3 ro = vec3(0.0, 4.0, -5.0 + iTime * cloudSpeed * 0.8);
    vec3 ta = vec3(0.0, 0.5, ro.z + 8.0);

    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(vec3(0.0, 1.0, 0.0), cw));
    vec3 cv = cross(cw, cu);
    vec3 rd = normalize(p.x * cu + p.y * cv + 1.5 * cw);

    // Sky — neutral gradient with sun glow
    float sunDot = clamp(dot(sunDir, rd), 0.0, 1.0);
    vec3 sky = skyColor;
    sky -= rd.y * 0.15 * vec3(0.8, 0.4, 0.8);
    sky += 0.1;
    sky += 0.25 * sunColor * pow(sunDot, 8.0);

    // Slab
    float yBot = -3.0;
    float yTop = 3.0;
    float tBot = (yBot - ro.y) / rd.y;
    float tTop = (yTop - ro.y) / rd.y;
    float tMin = max(min(tBot, tTop), 0.0);
    float tMax = max(tBot, tTop);

    vec4 sum = vec4(0.0);

    if (tMin < tMax && tMax > 0.0) {
        // Dither start to break banding
        float t = tMin + 0.1 * screenHash(fragCoord);

        for (int i = 0; i < 80; i++) {
            if (t > tMax || sum.a > 0.99) break;

            float dt = max(0.05, 0.02 * t);
            vec3 pos = ro + t * rd;

            // LOD: fewer octaves for distant samples
            int lod = 5 - int(clamp(log2(1.0 + t * 0.5), 0.0, 2.0));

            float den = mapCloud(pos, lod);

            if (den > 0.01) {
                // Directional derivative: one sample toward sun
                float denLit = mapCloud(pos + 0.4 * sunDir, lod);
                float dif = clamp((den - denLit) / 0.35, 0.0, 1.0);

                // Lighting: blend shadow → sun based on directional derivative
                vec3 lin = mix(shadowColor * 2.0, sunColor * 1.5, dif);

                // Cloud surface: neutral white/grey, lighting provides color
                vec3 cloudBase = mix(vec3(1.0, 0.97, 0.93), vec3(0.82, 0.82, 0.86), den);
                vec4 col = vec4(cloudBase * lin, den);

                // Distance fog
                col.rgb = mix(col.rgb, sky, 1.0 - exp(-0.05 * t));

                // Opacity per step
                col.a = min(col.a * 8.0 * dt, 1.0);

                // Front-to-back premultiplied alpha
                col.rgb *= col.a;
                sum += col * (1.0 - sum.a);
            }

            t += dt;
        }
    }

    vec3 col = sky * (1.0 - sum.a) + sum.rgb;

    // Sun glare
    col += sunColor * 0.15 * pow(sunDot, 3.0);

    fragColor = vec4(col, 1.0);
}
