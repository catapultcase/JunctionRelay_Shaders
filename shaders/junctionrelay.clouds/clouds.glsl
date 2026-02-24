// Clouds — Procedural Cloud Simulation (Pass 0)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Procedural cloudscape with layered FBM noise, domain warping, volumetric
// self-shadowing, and god rays over a background texture.
//
// 3 cloud layers at different depths with parallax offset:
//   Far  — high, thin cirrus-like wisps (slow drift)
//   Mid  — main cumulus volume (medium drift)
//   Near — low, thick cloud bottoms (faster drift, darker)
//
// Self-shadowing: march toward sun through noise field for light occlusion.
// God rays: light scattering through cloud gaps along sun direction.
// Temporal feedback: alpha channel stores cloud density for smooth evolution.
//
// Inputs: iChannel0 (background texture), iChannel1 (previous frame feedback)
// Inputs: iResolution, iTime, iFrame
// Params: cloudCoverage, cloudSpeed, windAngle, cloudScale, cloudHeight,
//         sunAngle, sunColor, shadowColor, godRayIntensity, cloudDensity,
//         turbulence

// ── Hash / Noise ─────────────────────────────────────────────

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Fractional Brownian Motion ───────────────────────────────

float fbm(vec2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < 7; i++) {
        if (i >= octaves) break;
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// ── Domain-Warped FBM ────────────────────────────────────────
// Feed FBM output back into itself for organic, churning motion

float warpedFbm(vec2 p, float warpAmount, float t) {
    vec2 q = vec2(
        fbm(p + vec2(0.0, 0.0), 5),
        fbm(p + vec2(5.2, 1.3), 5)
    );

    vec2 r = vec2(
        fbm(p + 4.0 * q + vec2(1.7, 9.2) + 0.15 * t, 5),
        fbm(p + 4.0 * q + vec2(8.3, 2.8) + 0.126 * t, 5)
    );

    return fbm(p + 4.0 * r * warpAmount, 5);
}

// ── Cloud Density at a Point ─────────────────────────────────
// Returns cloud density [0,1] for a given UV + layer offset

float cloudDensityAt(vec2 uv, float layerOffset, float scale, float speed,
                     vec2 windDir, float t, float coverage, float turb) {
    vec2 p = uv * 3.0 * scale + layerOffset;
    p += windDir * t * speed;

    float n = warpedFbm(p, 0.5 + turb * 0.5, t * speed);

    // Coverage threshold: remap noise so coverage controls how much sky is filled
    float threshold = 1.0 - coverage;
    float density = smoothstep(threshold, threshold + 0.3, n);

    return density;
}

// ── Self-Shadowing ───────────────────────────────────────────
// March toward sun through cloud field to accumulate light occlusion

float selfShadow(vec2 uv, vec2 sunDir, float scale, float speed,
                 vec2 windDir, float t, float coverage, float turb) {
    float shadow = 0.0;
    float stepSize = 0.02;

    for (int i = 1; i <= 6; i++) {
        float fi = float(i);
        vec2 samplePos = uv + sunDir * fi * stepSize;
        float d = cloudDensityAt(samplePos, 0.0, scale, speed, windDir, t, coverage, turb);
        // Exponential falloff — closer occlusion matters more
        shadow += d * exp(-fi * 0.4);
    }

    return clamp(shadow * 0.5, 0.0, 1.0);
}

// ── God Rays ─────────────────────────────────────────────────
// Light scattering through cloud gaps along sun direction

float godRays(vec2 uv, vec2 sunDir, float scale, float speed,
              vec2 windDir, float t, float coverage, float turb) {
    float light = 0.0;
    float stepSize = 0.025;

    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        vec2 samplePos = uv - sunDir * fi * stepSize;
        float d = cloudDensityAt(samplePos, 0.0, scale, speed, windDir, t, coverage, turb);
        // Accumulate light in gaps (inverse density)
        float gap = 1.0 - d;
        light += gap * exp(-fi * 0.25);
    }

    return clamp(light / 6.0, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 uvAspect = vec2(uv.x * aspect, uv.y);

    float t = iTime;

    // ── Wind direction ───────────────────────────────────────
    float wAngle = windAngle * 6.2832;
    vec2 windDir = vec2(cos(wAngle), sin(wAngle));

    // ── Sun direction ────────────────────────────────────────
    float sAngle = sunAngle * 6.2832;
    vec2 sunDir = vec2(cos(sAngle), sin(sAngle));

    // ── Cloud speed scaling ──────────────────────────────────
    float speed = cloudSpeed * 0.4;

    // ── Three cloud layers ───────────────────────────────────
    // Each layer has different scale, speed, and parallax offset

    // Far layer — high, thin wisps (slow, small scale)
    float farDensity = cloudDensityAt(
        uvAspect, 10.0, cloudScale * 0.7, speed * 0.4,
        windDir, t, cloudCoverage * 0.6, turbulence * 0.5
    ) * 0.35;

    // Mid layer — main cumulus volume
    float midDensity = cloudDensityAt(
        uvAspect, 0.0, cloudScale, speed * 0.7,
        windDir, t, cloudCoverage, turbulence
    );

    // Near layer — low, thick cloud bottoms (faster, larger)
    float nearDensity = cloudDensityAt(
        uvAspect, 20.0, cloudScale * 1.3, speed * 1.0,
        windDir, t, cloudCoverage * 0.7, turbulence * 0.8
    ) * 0.5;

    // ── Vertical height mask ─────────────────────────────────
    // Clouds concentrated around cloudHeight with soft falloff
    float heightCenter = cloudHeight;
    float heightFalloff = 0.5;
    float heightMask = smoothstep(heightCenter - heightFalloff, heightCenter, uv.y)
                     * smoothstep(heightCenter + heightFalloff, heightCenter, uv.y);
    // Soften the mask so clouds aren't harshly clipped
    heightMask = mix(0.3, 1.0, heightMask);

    // Apply height mask to layers
    midDensity *= heightMask;
    nearDensity *= heightMask;
    farDensity *= mix(0.5, 1.0, heightMask); // far layer less affected

    // ── Composite cloud density ──────────────────────────────
    // Layers combine additively with saturation
    float totalDensity = clamp(farDensity + midDensity + nearDensity, 0.0, 1.0);
    totalDensity *= cloudDensity; // global density control

    // ── Self-shadowing on mid layer ──────────────────────────
    float shadow = selfShadow(
        uvAspect, sunDir, cloudScale, speed * 0.7,
        windDir, t, cloudCoverage, turbulence
    );

    // ── Cloud coloring ───────────────────────────────────────
    // Lit side: sunColor, shadow side: shadowColor
    // Shadow amount modulates between lit and shadowed
    vec3 litCloud = sunColor;
    vec3 darkCloud = shadowColor;

    // Edge lighting — clouds facing the sun get bright rim
    // Use midDensity gradient: thin edges are bright, thick centers are dark
    float edgeBrightness = smoothstep(0.4, 0.1, midDensity);

    // Combine shadow occlusion with cloud thickness for lighting
    float lightAmount = (1.0 - shadow * 0.8) * mix(0.4, 1.0, edgeBrightness);
    vec3 cloudColor = mix(darkCloud, litCloud, lightAmount);

    // Add bright highlight on cloud edges facing sun
    float rimLight = edgeBrightness * (1.0 - shadow) * 0.6;
    cloudColor += sunColor * rimLight;

    // ── God rays ─────────────────────────────────────────────
    float rays = 0.0;
    if (godRayIntensity > 0.01) {
        rays = godRays(
            uvAspect, sunDir, cloudScale, speed * 0.7,
            windDir, t, cloudCoverage, turbulence
        );
        // Rays are stronger where there are no clouds
        rays *= (1.0 - totalDensity * 0.7);
    }

    // ── Background texture ───────────────────────────────────
    vec3 bg = texture(iChannel0, uv).rgb;

    // ── Temporal feedback ────────────────────────────────────
    // Blend with previous frame for smooth cloud evolution
    float prevDensity = 0.0;
    if (iFrame > 0) {
        prevDensity = texture(iChannel1, uv).a;
    }
    // Smooth density changes over time (temporal persistence)
    float smoothDensity = mix(totalDensity, prevDensity, 0.85);
    // Use smoothed density for final compositing, raw for alpha output
    float compositeDensity = mix(smoothDensity, totalDensity, 0.4);

    // ── Final compositing ────────────────────────────────────
    // Background shows through cloud gaps
    vec3 col = bg;

    // Add god rays to background (subtle glow in gaps)
    col += sunColor * rays * godRayIntensity * 0.5;

    // Blend clouds over background based on density
    col = mix(col, cloudColor, compositeDensity);

    // Add god ray glow on top of clouds too (volumetric scattering)
    col += sunColor * rays * godRayIntensity * 0.3 * (1.0 - compositeDensity * 0.5);

    // Subtle vignette
    vec2 vc = uv - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.3;

    // Output: RGB + cloud density in alpha for feedback
    fragColor = vec4(col, totalDensity);
}
