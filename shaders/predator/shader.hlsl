// Predator — Active camouflage shimmer effect
// Content barely visible through chromatic displacement + heat distortion + edge plasma glow
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}
float noise2(float2 p){float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);}
float fbm(float2 p){float v=0.0,a=0.5;float2x2 r=float2x2(0.8,-0.6,0.6,0.8);for(int i=0;i<5;i++){v+=a*noise2(p);p=mul(r,p)*2.1;a*=0.5;}return v;}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Primary displacement — the cloaking device bends light around the wearer
    float2 dispUV = uv * 4.0 + float2(time * 0.15, time * 0.11);
    float  dispX  = fbm(dispUV) - 0.5;
    float  dispY  = fbm(dispUV + float2(3.7, 1.9)) - 0.5;

    // Secondary micro-tremor — the cloak isn't perfect, it shimmers
    float  tremFreq = 22.0;
    float  tremX = sin(uv.y * tremFreq + time * 8.0) * 0.002;
    float  tremY = sin(uv.x * tremFreq * 1.3 - time * 6.5) * 0.001;

    float2 displacement = float2(dispX, dispY) * 0.03 + float2(tremX, tremY);

    // Each colour channel displaced differently — chromatic aberration of cloaking
    float2 uvR = saturate(uv + displacement * 1.20);
    float2 uvG = saturate(uv + displacement * 1.00);
    float2 uvB = saturate(uv + displacement * 0.82);

    float r = tex0.Sample(sampler0, uvR).r;
    float g = tex0.Sample(sampler0, uvG).g;
    float b = tex0.Sample(sampler0, uvB).b;

    // The cloaked form is mostly transparent — reduce visibility significantly
    float3 col = float3(r, g, b) * 0.35;

    // Edge plasma glow — the Predator's outline shimmers with bio-electric energy
    // Detected by sampling displaced vs undisplaced and finding the differential
    float lumaCloaked = dot(col, float3(0.299, 0.587, 0.114));
    float lumaOrig    = dot(tex0.Sample(sampler0, uv).rgb, float3(0.299, 0.587, 0.114));
    float edgeDiff    = abs(lumaCloaked - lumaOrig * 0.35);

    // Plasma colour — shifts between orange and blue-white like thermal discharge
    float plasmaShift = sin(time * 2.3 + uv.y * 8.0) * 0.5 + 0.5;
    float3 plasma1    = float3(1.0, 0.4, 0.1);   // hot orange
    float3 plasma2    = float3(0.3, 0.7, 1.0);   // cool blue
    float3 plasmaCol  = lerp(plasma1, plasma2, plasmaShift);

    float plasmaGlow = pow(edgeDiff, 0.6) * 1.5;
    col += plasmaGlow * plasmaCol;

    // Interference fringe — like a holographic diffraction pattern overlaid
    float fringe = sin(uv.x * 180.0 + dispX * 40.0 + time * 4.0) * 0.5 + 0.5;
    fringe      *= sin(uv.y * 140.0 + dispY * 35.0 - time * 3.2) * 0.5 + 0.5;
    fringe       = pow(fringe, 3.0) * 0.08;
    col         += fringe * float3(0.2, 0.8, 1.0);

    // Very faint original scene underneath — the cloak isn't perfect
    col += tex0.Sample(sampler0, uv).rgb * 0.08;

    // Environmental darkness — the Predator's cloak absorbs some light
    float2 vig = uv * (1.0 - uv);
    col *= lerp(0.6, 1.0, pow(vig.x * vig.y * 12.0, 0.25));

    return float4(saturate(col), 1.0);
}
