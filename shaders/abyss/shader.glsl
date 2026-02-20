#version 300 es
precision mediump float;
// Abyss — Deep sea bioluminescence pixel shader
// Crushing darkness + drifting luminous particles + chromatic pressure waves + ink diffusion
// Like viewing through the viewport of a submersible at 4000m depth.
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime


// ── Helpers ──────────────────────────────────────────────────────────────────


uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash11(float p)
{
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise
float noise2(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),               hash21(i + vec2(1,0)), u.x),
        mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), u.x),
        u.y);
}

// Fractal Brownian Motion
float fbm(vec2 p)
{
    float v = 0.0, a = 0.5;
    mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++)
    {
        v += a * noise2(p);
        p  = rot * p * 2.1;
        a *= 0.5;
    }
    return v;
}

// Voronoi — nearest cell distance + cell id
float voronoi(vec2 p, out vec2 cellId)
{
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float minDist = 8.0;
    cellId = vec2(0, 0);

    for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++)
    {
        vec2 offset = vec2(x, y);
        vec2 id     = ip + offset;
        vec2 rnd    = vec2(hash21(id), hash21(id + 97.3));
        rnd += 0.35 * sin(iTime * 0.3 * vec2(0.7, 1.1) + id * 2.3);
        vec2 diff = offset + rnd - fp;
        float  d    = dot(diff, diff);
        if (d < minDist)
        {
            minDist = d;
            cellId  = id;
        }
    }
    return sqrt(minDist);
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // ── 1. Water column distortion ─────────────────────────────────────────────
    vec2 flow;
    flow.x = fbm(uv * 3.5 + vec2(iTime * 0.07,  0.0)) - 0.5;
    flow.y = fbm(uv * 3.5 + vec2(0.0, iTime * 0.05)) - 0.5;

    float ping      = sin(length(uv - 0.5) * 28.0 - iTime * 2.1) * 0.003;
    vec2 warpedUV = clamp(uv + flow * 0.012 + ping, 0.0, 1.0);

    vec4 col = texture(iChannel0, warpedUV);

    // ── 2. Deep water color grade ──────────────────────────────────────────────
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 deep;
    deep.r = luma * 0.04;
    deep.g = luma * 0.22;
    deep.b = luma * 0.45 + 0.04;
    col.rgb = deep;

    // ── 3. Pressure darkness ───────────────────────────────────────────────────
    vec2 fromCenter = uv - vec2(0.5, 0.45);
    float  depth      = dot(fromCenter, fromCenter);
    float  pressure   = 1.0 - smoothstep(0.0, 0.65, depth * 2.2);
    col.rgb          *= (0.15 + 0.85 * pressure);

    // ── 4. Bioluminescent organisms ────────────────────────────────────────────
    vec3 bioColor = vec3(0, 0, 0);

    // Micro: dinoflagellates
    {
        vec2 cid;
        float  d     = voronoi(uv * 28.0 + vec2(iTime * 0.04, iTime * 0.02), cid);
        float  pulse = 0.5 + 0.5 * sin(iTime * (1.5 + hash21(cid) * 2.0) + hash21(cid + 3.7) * 6.28);
        float  glow  = pow(clamp(1.0 - d * 2.8, 0.0, 1.0), 4.0) * pulse;
        bioColor    += glow * vec3(0.1, 0.8, 1.0) * 0.6;
    }

    // Meso: jellyfish / comb jellies
    {
        vec2 cid;
        float  d        = voronoi(uv * 7.0 + vec2(iTime * 0.025, iTime * 0.018), cid);
        float  hueShift = hash21(cid + 17.3);
        vec3 orgColor = mix(
            mix(vec3(0.0, 0.9, 1.0), vec3(0.6, 0.2, 1.0), step(0.5,  hueShift)),
            vec3(0.2, 1.0, 0.5), step(0.75, hueShift));
        float  pulse = 0.3 + 0.7 * abs(sin(iTime * (0.4 + hash21(cid) * 0.6)));
        float  glow  = pow(clamp(1.0 - d * 1.6, 0.0, 1.0), 6.0) * pulse;
        bioColor    += glow * orgColor * 1.4;
    }

    // Macro: rare large creature
    {
        vec2 cid;
        float  d     = voronoi(uv * 2.2 + vec2(iTime * 0.008, iTime * 0.006 + 1.7), cid);
        float  pulse = 0.1 + 0.9 * pow(abs(sin(iTime * 0.15 + hash21(cid) * 3.14)), 3.0);
        float  glow  = pow(clamp(1.0 - d * 0.9, 0.0, 1.0), 8.0) * pulse * 0.5;
        bioColor    += glow * vec3(0.05, 0.4, 0.9) * 2.0;
    }

    col.rgb += bioColor;

    // ── 5. Ink / particle diffusion ────────────────────────────────────────────
    float ink = fbm(uv * 5.0 - vec2(0.0, iTime * 0.04));
    ink       = smoothstep(0.55, 0.75, ink);
    col.rgb  *= (1.0 - ink * 0.35);

    // ── 6. Caustic light shafts from far above ─────────────────────────────────
    float caustic = fbm(uv * 6.0 + vec2(iTime * 0.06, iTime * 0.04));
    caustic      += fbm(uv * 9.0 - vec2(iTime * 0.03, iTime * 0.05)) * 0.5;
    caustic       = smoothstep(0.7, 1.0, caustic);
    float shaftMask = smoothstep(0.5, 0.0, abs(uv.x - 0.5) * 2.5)
                    * smoothstep(0.8, 0.1, uv.y);
    col.rgb += caustic * shaftMask * vec3(0.0, 0.06, 0.12);

    // ── 7. Viewport saltwater streaks ──────────────────────────────────────────
    float streakX = hash11(floor(uv.x * 60.0) * 0.3);
    float streakT = fract(streakX + iTime * 0.04);
    float streak  = smoothstep(0.0, 0.02, fract(uv.y + streakT))
                  * smoothstep(0.15, 0.05, fract(uv.y + streakT));
    streak       *= step(0.92, hash11(floor(uv.x * 60.0)));
    col.rgb      += streak * vec3(0.0, 0.04, 0.08);

    // ── 8. Marine snow ─────────────────────────────────────────────────────────
    float snow = hash21(uv * vec2(800.0, 600.0) + fract(iTime * 0.9));
    snow       = step(0.998, snow);
    col.rgb   += snow * vec3(0.4, 0.7, 1.0) * 0.6;

    // ── 9. Chromatic pressure aberration ──────────────────────────────────────
    float edgeDist = length(uv * 2.0 - 1.0);
    float aber     = smoothstep(0.6, 1.4, edgeDist) * 0.008;
    col.r += texture(iChannel0, warpedUV + vec2( aber, 0)).r * 0.04;
    col.b += texture(iChannel0, warpedUV - vec2( aber, 0)).b * 0.04;

    // ── 10. Final crush ────────────────────────────────────────────────────────
    col.rgb  = pow(clamp(col.rgb, 0.0, 1.0), vec3(1.15));
    col.rgb *= 0.92;

    fragColor = vec4(col.rgb, 1.0);
}
