// Clouds — God Rays Post-Process (Pass 1)
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Permission is granted to use, modify, and redistribute this shader
// solely as a plugin for the JunctionRelay platform (junctionrelay.com).
// All other use requires explicit written permission from CatapultCase.
//
// Screen-space radial blur from the sun's projected position.
// Samples along rays from each pixel toward the sun, accumulating
// bright areas to create volumetric light shaft illusion.
//
// Inputs: iChannel0 (pass 0 output), iResolution
// Params: sunAngle, godrayIntensity, godrayDecay, godrayDensity

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 original = texture(iChannel0, uv);

    // Sun screen position from sunAngle (matches pass 0 camera)
    float sAngle = sunAngle * 6.2832;
    vec2 sunScreen = vec2(0.5 + cos(sAngle) * 0.6, 0.35 + sin(sAngle) * 0.15);

    // Direction from this pixel toward the sun
    vec2 delta = (sunScreen - uv) * godrayDensity / 40.0;

    vec2 tc = uv;
    vec3 rays = vec3(0.0);
    float weight = 1.0;

    for (int i = 0; i < 40; i++) {
        tc += delta;
        vec3 s = texture(iChannel0, tc).rgb;

        // Only accumulate bright areas
        float lum = dot(s, vec3(0.299, 0.587, 0.114));
        rays += s * max(lum - 0.5, 0.0) * weight;

        weight *= godrayDecay;
    }

    rays /= 40.0;

    vec3 result = original.rgb + rays * godrayIntensity;
    fragColor = vec4(result, original.a);
}
