// Abyss — Deep sea bioluminescence pixel shader
// Crushing darkness + drifting luminous particles + chromatic pressure waves + ink diffusion
// Like viewing through the viewport of a submersible at 4000m depth.
//
// Bridge contract:
//   - Input texture bound to t0 (captured WebView2 frame)
//   - Sampler bound to s0 (linear clamp)
//   - TimeBuffer cbuffer at b0 (float time + 12 bytes padding)
//   - VS provides: float4 pos : SV_Position, float2 uv : TEXCOORD0

Texture2D    tex0     : register(t0);
SamplerState sampler0 : register(s0);

cbuffer TimeBuffer : register(b0)
{
    float time;
    float3 _pad;
};

// ── Helpers ──────────────────────────────────────────────────────────────────

float hash11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float hash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// Smooth value noise
float noise2(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash21(i),               hash21(i + float2(1,0)), u.x),
        lerp(hash21(i + float2(0,1)), hash21(i + float2(1,1)), u.x),
        u.y);
}

// Fractal Brownian Motion
float fbm(float2 p)
{
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++)
    {
        v += a * noise2(p);
        p  = mul(rot, p) * 2.1;
        a *= 0.5;
    }
    return v;
}

// Voronoi — nearest cell distance + cell id
float voronoi(float2 p, out float2 cellId)
{
    float2 ip = floor(p);
    float2 fp = frac(p);
    float minDist = 8.0;
    cellId = float2(0, 0);

    for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++)
    {
        float2 offset = float2(x, y);
        float2 id     = ip + offset;
        float2 rnd    = float2(hash21(id), hash21(id + 97.3));
        rnd += 0.35 * sin(time * 0.3 * float2(0.7, 1.1) + id * 2.3);
        float2 diff = offset + rnd - fp;
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

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── 1. Water column distortion ─────────────────────────────────────────────
    float2 flow;
    flow.x = fbm(uv * 3.5 + float2(time * 0.07,  0.0)) - 0.5;
    flow.y = fbm(uv * 3.5 + float2(0.0, time * 0.05)) - 0.5;

    float ping      = sin(length(uv - 0.5) * 28.0 - time * 2.1) * 0.003;
    float2 warpedUV = saturate(uv + flow * 0.012 + ping);

    float4 col = tex0.Sample(sampler0, warpedUV);

    // ── 2. Deep water color grade ──────────────────────────────────────────────
    float luma = dot(col.rgb, float3(0.299, 0.587, 0.114));
    float3 deep;
    deep.r = luma * 0.04;
    deep.g = luma * 0.22;
    deep.b = luma * 0.45 + 0.04;
    col.rgb = deep;

    // ── 3. Pressure darkness ───────────────────────────────────────────────────
    float2 fromCenter = uv - float2(0.5, 0.45);
    float  depth      = dot(fromCenter, fromCenter);
    float  pressure   = 1.0 - smoothstep(0.0, 0.65, depth * 2.2);
    col.rgb          *= (0.15 + 0.85 * pressure);

    // ── 4. Bioluminescent organisms ────────────────────────────────────────────
    float3 bioColor = float3(0, 0, 0);

    // Micro: dinoflagellates
    {
        float2 cid;
        float  d     = voronoi(uv * 28.0 + float2(time * 0.04, time * 0.02), cid);
        float  pulse = 0.5 + 0.5 * sin(time * (1.5 + hash21(cid) * 2.0) + hash21(cid + 3.7) * 6.28);
        float  glow  = pow(saturate(1.0 - d * 2.8), 4.0) * pulse;
        bioColor    += glow * float3(0.1, 0.8, 1.0) * 0.6;
    }

    // Meso: jellyfish / comb jellies
    {
        float2 cid;
        float  d        = voronoi(uv * 7.0 + float2(time * 0.025, time * 0.018), cid);
        float  hueShift = hash21(cid + 17.3);
        float3 orgColor = lerp(
            lerp(float3(0.0, 0.9, 1.0), float3(0.6, 0.2, 1.0), step(0.5,  hueShift)),
            float3(0.2, 1.0, 0.5), step(0.75, hueShift));
        float  pulse = 0.3 + 0.7 * abs(sin(time * (0.4 + hash21(cid) * 0.6)));
        float  glow  = pow(saturate(1.0 - d * 1.6), 6.0) * pulse;
        bioColor    += glow * orgColor * 1.4;
    }

    // Macro: rare large creature
    {
        float2 cid;
        float  d     = voronoi(uv * 2.2 + float2(time * 0.008, time * 0.006 + 1.7), cid);
        float  pulse = 0.1 + 0.9 * pow(abs(sin(time * 0.15 + hash21(cid) * 3.14)), 3.0);
        float  glow  = pow(saturate(1.0 - d * 0.9), 8.0) * pulse * 0.5;
        bioColor    += glow * float3(0.05, 0.4, 0.9) * 2.0;
    }

    col.rgb += bioColor;

    // ── 5. Ink / particle diffusion ────────────────────────────────────────────
    float ink = fbm(uv * 5.0 - float2(0.0, time * 0.04));
    ink       = smoothstep(0.55, 0.75, ink);
    col.rgb  *= (1.0 - ink * 0.35);

    // ── 6. Caustic light shafts from far above ─────────────────────────────────
    float caustic = fbm(uv * 6.0 + float2(time * 0.06, time * 0.04));
    caustic      += fbm(uv * 9.0 - float2(time * 0.03, time * 0.05)) * 0.5;
    caustic       = smoothstep(0.7, 1.0, caustic);
    float shaftMask = smoothstep(0.5, 0.0, abs(uv.x - 0.5) * 2.5)
                    * smoothstep(0.8, 0.1, uv.y);
    col.rgb += caustic * shaftMask * float3(0.0, 0.06, 0.12);

    // ── 7. Viewport saltwater streaks ──────────────────────────────────────────
    float streakX = hash11(floor(uv.x * 60.0) * 0.3);
    float streakT = frac(streakX + time * 0.04);
    float streak  = smoothstep(0.0, 0.02, frac(uv.y + streakT))
                  * smoothstep(0.15, 0.05, frac(uv.y + streakT));
    streak       *= step(0.92, hash11(floor(uv.x * 60.0)));
    col.rgb      += streak * float3(0.0, 0.04, 0.08);

    // ── 8. Marine snow ─────────────────────────────────────────────────────────
    float snow = hash21(uv * float2(800.0, 600.0) + frac(time * 0.9));
    snow       = step(0.998, snow);
    col.rgb   += snow * float3(0.4, 0.7, 1.0) * 0.6;

    // ── 9. Chromatic pressure aberration ──────────────────────────────────────
    float edgeDist = length(uv * 2.0 - 1.0);
    float aber     = smoothstep(0.6, 1.4, edgeDist) * 0.008;
    col.r += tex0.Sample(sampler0, warpedUV + float2( aber, 0)).r * 0.04;
    col.b += tex0.Sample(sampler0, warpedUV - float2( aber, 0)).b * 0.04;

    // ── 10. Final crush ────────────────────────────────────────────────────────
    col.rgb  = pow(saturate(col.rgb), 1.15);
    col.rgb *= 0.92;

    return float4(col.rgb, 1.0);
}
