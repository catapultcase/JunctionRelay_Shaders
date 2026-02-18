// Daguerreotype — 1840s silver plate photography
// Mirror-like metallic sheen + extreme vignette + chemical blotching + reversed tones
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
float fbm(float2 p) {
    float v=0.0,a=0.5; float2x2 r=float2x2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<4;i++){v+=a*noise2(p);p=mul(r,p)*2.1;a*=0.5;} return v;
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 raw = tex0.Sample(sampler0, uv);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // Daguerreotypes have peculiar tonal reversal in highlights —
    // very bright areas appear almost metallic/specular rather than white
    float toneCurve = luma < 0.5
        ? luma * 1.2
        : 0.6 + (luma - 0.5) * 0.6 + pow(luma, 3.0) * 0.3;
    toneCurve = saturate(toneCurve);

    // Silver-mercury amalgam colour — warm grey with slight gold in midtones
    float3 silver;
    silver.r = toneCurve * 0.92 + pow(toneCurve, 2.0) * 0.08;
    silver.g = toneCurve * 0.88 + pow(toneCurve, 2.0) * 0.06;
    silver.b = toneCurve * 0.80;

    // Metallic sheen — the plate surface has a mirror quality at angles
    // Simulate as a soft specular gradient across the plate
    float2 plateCenter = uv - float2(0.5, 0.48);
    float  viewAngle   = dot(normalize(plateCenter), float2(0.7, 0.3));
    float  sheen       = pow(saturate(viewAngle * 0.5 + 0.5), 6.0) * 0.15;
    silver            += sheen * float3(1.0, 0.95, 0.8);

    // Chemical blotching — uneven development, fog, age spots
    float blotch1 = fbm(uv * 3.0 + float2(2.3, 4.1));
    float blotch2 = fbm(uv * 7.0 + float2(5.5, 1.8));
    float blotch  = (blotch1 * 0.7 + blotch2 * 0.3);
    // Dark blotches where chemistry pooled, light halos where it was thin
    float darkBlotch  = smoothstep(0.6, 0.8, blotch) * 0.35;
    float lightBlotch = smoothstep(0.3, 0.1, blotch) * 0.2;
    silver -= darkBlotch;
    silver += lightBlotch * float3(0.9, 0.85, 0.7);

    // Plate scratches — thin bright lines across the surface
    float scratch1 = step(0.997, hash21(float2(floor(uv.x * 1920.0), 3.3)));
    float scratch2 = step(0.995, hash21(float2(4.4, floor(uv.y * 1080.0))));
    silver += (scratch1 + scratch2) * 0.4 * float3(1.0, 0.95, 0.85);

    // Heavy vignette — plate darkens dramatically at edges (uneven coating)
    float2 fromCenter = uv - 0.5;
    float  radial     = dot(fromCenter, fromCenter);
    float  vign       = 1.0 - smoothstep(0.1, 0.7, radial * 2.5);
    vign              = pow(vign, 1.8);
    silver           *= vign;

    // Plate border — the physical boundary of the exposure
    float2 border = smoothstep(0.0, 0.015, uv) * smoothstep(1.0, 0.985, uv);
    silver *= border.x * border.y;
    // Thin bright frame line at the plate edge
    float frameEdge = (1.0 - border.x * border.y) * step(0.96, border.x * border.y + 0.04);
    silver += frameEdge * 0.3 * float3(0.9, 0.85, 0.7);

    return float4(saturate(silver), 1.0);
}
