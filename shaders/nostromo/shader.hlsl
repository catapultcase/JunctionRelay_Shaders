// Nostromo — Sci-fi cassette futurism pixel shader
// Amber phosphor CRT + chunky scanlines + raster interference + data corruption glyphs
// Inspired by the USCSS Nostromo MU-TH-UR 6000 terminal aesthetic.
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

// Smooth noise for organic interference
float noise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash21(i),               hash21(i + float2(1, 0)), u.x),
        lerp(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x),
        u.y);
}

// 5x7 bitmap font — digits 0-9, each row is a 5-bit mask (bit4 = leftmost).
float bitmapGlyph(int id, int cx, int cy)
{
    if (cx < 0 || cx > 4 || cy < 0 || cy > 6) return 0.0;

    static const uint font[10][7] = {
        { 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E }, // 0
        { 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E }, // 1
        { 0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F }, // 2
        { 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E }, // 3
        { 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 }, // 4
        { 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E }, // 5
        { 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E }, // 6
        { 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 }, // 7
        { 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E }, // 8
        { 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C }, // 9
    };

    uint row = font[id % 10][cy];
    return ((row >> (4 - cx)) & 1u) ? 1.0 : 0.0;
}

// ── Main ─────────────────────────────────────────────────────────────────────

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── 1. Barrel / CRT warp ──────────────────────────────────────────────────
    float2 centered = uv * 2.0 - 1.0;
    float2 warp     = centered * (1.0 + dot(centered, centered) * 0.06);
    float2 warpedUV = warp * 0.5 + 0.5;

    // Black outside the warped boundary
    float inBounds = step(0.0, warpedUV.x) * step(warpedUV.x, 1.0)
                   * step(0.0, warpedUV.y) * step(warpedUV.y, 1.0);

    float4 col = tex0.Sample(sampler0, warpedUV) * inBounds;

    // ── 2. Phosphor color grading — amber / Weyland-Yutani terminal ───────────
    float luma = dot(col.rgb, float3(0.299, 0.587, 0.114));

    float3 phosphor;
    phosphor.r = luma * 1.10;
    phosphor.g = luma * 0.80;
    phosphor.b = luma * 0.08;

    // Sickly green corona in bright areas
    phosphor.g += pow(luma, 2.2) * 0.25;

    col.rgb = phosphor;

    // ── 3. Chunky CRT scanlines ───────────────────────────────────────────────
    float scanRow  = floor(pos.y * 0.5);
    float scanline = 0.72 + 0.28 * step(0.5, frac(scanRow * 0.5));
    col.rgb       *= scanline;

    // ── 4. Horizontal raster interference ripple ──────────────────────────────
    float ripple = sin(uv.y * 85.0 + time * 1.3) * 0.04
                 + sin(uv.y * 23.0 - time * 0.7) * 0.03;
    col.rgb      += ripple;

    // ── 5. Vertical sync roll — dim bar drifts up like an unsync'd monitor ────
    float rollPhase = frac(time * 0.07);
    float rollBar   = 1.0 - 0.18 * smoothstep(0.0, 0.04,
                          abs(frac(uv.y - rollPhase) - 0.5) - 0.46);
    col.rgb        *= rollBar;

    // ── 6. Data corruption glitch strip ──────────────────────────────────────
    // Fires for ~6% of an 8-second cycle; renders tiled bitmap digits
    float glitchCycle  = frac(time * 0.12);
    float glitchActive = step(0.92, glitchCycle);
    float glitchY      = hash11(floor(time * 0.12)) * 0.75 + 0.1;
    float glitchHeight = 0.04;
    float inStrip      = glitchActive
                       * step(glitchY, uv.y)
                       * step(uv.y, glitchY + glitchHeight);

    if (inStrip > 0.0)
    {
        int cellW   = 6;
        int cellH   = 9;
        int cellX   = (int)fmod(pos.x, (float)cellW);
        int cellY   = (int)fmod(pos.y - glitchY * 1080.0, (float)cellH);
        int glyphId = (int)(hash21(float2(floor(pos.x / cellW),
                                         floor(time * 6.0))) * 10.0);

        float bit = bitmapGlyph(glyphId, cellX, cellY);
        col.rgb   = lerp(float3(0.02, 0.01, 0.0),
                         float3(1.0,  0.65, 0.05),
                         bit);
    }

    // ── 7. Slow phosphor grain / thermal noise ────────────────────────────────
    float grain = hash21(warpedUV + frac(time * 73.1)) - 0.5;
    col.rgb    += grain * 0.035;

    // ── 8. Heavy bezel vignette ───────────────────────────────────────────────
    float2 vig  = warpedUV * (1.0 - warpedUV);
    float  vign = pow(vig.x * vig.y * 18.0, 0.5);
    col.rgb    *= lerp(0.0, 1.0, vign);

    // ── 9. Phosphor green fringing on bright edges ────────────────────────────
    float brightness = dot(col.rgb, float3(1, 1, 1));
    col.g           += brightness * 0.04;

    // ── 10. Gamma punch ───────────────────────────────────────────────────────
    col.rgb = pow(saturate(col.rgb), 0.88);

    return float4(col.rgb, 1.0);
}
