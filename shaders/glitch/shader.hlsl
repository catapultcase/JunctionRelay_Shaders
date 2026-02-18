// Glitch — Digital signal corruption shader
// RGB channel splitting + block displacement + bit-crush + datamosh smear
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

float hash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float hash21(float2 p) { float3 p3 = frac(float3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return frac((p3.x + p3.y) * p3.z); }

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── Glitch event timing — irregular bursts ─────────────────────────────
    float eventT    = floor(time * 3.7);
    float eventRand = hash11(eventT);
    float burstOn   = step(0.65, eventRand);   // fires ~35% of the time

    // ── Block displacement — macroblocks shift horizontally ────────────────
    float blockSize  = lerp(0.04, 0.12, hash11(eventT + 1.1));
    float blockRow   = floor(uv.y / blockSize);
    float blockShift = 0.0;
    if (burstOn > 0.0)
    {
        float rowRand = hash21(float2(blockRow, eventT));
        blockShift    = (rowRand > 0.75)
                      ? (hash21(float2(blockRow, eventT + 5.3)) - 0.5) * 0.18
                      : 0.0;
    }

    // ── Scanline-level jitter ──────────────────────────────────────────────
    float lineJitter = 0.0;
    if (burstOn > 0.0)
    {
        float lineRand = hash21(float2(floor(uv.y * 1080.0), eventT));
        lineJitter     = (lineRand > 0.92) ? (hash21(float2(uv.y, eventT)) - 0.5) * 0.06 : 0.0;
    }

    float2 warpedUV = saturate(float2(uv.x + blockShift + lineJitter, uv.y));

    // ── RGB channel split — each channel displaced independently ───────────
    float splitAmt = burstOn * lerp(0.002, 0.022, hash11(eventT + 2.2));
    float splitDir = (hash11(eventT + 3.3) - 0.5) * 2.0;

    float r = tex0.Sample(sampler0, saturate(warpedUV + float2( splitAmt * splitDir, 0))).r;
    float g = tex0.Sample(sampler0, warpedUV).g;
    float b = tex0.Sample(sampler0, saturate(warpedUV - float2( splitAmt * splitDir, 0))).b;
    float4 col = float4(r, g, b, 1.0);

    // ── Bit crush — quantize to simulate low bit-depth corruption ──────────
    float crushAmount = burstOn * lerp(4.0, 24.0, hash11(eventT + 4.4));
    if (crushAmount > 0.5)
        col.rgb = floor(col.rgb * crushAmount) / crushAmount;

    // ── Datamosh smear — rows of solid colour bleed from above ────────────
    if (burstOn > 0.0)
    {
        float smearRow  = hash11(eventT + 6.6);
        float smearH    = 0.03 + hash11(eventT + 7.7) * 0.08;
        float inSmear   = step(smearRow, uv.y) * step(uv.y, smearRow + smearH);
        float3 smearCol = tex0.Sample(sampler0, float2(uv.x, smearRow)).rgb;
        col.rgb         = lerp(col.rgb, smearCol, inSmear * 0.85);
    }

    // ── Random full-row colour flash ───────────────────────────────────────
    float flashRow  = hash11(floor(uv.y * 1080.0) + eventT * 13.7);
    float flashOn   = burstOn * step(0.97, flashRow);
    float3 flashCol = float3(hash11(eventT + 8.0), hash11(eventT + 9.0), hash11(eventT + 10.0));
    col.rgb         = lerp(col.rgb, flashCol, flashOn);

    // ── Subtle always-on digital noise ────────────────────────────────────
    col.rgb += (hash21(uv + frac(time * 47.3)) - 0.5) * 0.03;

    return saturate(col);
}
