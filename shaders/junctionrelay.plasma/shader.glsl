// Generative Plasma — FBM color fields, zero texture input
// Custom uniforms: uSpeed (float), uPrimaryColor (vec3), uSecondaryColor (vec3)

float hash_p(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise_p(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash_p(i), hash_p(i + vec2(1.0, 0.0)), f.x),
        mix(hash_p(i + vec2(0.0, 1.0)), hash_p(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm_p(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.87, 0.48, -0.48, 0.87);
    for (int i = 0; i < 4; i++) {
        v += a * noise_p(p);
        p = rot * p * 2.0;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime * uSpeed;

    // Layered FBM domain warping
    vec2 q = vec2(
        fbm_p(uv * 3.0 + t * 0.2),
        fbm_p(uv * 3.0 + vec2(1.7, 9.2) + t * 0.15)
    );
    vec2 r = vec2(
        fbm_p(uv * 2.0 + q + vec2(8.3, 2.8) + t * 0.1),
        fbm_p(uv * 2.0 + q + vec2(5.1, 3.3) + t * 0.12)
    );
    float f = fbm_p(uv * 1.5 + r);

    // Two-tone palette from custom uniforms
    vec3 col = mix(uPrimaryColor, uSecondaryColor, f);
    col = mix(col, uPrimaryColor * 0.3, r.x * 0.6);
    col = mix(col, uSecondaryColor * 1.4, r.y * r.y * 0.5);

    // Brightness boost in warped regions
    col += vec3(0.1) * smoothstep(0.3, 0.8, f);

    // Vignette
    vec2 vig = uv * (1.0 - uv);
    col *= pow(vig.x * vig.y * 16.0, 0.15);

    fragColor = vec4(col, 1.0);
}
