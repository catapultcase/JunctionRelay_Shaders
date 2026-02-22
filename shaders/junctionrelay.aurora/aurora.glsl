// Generative Aurora Borealis — shimmering light curtains, zero texture input
// Custom uniforms: uIntensity (float)

float hash_a(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_a(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash_a(i), hash_a(i + vec2(1.0, 0.0)), f.x),
        mix(hash_a(i + vec2(0.0, 1.0)), hash_a(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm_a(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 3; i++) {
        v += a * noise_a(p);
        p = rot * p * 2.0;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime * 0.3;

    // Sky gradient — dark at top, slightly lighter at horizon
    vec3 sky = mix(vec3(0.0, 0.02, 0.05), vec3(0.02, 0.04, 0.08), uv.y);

    // Aurora curtains — layered vertical bands with horizontal drift
    float curtain = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float freq = 2.0 + fi * 1.5;
        float speed = t * (0.4 + fi * 0.15);
        float wave = sin(uv.x * freq + speed + fbm_a(vec2(uv.x * 3.0, t * 0.2 + fi)));
        wave = wave * 0.5 + 0.5;
        // Vertical fade — aurora appears in upper half
        float vfade = smoothstep(0.2, 0.7, uv.y) * smoothstep(1.0, 0.75, uv.y);
        curtain += wave * vfade * (0.5 - fi * 0.1);
    }

    // Shimmer — high-frequency noise modulation
    float shimmer = noise_a(vec2(uv.x * 8.0, uv.y * 4.0 + t * 2.0));
    curtain *= 0.7 + 0.3 * shimmer;

    // Aurora color — green core, purple/blue edges
    vec3 auroraColor = mix(
        vec3(0.1, 0.8, 0.3),  // green
        vec3(0.4, 0.1, 0.7),  // purple
        smoothstep(0.4, 0.85, uv.y)
    );
    auroraColor = mix(auroraColor, vec3(0.1, 0.3, 0.9), curtain * 0.3); // blue tint

    // Compose
    vec3 col = sky + auroraColor * curtain * uIntensity;

    // Subtle star field in dark regions
    float star = step(0.998, hash_a(floor(fragCoord * 0.5)));
    float twinkle = 0.5 + 0.5 * sin(iTime * 3.0 + hash_a(floor(fragCoord * 0.5)) * 6.28);
    col += vec3(star * twinkle * 0.6 * (1.0 - curtain));

    fragColor = vec4(col, 1.0);
}
