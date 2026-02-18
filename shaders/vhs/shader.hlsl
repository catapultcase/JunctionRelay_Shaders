// VHS pixel shader — color bleeding, luminance noise, tracking glitches, tape warble.
// Self-contained: driven entirely by time + UV, no extra cbuffers needed.
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

// ── Helpers ─────────────────────────────────────────────────────────────────

// Cheap hash — produces pseudo-random float in [0,1]
float hash(float2 p)
{
    p = frac(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return frac((p.x + p.y) * p.x);
}

// Smooth per-row hash (changes slowly with time) for tape warble
float rowHash(float row, float t)
{
    return hash(float2(row, floor(t * 12.0)));
}

// ── Main ─────────────────────────────────────────────────────────────────────

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── Tape warble: wobble U slightly based on scanline row and time ─────────
    float row        = floor(pos.y);
    float warble     = (rowHash(row, time) - 0.5) * 0.003;
    // Add a slower, broader wave on top
    warble          += sin(uv.y * 18.0 + time * 3.5) * 0.0008;
    float2 warpedUV  = float2(uv.x + warble, uv.y);

    // ── Horizontal tracking glitch bands ─────────────────────────────────────
    // A narrow band drifts up the screen every few seconds
    float bandSpeed  = frac(time * 0.18);
    float bandY      = frac(uv.y - bandSpeed);
    float glitchBand = step(0.97, bandY); // ~3% of screen height
    // Inside the band, shift U dramatically
    warpedUV.x      += glitchBand * (hash(float2(floor(time * 6.0), row)) - 0.5) * 0.06;

    // ── Sample with channel separation (chroma bleed) ─────────────────────────
    float bleed = 0.004 + glitchBand * 0.012;
    float r = tex0.Sample(sampler0, float2(warpedUV.x + bleed, warpedUV.y)).r;
    float g = tex0.Sample(sampler0, warpedUV).g;
    float b = tex0.Sample(sampler0, float2(warpedUV.x - bleed, warpedUV.y)).b;
    float4 col = float4(r, g, b, 1.0);

    // ── VHS color grading: desaturate slightly, warm up whites ────────────────
    float luma    = dot(col.rgb, float3(0.299, 0.587, 0.114));
    col.rgb       = lerp(col.rgb, float3(luma, luma, luma), 0.25); // mild desaturation
    col.rgb      *= float3(1.05, 1.0, 0.88);                       // warm / slightly yellowed

    // ── Luminance noise (tape grain) ─────────────────────────────────────────
    float grain   = hash(float2(uv.x + frac(time * 47.3), uv.y + frac(time * 31.7)));
    grain         = (grain - 0.5) * 0.08;
    col.rgb      += grain;

    // ── Scanlines (softer than hologram — VHS lines are subtle) ──────────────
    float scanline = 0.88 + 0.12 * sin(pos.y * 3.14159);
    col.rgb       *= scanline;

    // ── Horizontal luminance smear on the glitch band ─────────────────────────
    col.rgb       = lerp(col.rgb, col.rgb * float3(1.3, 1.1, 0.8), glitchBand * 0.6);

    // ── Vignette ──────────────────────────────────────────────────────────────
    float2 vig    = uv * (1.0 - uv.yx);
    float  vign   = pow(vig.x * vig.y * 15.0, 0.4);
    col.rgb      *= lerp(0.5, 1.0, vign);

    // ── Occasional full-frame brightness drop (tape dropout) ──────────────────
    float dropout  = 1.0 - 0.35 * step(0.97, frac(sin(floor(time * 5.0) * 127.1) * 43758.5));
    col.rgb       *= dropout;

    return saturate(col);
}
