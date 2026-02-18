// Caustics — Dancing light grid projected onto content from above
// Bright summery pool-floor light patterns, animated interference of refracted rays
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p) { float3 p3=frac(float3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return frac((p3.x+p3.y)*p3.z); }
float noise2(float2 p) {
    float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);
    return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);
}

float causticPattern(float2 p, float t)
{
    float c = 0.0;
    c += sin(p.x * 6.0 + sin(p.y * 4.0 + t * 0.7) + t * 1.1);
    c += sin(p.y * 5.0 + sin(p.x * 3.5 - t * 0.5) - t * 0.9);
    c += sin((p.x + p.y) * 4.5 + t * 0.6);
    return pow(saturate(c / 3.0 * 0.5 + 0.5), 4.0);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 col = tex0.Sample(sampler0, uv);

    float2 waterUV = uv * 6.0;
    float dx = noise2(waterUV + float2(time * 0.3, 0)) - 0.5;
    float dy = noise2(waterUV + float2(0, time * 0.25)) - 0.5;

    float2 causticUV = uv * 5.0 + float2(dx, dy) * 0.3;
    float  c1 = causticPattern(causticUV, time);
    float  c2 = causticPattern(causticUV * 1.3 + 0.7, time * 1.1);
    float  caustic = (c1 + c2 * 0.5) / 1.5;

    float3 lightColor = lerp(float3(0.6, 0.9, 1.0), float3(1.0, 0.98, 0.85), caustic);
    col.rgb *= 1.0 + caustic * lightColor * 1.2;
    col.rgb = lerp(col.rgb, col.rgb * float3(0.75, 0.92, 1.0), 0.25);

    float2 ripple = float2(dx, dy) * 0.006;
    col.rgb = lerp(col.rgb, tex0.Sample(sampler0, saturate(uv + ripple)).rgb, 0.3);

    float2 vig = uv * (1.0 - uv);
    col.rgb *= lerp(0.5, 1.0, pow(vig.x * vig.y * 12.0, 0.3));

    return saturate(col);
}
