// Kinescope — 1940s TV broadcast recorded off a CRT onto 16mm film
// Softer and ghostlier than VHS — bloom halation, phosphor persistence, film weave
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash11(float p){p=frac(p*0.1031);p*=p+33.33;p*=p+p;return frac(p);}
float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}
float noise2(float2 p){float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Film weave — the 16mm frame physically wobbles in the gate
    float frameT = floor(time * 18.0);   // 18fps kinescope
    float weaveX = (hash11(frameT * 0.37) - 0.5) * 0.004;
    float weaveY = (hash11(frameT * 0.71) - 0.5) * 0.002;
    float2 weavedUV = saturate(uv + float2(weaveX, weaveY));

    float4 col = tex0.Sample(sampler0, weavedUV);
    float  luma = dot(col.rgb, float3(0.299, 0.587, 0.114));

    // Monochrome — kinescopes were B&W
    col.rgb = float3(luma, luma, luma);

    // Phosphor persistence / ghosting — CRT phosphor holds image briefly
    // Approximated with a slight upward smear (phosphor decays as beam moves on)
    float ghostLuma = dot(tex0.Sample(sampler0, saturate(weavedUV - float2(0, 0.003))).rgb, float3(0.299,0.587,0.114));
    col.rgb = lerp(col.rgb, float3(ghostLuma,ghostLuma,ghostLuma), 0.2);

    // Bloom halation — CRT highlights bleed into surrounding film emulsion
    float bloom = 0.0;
    bloom += dot(tex0.Sample(sampler0, saturate(weavedUV + float2( 0.003, 0))).rgb, float3(0.299,0.587,0.114));
    bloom += dot(tex0.Sample(sampler0, saturate(weavedUV + float2(-0.003, 0))).rgb, float3(0.299,0.587,0.114));
    bloom += dot(tex0.Sample(sampler0, saturate(weavedUV + float2(0,  0.003))).rgb, float3(0.299,0.587,0.114));
    bloom += dot(tex0.Sample(sampler0, saturate(weavedUV + float2(0, -0.003))).rgb, float3(0.299,0.587,0.114));
    bloom /= 4.0;
    float halation = pow(bloom, 2.5) * 0.35;
    col.rgb += halation;

    // Warm base tint — 1940s film stock had a warm silver-gelatin base
    col.rgb *= float3(1.05, 1.0, 0.90);

    // Contrast curve — kinescopes were contrasty with crushed shadows
    col.rgb = pow(saturate(col.rgb), 1.3);
    col.rgb = saturate(col.rgb * 1.15 - 0.05);

    // Scanlines — CRT raster visible through the film
    float scanline = 0.82 + 0.18 * step(0.5, frac(pos.y * 0.5));
    col.rgb *= scanline;

    // Coarse film grain — 16mm is grainy
    float grain = hash21(weavedUV * float2(480.0, 270.0) + frac(time * 31.3)) - 0.5;
    col.rgb += grain * 0.07;

    // Frame flicker — exposure variation between frames
    float flicker = 0.88 + 0.12 * hash11(frameT * 0.13);
    col.rgb *= flicker;

    // Vertical scratch — rare but persistent frame scratch on the film
    float scratchX = 0.63;
    float scratchMask = step(abs(uv.x - scratchX), 0.001) * step(0.8, hash11(floor(uv.y * 200.0) + frameT * 0.1));
    col.rgb += scratchMask * 0.5;

    // Vignette — lens falloff on the kinescope camera filming the CRT
    float2 vig = uv * (1.0 - uv);
    col.rgb *= pow(vig.x * vig.y * 16.0, 0.4);

    return saturate(col);
}
