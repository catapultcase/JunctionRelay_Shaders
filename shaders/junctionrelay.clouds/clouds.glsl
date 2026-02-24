// Clouds — Volumetric Ray-Marched Cloud Simulation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Volumetric cloudscape via ray marching through a 3D FBM noise slab.
// Each pixel casts a ray from a virtual camera into a cloud layer defined
// between two altitude planes. The ray accumulates density (Beer-Lambert
// absorption) and at each sample point, a secondary light march toward the
// sun computes self-shadowing. Henyey-Greenstein phase function gives bright
// silver-lining edges when looking toward the sun.
//
// The background texture (iChannel0) is composited behind the clouds.
// Temporal feedback (iChannel1) smooths cloud evolution frame-to-frame.
//
// Inputs: iChannel0 (background texture), iChannel1 (previous frame feedback)
// Inputs: iResolution, iTime, iFrame
// Params: cloudCoverage, cloudSpeed, windAngle, cloudScale, cloudHeight,
//         sunAngle, sunColor, shadowColor, godRayIntensity, cloudDensity,
//         turbulence

// ── Hash / Noise ─────────────────────────────────────────────

float hash3(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash3(i);
    float n100 = hash3(i + vec3(1, 0, 0));
    float n010 = hash3(i + vec3(0, 1, 0));
    float n110 = hash3(i + vec3(1, 1, 0));
    float n001 = hash3(i + vec3(0, 0, 1));
    float n101 = hash3(i + vec3(1, 0, 1));
    float n011 = hash3(i + vec3(0, 1, 1));
    float n111 = hash3(i + vec3(1, 1, 1));

    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);

    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);

    return mix(nxy0, nxy1, f.z);
}

// ── 3D FBM ───────────────────────────────────────────────────

