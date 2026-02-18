// Hologram pixel shader — cyan tint + scanlines + time-based flicker + edge glow.
// Ported from XSD-VR Bridge V4 POC.
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

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex0.Sample(sampler0, uv);

    // Cyan hologram tint
    col.rgb = float3(col.r * 0.3, col.g * 0.9, col.b * 1.0);

    // Scanlines — darken every other pair of lines
    float scanline = step(0.5, frac(pos.y * 0.25));
    col.rgb *= 0.7 + 0.3 * scanline;

    // Time-based flicker
    float flicker = 0.92 + 0.08 * sin(time * 8.0);
    col.rgb *= flicker;

    // Slight edge glow boost
    float edge = smoothstep(0.0, 0.15, uv.x) * smoothstep(0.0, 0.15, 1.0 - uv.x);
    edge *= smoothstep(0.0, 0.15, uv.y) * smoothstep(0.0, 0.15, 1.0 - uv.y);
    col.rgb *= 0.6 + 0.4 * edge;

    return col;
}
