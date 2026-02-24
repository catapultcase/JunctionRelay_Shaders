// Clouds — Volumetric Ray-Marched Cloud Simulation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Volumetric cloudscape via ray marching through a height-bounded cloud slab.
// Density = height plane + FBM noise. Lighting via single-sample directional
// derivative (one extra density lookup toward the sun per step). Adaptive step
// size and octave LOD for performance. Beer-Lambert front-to-back compositing.
// Background texture (iChannel0) shows through gaps.
//
// Inputs: iChannel0 (background texture), iChannel1 (previous frame feedback)
// Inputs: iResolution, iTime, iFrame
// Params: cloudCoverage, cloudSpeed, windAngle, cloudScale, cloudHeight,
//         sunAngle, sunColor, shadowColor, godRayIntensity, cloudDensity,
//         turbulence

// ── Fast 3D Value Noise ──────────────────────────────────────
// sin-hash based — no texture dependency

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

// ── FBM with variable octaves (for LOD) ──────────────────────

float fbm5(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q = q * 2.02;
    f += 0.25000 * noise3(q); q = q * 2.03;
    f += 0.12500 * noise3(q); q = q * 2.01;
    f += 0.06250 * noise3(q); q = q * 2.02;
    f += 0.03125 * noise3(q);
    return f;
}

float fbm4(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q = q * 2.02;
    f += 0.25000 * noise3(q); q = q * 2.03;
    f += 0.12500 * noise3(q); q = q * 2.01;
    f += 0.06250 * noise3(q);
    return f;
}

float fbm3(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q = q * 2.02;
    f += 0.25000 * noise3(q); q = q * 2.03;
    f += 0.12500 * noise3(q);
    return f;
}

float fbm2(vec3 p) {
    vec3 q = p;
    float f;
    f  = 0.50000 * noise3(q); q = q * 2.02;
    f += 0.25000 * noise3(q);
    return f;
}

// ── Cloud Density ────────────────────────────────────────────
// Simple: height plane + FBM. Flat bottoms, billowing tops.
// Coverage shifts the base threshold. Turbulence scales the FBM amplitude.

float mapDensity(vec3 p, int lod) {
    // Wind animation
    float wAngle = windAngle * 6.2832;
    vec3 wind = vec3(cos(wAngle), 0.0, sin(wAngle));
    vec3 q = p - wind * iTime * cloudSpeed * 0.4;

    // Scale the noise space
    q *= cloudScale * 1.5;

    // FBM with LOD
    float f;
    if (lod >= 5) f = fbm5(q);
    else if (lod >= 4) f = fbm4(q);
    else if (lod >= 3) f = fbm3(q);
    else f = fbm2(q);

    // Turbulence scales the noise amplitude
    f *= (0.6 + turbulence * 0.8);

    // Height-based density: flat bottom, billowing tops
    // cloudHeight shifts the slab vertically, cloudCoverage controls fill
    float coverageBoost = cloudCoverage * 3.0;
    float density = coverageBoost - 1.5 - p.y + 1.75 * f;

    return clamp(density, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 p = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    // ── Sun direction (3D) ───────────────────────────────────
    float sAngle = sunAngle * 6.2832;
    vec3 sunDir = normalize(vec3(cos(sAngle), 0.35, sin(sAngle)));

    // ── Camera ───────────────────────────────────────────────
    // Fixed camera looking into the cloud slab from below
    float camY = -1.0 + cloudHeight * 2.0;
    vec3 ro = vec3(0.0, camY, 0.0);
    vec3 rd = normalize(vec3(p.x, p.y * 0.5 + 0.5, 1.5));

    // ── Slab bounds ──────────────────────────────────────────
    float yBottom = -3.0;
    float yTop = 2.0;

    // Intersect ray with bounding planes
    float tBot = (yBottom - ro.y) / rd.y;
    float tTop = (yTop - ro.y) / rd.y;
    float tMin = max(min(tBot, tTop), 0.0);
    float tMax = max(tBot, tTop);

    if (tMin >= tMax) {
        // Miss — show background
        vec3 bg = texture(iChannel0, uv).rgb;
        fragColor = vec4(bg, 0.0);
    }
    else {

    // ── Background texture ───────────────────────────────────
    vec3 bg = texture(iChannel0, uv).rgb;

    // ── Sky gradient (blended behind clouds, in front of bg) ─
    // Warm sky toward sun, cool away
    float sunDot = clamp(dot(sunDir, rd), 0.0, 1.0);

    // ── Raymarch ─────────────────────────────────────────────
    vec4 sum = vec4(0.0);
    float t = tMin;

    // Dither start to reduce banding
    t += 0.05 * hash(dot(fragCoord, vec2(12.9898, 78.233)));

    for (int i = 0; i < 80; i++) {
        if (t > tMax || sum.a > 0.99) break;

        vec3 pos = ro + t * rd;

        // LOD: fewer octaves for distant samples
        int lod = 5 - int(clamp(log2(1.0 + t * 0.5), 0.0, 3.0));

        float den = mapDensity(pos, lod);

        if (den > 0.01) {
            // ── Lighting: one extra sample toward sun ────────
            // Directional derivative — cheap self-shadowing
            float denSun = mapDensity(pos + 0.3 * sunDir, lod);
            float dif = clamp((den - denSun) / 0.6, 0.0, 1.0);

            // Color: lit side = sunColor, shadow side = shadowColor
            vec3 lin = shadowColor * 1.2 + sunColor * dif;

            // Add forward scattering toward sun (god ray / silver lining)
            lin += sunColor * godRayIntensity * pow(sunDot, 4.0) * dif;

            // Cloud base color: bright at edges, darker in dense areas
            vec3 cloudBase = mix(sunColor * 1.1, shadowColor * 1.5, den);
            vec4 col = vec4(cloudBase * lin, den);

            // Depth fog — blend toward background at distance
            col.rgb = mix(col.rgb, bg, 1.0 - exp(-0.003 * t * t));

            // Opacity scaling by cloudDensity uniform
            col.a *= cloudDensity * 0.5;

            // Pre-multiplied alpha compositing (front-to-back)
            col.rgb *= col.a;
            sum += col * (1.0 - sum.a);
        }

        // Adaptive step size — larger steps when far from camera
        t += max(0.06, 0.04 * t);
    }

    // ── Composite ────────────────────────────────────────────
    // Background shows through where clouds are transparent
    vec3 col = bg * (1.0 - sum.a) + sum.rgb;

    // Sun glare through cloud gaps
    col += sunColor * 0.15 * pow(sunDot, 3.0) * (1.0 - sum.a * 0.8);

    // Subtle vignette
    vec2 vc = uv - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.3;

    // ── Temporal feedback ────────────────────────────────────
    float cloudAlpha = sum.a;
    if (iFrame > 0) {
        float prevAlpha = texture(iChannel1, uv).a;
        cloudAlpha = mix(cloudAlpha, prevAlpha, 0.5);
    }

    fragColor = vec4(col, cloudAlpha);

    } // end else (ray hit slab)
}