float fbm3(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    float f = 1.0;
    for (int i = 0; i < 5; i++) {
        v += a * noise3(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return v;
}

// ── Cloud Density at 3D Point ────────────────────────────────
// Returns raw density [0,1] for a world-space position inside the slab.
// Coverage controls the threshold, turbulence adds domain warping.

float cloudField(vec3 p, float coverage, float turb, float evolve) {
    // Domain warp for organic shapes — evolve offsets morph the warp over time
    vec3 warp = vec3(
        fbm3(p + vec3(0.0, 0.0, evolve * 0.37)),
        fbm3(p + vec3(5.2, 1.3, 2.8 + evolve * 0.29)),
        fbm3(p + vec3(2.1 + evolve * 0.23, 7.3, 4.1))
    );
    vec3 wp = p + warp * turb * 1.5;

    // Evolve the main noise field — clouds change shape over time
    float n = fbm3(wp + vec3(0.0, evolve * 0.17, 0.0));

    // Coverage threshold
    float threshold = 1.0 - coverage;
    float d = smoothstep(threshold, threshold + 0.25, n);

    return d;
}

// ── Slab Intersection ────────────────────────────────────────
// Ray-slab intersection for cloud layer between yBottom and yTop.
// Returns (tNear, tFar) or (-1,-1) if no intersection.

vec2 slabIntersect(vec3 ro, vec3 rd, float yBottom, float yTop) {
    float tBot = (yBottom - ro.y) / rd.y;
    float tTop = (yTop - ro.y) / rd.y;

    float tNear = min(tBot, tTop);
    float tFar  = max(tBot, tTop);

    tNear = max(tNear, 0.0);
    if (tNear >= tFar) return vec2(-1.0);
    return vec2(tNear, tFar);
}

// ── Light March ──────────────────────────────────────────────
// March from a point toward the sun to compute optical depth (shadow).

float lightMarch(vec3 p, vec3 lightDir, float coverage, float turb,
                 float yTop, float evolve) {
    float opticalDepth = 0.0;
    float stepLen = (yTop - p.y) / max(lightDir.y, 0.05) / 4.0;
    stepLen = min(stepLen, 0.6);

    for (int i = 0; i < 4; i++) {
        p += lightDir * stepLen;
        float d = cloudField(p, coverage, turb, evolve);
        opticalDepth += d * stepLen;
    }

    return opticalDepth;
}

// ── Henyey-Greenstein Phase Function ─────────────────────────
// Controls forward/backward scattering. g > 0 = forward (silver lining).

float hg(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * 3.14159 * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    float t = iTime;

    // ── Wind & sun direction (3D) ────────────────────────────
    float wAngle = windAngle * 6.2832;
    vec3 wind = vec3(cos(wAngle), 0.0, sin(wAngle));

    float sAngle = sunAngle * 6.2832;
    // Sun is above the cloud layer, direction points toward sun
    vec3 lightDir = normalize(vec3(cos(sAngle), 0.6, sin(sAngle)));

    // ── Camera setup ─────────────────────────────────────────
    // Camera looks forward into the cloud slab from below
    vec3 ro = vec3(0.0, 0.5, 0.0);
    // Screen-space ray direction
    vec2 screen = (uv - 0.5) * vec2(aspect, 1.0);
    vec3 rd = normalize(vec3(screen.x, screen.y * 0.6 + 0.3, 1.0));

    // ── Cloud slab bounds ────────────────────────────────────
    float yBottom = 1.0 + cloudHeight * 1.0;
    float yTop = yBottom + 2.0;

    vec2 tRange = slabIntersect(ro, rd, yBottom, yTop);

    // ── Background texture ───────────────────────────────────
    vec3 bg = texture(iChannel0, uv).rgb;

    if (tRange.x < 0.0) {
        // Ray misses the cloud slab entirely — show background
        fragColor = vec4(bg, 0.0);
        return;
    }

    // ── Ray march parameters ─────────────────────────────────
    float speed = cloudSpeed * 0.3;
    float scale = cloudScale * 2.0;
    float marchLen = tRange.y - tRange.x;
    int steps = 32;
    float stepLen = marchLen / float(steps);

    // Shape evolution — clouds morph over time (independent of wind drift)
    float evolve = t * speed * 0.5;

    // Phase function: dot(viewDir, lightDir) for silver lining
    float cosTheta = dot(rd, lightDir);
    float phase = mix(hg(cosTheta, 0.6), hg(cosTheta, -0.3), 0.2);

    // ── Volumetric accumulation ──────────────────────────────
    float transmittance = 1.0;
    vec3 scatteredLight = vec3(0.0);
    float totalOpticalDepth = 0.0;

    float absorption = 1.0 + cloudDensity * 3.0;

    for (int i = 0; i < 32; i++) {
        float tCur = tRange.x + (float(i) + 0.5) * stepLen;
        vec3 pos = ro + rd * tCur;

        // Animate with wind drift + shape evolution
        vec3 samplePos = pos * scale + wind * t * speed;

        // Density at this 3D point (evolve morphs shapes over time)
        float d = cloudField(samplePos, cloudCoverage, turbulence, evolve);

        if (d > 0.01) {
            // ── Light march for self-shadowing ───────────────
            float lightOD = lightMarch(samplePos, lightDir, cloudCoverage,
                                       turbulence, yTop * scale, evolve);
            float lightTransmit = exp(-lightOD * absorption * 0.8);

            // ── Coloring ─────────────────────────────────────
            // Lit portions get sunColor, shadowed get shadowColor
            vec3 litCol = sunColor * lightTransmit;
            vec3 ambCol = shadowColor * 0.3;
            vec3 sampleColor = litCol + ambCol;

            // Add phase-function scattering (silver lining / god ray glow)
            sampleColor += sunColor * phase * lightTransmit * godRayIntensity;

            // ── Beer-Lambert absorption ──────────────────────
            float sampleOD = d * stepLen * absorption;
            float sampleTransmit = exp(-sampleOD);

            // Energy-conserving integration
            vec3 integScatter = sampleColor * (1.0 - sampleTransmit);
            scatteredLight += transmittance * integScatter;
            transmittance *= sampleTransmit;

            totalOpticalDepth += d * stepLen;

            // Early exit if fully opaque
            if (transmittance < 0.01) break;
        }
    }

    // ── Composite over background ────────────────────────────
    vec3 col = bg * transmittance + scatteredLight;

    // Subtle vignette
    vec2 vc = uv - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.3;

    // ── Temporal feedback ────────────────────────────────────
    float cloudAlpha = 1.0 - transmittance;
    if (iFrame > 0) {
        float prevAlpha = texture(iChannel1, uv).a;
        cloudAlpha = mix(cloudAlpha, prevAlpha, 0.7);
    }

    fragColor = vec4(col, cloudAlpha);
}
