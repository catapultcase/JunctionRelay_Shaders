// Clouds — Volumetric Ray-Marched Cloud Simulation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Volumetric cloudscape via ray marching through a height-bounded cloud slab.
// Camera is positioned BELOW the cloud layer looking upward — this gives the
// dramatic perspective of cumulus seen from below with flat dark bottoms and
// bright billowing tops. Density = height_threshold + FBM_noise where the FBM
// amplitude dominates, creating clear cloud/gap structure. Lighting via
// single-sample directional derivative. Adaptive step size and octave LOD.
//
// Inputs: iChannel0 (background texture), iChannel1 (previous frame feedback)
// Inputs: iResolution, iTime, iFrame
// Params: cloudCoverage, cloudSpeed, windAngle, cloudScale, cloudHeight,
//         sunAngle, sunColor, shadowColor, godRayIntensity, cloudDensity,
//         turbulence

// ── Fast 3D Value Noise ──────────────────────────────────────

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

// ── FBM with LOD ─────────────────────────────────────────────

float fbm5(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q *= 2.02;
    f += 0.25000 * noise3(q); q *= 2.03;
    f += 0.12500 * noise3(q); q *= 2.01;
    f += 0.06250 * noise3(q); q *= 2.02;
    f += 0.03125 * noise3(q);
    return f;
}

float fbm4(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q *= 2.02;
    f += 0.25000 * noise3(q); q *= 2.03;
    f += 0.12500 * noise3(q); q *= 2.01;
    f += 0.06250 * noise3(q);
    return f;
}

float fbm3(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q *= 2.02;
    f += 0.25000 * noise3(q); q *= 2.03;
    f += 0.12500 * noise3(q);
    return f;
}

float fbm2(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q *= 2.02;
    f += 0.25000 * noise3(q);
    return f;
}

// ── Cloud Density ────────────────────────────────────────────
// height_threshold + amplitude * FBM. The FBM amplitude (2.5) is comparable
// to the height range of the slab, so noise creates clear cloud/gap structure
// at every height — not uniform fog.

float mapDensity(vec3 p, int lod) {
    // Wind drift
    float wAngle = windAngle * 6.2832;
    vec3 wind = vec3(cos(wAngle), 0.0, sin(wAngle));
    vec3 q = p - wind * iTime * cloudSpeed * 0.5;

    q *= cloudScale * 1.2;

    float f;
    if (lod >= 5) f = fbm5(q);
    else if (lod >= 4) f = fbm4(q);
    else if (lod >= 3) f = fbm3(q);
    else f = fbm2(q);

    // Turbulence boosts FBM amplitude for more chaotic edges
    f *= (0.7 + turbulence * 0.6);

    // Density: coverage threshold - height + noise
    // Coverage 0.0 → base = -1.5 (mostly clear)
    // Coverage 0.5 → base = 0.0 (half coverage)
    // Coverage 1.0 → base = 1.5 (fully overcast)
    float base = (cloudCoverage - 0.5) * 3.0;

    // Height gradient: density decreases with altitude (flat bottoms, wispy tops)
    // p.y is in slab range [-3, 1], so this subtracts 0.3*(-3 to 1) = -0.9 to 0.3
    float density = base - p.y * 0.3 + 2.5 * f;

    return clamp(density, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    // ── Background texture ───────────────────────────────────
    vec3 bg = texture(iChannel0, uv).rgb;

    // ── Sun direction ────────────────────────────────────────
    float sAngle = sunAngle * 6.2832;
    vec3 sunDir = normalize(vec3(cos(sAngle), 0.4, sin(sAngle)));

    // ── Camera ───────────────────────────────────────────────
    // Below the cloud layer, looking upward into the slab.
    // cloudHeight shifts view: 0 = looking at cloud base, 1 = looking through tops
    vec3 ro = vec3(0.0, -4.0 + cloudHeight * 2.0, -5.0);

    // Ray direction: screen maps to looking upward and forward
    vec3 rd = normalize(vec3(p.x * 0.5, 0.7 + p.y * 0.35, 1.5));

    // ── Slab bounds ──────────────────────────────────────────
    float yBottom = -3.0;
    float yTop = 1.0;

    float tBot = (yBottom - ro.y) / rd.y;
    float tTop = (yTop - ro.y) / rd.y;
    float tMin = min(tBot, tTop);
    float tMax = max(tBot, tTop);
    tMin = max(tMin, 0.0);

    // ── Raymarch ─────────────────────────────────────────────
    vec4 sum = vec4(0.0);

    if (tMin < tMax) {
        float sunDot = clamp(dot(sunDir, rd), 0.0, 1.0);

        // Dither to reduce banding
        float t = tMin + 0.1 * hash(dot(fragCoord, vec2(12.9898, 78.233)));

        for (int i = 0; i < 80; i++) {
            if (t > tMax || sum.a > 0.99) break;

            vec3 pos = ro + t * rd;

            // LOD
            int lod = 5 - int(clamp(log2(1.0 + t * 0.5), 0.0, 3.0));

            float den = mapDensity(pos, lod);

            if (den > 0.01) {
                // Directional derivative lighting (one extra sample toward sun)
                float denSun = mapDensity(pos + 0.3 * sunDir, lod);
                float dif = clamp((den - denSun) / 0.6, 0.0, 1.0);

                // Lighting: ambient shadow color + directional sun
                vec3 lin = shadowColor * 1.1 + sunColor * 1.3 * dif;

                // Forward scattering (silver lining / god rays)
                lin += sunColor * godRayIntensity * 0.5 * pow(sunDot, 5.0);

                // Cloud color: bright edges, dark interiors
                vec3 cloudCol = mix(vec3(1.0, 0.95, 0.85), shadowColor * 1.8, den);
                vec4 col = vec4(cloudCol * lin, den);

                // Depth fog toward background
                col.rgb = mix(col.rgb, bg, 1.0 - exp(-0.002 * t * t));

                // Opacity: cloudDensity controls how solid clouds are
                col.a *= 0.35 * cloudDensity;

                // Front-to-back premultiplied alpha
                col.rgb *= col.a;
                sum += col * (1.0 - sum.a);
            }

            // Adaptive step size
            t += max(0.05, 0.03 * t);
        }
    }

    // ── Composite over background ────────────────────────────
    vec3 col = bg * (1.0 - sum.a) + sum.rgb;

    // Sun glare in cloud gaps
    float sunDotFinal = clamp(dot(sunDir, normalize(vec3(p.x * 0.5, 0.7, 1.5))), 0.0, 1.0);
    col += sunColor * 0.12 * pow(sunDotFinal, 4.0) * (1.0 - sum.a * 0.7);

    // Vignette
    vec2 vc = uv - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.25;

    // Temporal feedback
    float cloudAlpha = sum.a;
    if (iFrame > 0) {
        float prevAlpha = texture(iChannel1, uv).a;
        cloudAlpha = mix(cloudAlpha, prevAlpha, 0.5);
    }

    fragColor = vec4(col, cloudAlpha);
}
