// FireHaze — Content seen through rising heat distortion with fire emission glow
// Hot air refractive shimmer + ember particles + infrared bloom on bright areas
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash11(float p) { p=frac(p*0.1031); p*=p+33.33; p*=p+p; return frac(p); }
float hash21(float2 p) { float3 p3=frac(float3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return frac((p3.x+p3.y)*p3.z); }
float noise2(float2 p) {
    float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);
    return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);
}
float fbm(float2 p) {
    float v=0.0,a=0.5;
    float2x2 r=float2x2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<4;i++){v+=a*noise2(p);p=mul(r,p)*2.1;a*=0.5;}
    return v;
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Heat rises from the bottom — strongest distortion near base
    float heatStrength = pow(1.0 - uv.y, 2.0) * 0.5 + 0.05;

    // Turbulent rising columns of hot air
    float2 heatUV = float2(uv.x * 3.0, uv.y * 2.0 - time * 0.4);
    float  heatX  = fbm(heatUV) - 0.5;
    float  heatY  = fbm(heatUV + float2(5.2, 1.3)) - 0.5;

    float2 distort = float2(heatX, heatY * 0.3) * heatStrength * 0.04;
    float2 warpedUV = saturate(uv + distort);

    float4 col = tex0.Sample(sampler0, warpedUV);
    float  luma = dot(col.rgb, float3(0.299, 0.587, 0.114));

    // Colour shift — heat shifts the spectrum toward red/orange
    float heatTint = heatStrength * 0.6;
    col.rgb = lerp(col.rgb, col.rgb * float3(1.15, 0.85, 0.55), heatTint);

    // Bloom on bright areas — fire makes everything around it glow orange
    float bloom = smoothstep(0.6, 1.0, luma);
    col.rgb += bloom * float3(0.4, 0.15, 0.0) * heatStrength * 2.0;

    // Ember particles — tiny bright orange sparks rising
    float2 emberGrid = float2(uv.x * 120.0, uv.y * 70.0 + time * 1.8);
    float2 emberCell = floor(emberGrid);
    float2 emberFrac = frac(emberGrid);
    float2 emberPos  = float2(hash21(emberCell), hash21(emberCell + 7.3));
    // Sparks drift sideways slightly as they rise
    emberPos.x      += sin(time * (0.5 + hash21(emberCell) * 2.0) + emberCell.y) * 0.3;
    float emberLife  = frac(hash21(emberCell + 2.1) + time * (0.3 + hash21(emberCell) * 0.4));
    float emberDist  = length(emberFrac - emberPos);
    float ember      = step(emberDist, 0.04) * emberLife * (1.0 - uv.y);
    // Only spawn embers in lower 2/3 of screen
    ember           *= step(uv.y, 0.7);
    col.rgb         += ember * float3(1.0, 0.4, 0.05) * 2.0;

    // Smoke darkening in upper areas
    float smoke = fbm(float2(uv.x * 2.0, uv.y * 1.5 - time * 0.15)) * smoothstep(0.3, 0.0, uv.y);
    col.rgb     *= 1.0 - smoke * 0.4;

    // Vignette — darkness at edges like looking through flames
    float2 vig = uv * (1.0 - uv);
    col.rgb   *= lerp(0.3, 1.0, pow(vig.x * vig.y * 10.0, 0.4));

    return saturate(col);
}
