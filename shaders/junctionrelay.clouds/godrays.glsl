// Clouds — God Rays Post-Process (Pass 1)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Screen-space radial blur from the sun's projected position.
// Extracts a bright-sky mask, then marches from each pixel toward the
// sun accumulating only the mask — gives crisp shafts through cloud gaps.
//
// Inputs: iChannel0 (pass 0 output), iResolution
// Params: godraySunAngle, godrayIntensity, godrayDecay, godrayDensity

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 original = texture(iChannel0, uv);

    // Sun screen position — reconstruct from the same camera as pass 0
    float sAngle = godraySunAngle * 6.2832;
    vec3 sunDir = normalize(vec3(cos(sAngle), 0.0, sin(sAngle)));

    // Match pass 0 camera exactly
    vec3 ro = vec3(0.0, 4.0, -5.0);  // camera origin (time doesn't affect screen projection)
    vec3 ta = vec3(0.0, 0.5, ro.z + 8.0);
    vec3 cw = normalize(ta - ro);
    vec3 cu = normalize(cross(vec3(0.0, 1.0, 0.0), cw));
    vec3 cv = cross(cw, cu);

    // Project sun direction into screen space
    float dCw = dot(sunDir, cw);
    float sunU = 0.5 + (dot(sunDir, cu) / dCw) / (2.0 * iResolution.x / iResolution.y);
    float sunV = 0.5 + (dot(sunDir, cv) / dCw) / 2.0;
    vec2 sunScreen = vec2(sunU, sunV);

    // Step toward the sun
    vec2 delta = (sunScreen - uv) * godrayDensity / 60.0;

    // Proximity to sun — rays are stronger near the source
    float distToSun = length(uv - sunScreen);
    float sunProximity = 1.0 - smoothstep(0.0, 1.2, distToSun);

    vec2 tc = uv;
    float rays = 0.0;
    float weight = 1.0;

    for (int i = 0; i < 60; i++) {
        tc += delta;

        // Clamp to screen
        vec2 stc = clamp(tc, 0.0, 1.0);
        vec3 s = texture(iChannel0, stc).rgb;

        // Luminance
        float lum = dot(s, vec3(0.299, 0.587, 0.114));

        // Hard threshold — only sky-bright pixels contribute (cloud gaps, sun glow)
        float mask = smoothstep(0.7, 0.95, lum);

        rays += mask * weight;
        weight *= godrayDecay;
    }

    rays /= 60.0;

    // Tint rays with sun-adjacent color (warm near sun)
    vec3 rayColor = mix(vec3(0.9, 0.9, 0.95), original.rgb, 0.3);

    // Apply with sun proximity falloff — shafts fade further from sun
    vec3 result = original.rgb + rayColor * rays * godrayIntensity * sunProximity;

    fragColor = vec4(result, original.a);
}
