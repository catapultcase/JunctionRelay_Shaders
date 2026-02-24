// Kaleidoscope — pass 0: animated symmetric pattern generator with feedback trails

// ─── Noise helpers ───────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = rot * p * 2.0;
        a *= 0.5;
    }
    return v;
}

// ─── Colour palette ──────────────────────────────────────────
vec3 palette(float t, vec3 tintA, vec3 tintB) {
    vec3 a = mix(tintA, tintB, 0.5) * 0.5;
    vec3 b = vec3(0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// ─── Main ────────────────────────────────────────────────────
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / min(iResolution.x, iResolution.y);
    float t = iTime;

    // ── Kaleidoscope fold (seamless — no hard lines) ──
    float r = length(uv);
    float a = atan(uv.y, uv.x);

    // Apply rotation
    a += t * rotationSpeed;

    // Fold into N segments using abs() — eliminates boundary artifacts
    float segAngle = 3.14159 * 2.0 / segments;
    a = mod(a + segAngle * 0.5, segAngle) - segAngle * 0.5;
    a = abs(a);

    // Back to cartesian (folded space)
    vec2 p = vec2(cos(a), sin(a)) * r;

    // ── Pattern generation ──
    p *= zoom;

    // Layer 1: primary flowing pattern
    float n1 = fbm(p * 3.0 + t * flowSpeed * 0.4);

    // Layer 2: secondary detail at different scale/speed
    float n2 = fbm(p * 6.0 - t * flowSpeed * 0.25 + 10.0);

    // Layer 3: fine crystalline detail
    float n3 = fbm(p * 12.0 + t * flowSpeed * 0.15 + 20.0);

    // Combine layers
    float pattern = n1 * 0.5 + n2 * 0.35 + n3 * 0.15;

    // ── Colouring with two tints ──
    vec3 col = palette(pattern + t * colorCycleSpeed * 0.1, colorTintA, colorTintB);

    // Add depth with radial brightness
    float radial = 1.0 - r * 0.6;
    col *= max(radial, 0.2);

    // Brighten pattern peaks using both tints
    vec3 peakTint = mix(colorTintA, colorTintB, sin(t * 0.5) * 0.5 + 0.5);
    col += peakTint * smoothstep(0.55, 0.75, n1) * 0.3 * brightness;

    // Overall brightness
    col *= brightness;

    // Vignette
    vec2 q = fragCoord / iResolution.xy;
    vec2 v = q * 2.0 - 1.0;
    col *= 1.0 - vignetteAmount * dot(v * v, v * v);

    // ── Feedback trail blending ──
    float trail = 0.0;
    if (iFrame > 0) {
        vec4 prev = texture(iChannel1, fragCoord / iResolution.xy);
        trail = prev.a;
    }
    // Decay old trail, accumulate new brightness
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    trail = max(trail * trailDecay, luma);

    fragColor = vec4(col, trail);
}
