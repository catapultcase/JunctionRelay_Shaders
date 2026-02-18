// Oscilloscope — Edge-detected content rendered as a glowing vector beam
// Lissajous-style display with electron beam bloom and phosphor persistence
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}

float sobelLuma(float2 uv, float2 ts)
{
    float tl=dot(tex0.Sample(sampler0,uv+ts*float2(-1,-1)).rgb,float3(0.299,0.587,0.114));
    float tc=dot(tex0.Sample(sampler0,uv+ts*float2( 0,-1)).rgb,float3(0.299,0.587,0.114));
    float tr=dot(tex0.Sample(sampler0,uv+ts*float2( 1,-1)).rgb,float3(0.299,0.587,0.114));
    float ml=dot(tex0.Sample(sampler0,uv+ts*float2(-1, 0)).rgb,float3(0.299,0.587,0.114));
    float mr=dot(tex0.Sample(sampler0,uv+ts*float2( 1, 0)).rgb,float3(0.299,0.587,0.114));
    float bl=dot(tex0.Sample(sampler0,uv+ts*float2(-1, 1)).rgb,float3(0.299,0.587,0.114));
    float bc=dot(tex0.Sample(sampler0,uv+ts*float2( 0, 1)).rgb,float3(0.299,0.587,0.114));
    float br=dot(tex0.Sample(sampler0,uv+ts*float2( 1, 1)).rgb,float3(0.299,0.587,0.114));
    float gx=-tl-2.0*ml-bl+tr+2.0*mr+br;
    float gy=-tl-2.0*tc-tr+bl+2.0*bc+br;
    return saturate(sqrt(gx*gx+gy*gy)*5.0);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 ts = float2(1.0/1920.0, 1.0/1080.0);

    // Edge detection — these become the "beam traces"
    float edge = sobelLuma(uv, ts);

    // Thicken edges slightly — beam has physical width
    float edgeBlur = 0.0;
    edgeBlur += sobelLuma(uv + ts * float2( 1,  0), ts);
    edgeBlur += sobelLuma(uv + ts * float2(-1,  0), ts);
    edgeBlur += sobelLuma(uv + ts * float2( 0,  1), ts);
    edgeBlur += sobelLuma(uv + ts * float2( 0, -1), ts);
    edgeBlur /= 4.0;
    float beam = saturate(edge * 1.5 + edgeBlur * 0.5);

    // Electron beam bloom — bright beam bleeds into surrounding phosphor
    float bloom = 0.0;
    float2 offsets[8] = {
        float2(2,0),float2(-2,0),float2(0,2),float2(0,-2),
        float2(1.4,1.4),float2(-1.4,1.4),float2(1.4,-1.4),float2(-1.4,-1.4)
    };
    for(int i=0;i<8;i++)
        bloom += sobelLuma(uv + ts * offsets[i] * 2.0, ts);
    bloom /= 8.0;
    float glowBeam = saturate(beam + bloom * 0.4);

    // Phosphor colour — classic green P31 oscilloscope phosphor
    float3 col = float3(0.0, glowBeam, glowBeam * 0.15);
    // Core of beam is brighter white-green
    col += float3(beam * 0.1, beam * 0.2, beam * 0.05);

    // Graticule — the grid lines on the oscilloscope face
    float2 gratUV = frac(uv * float2(10.0, 8.0));
    float  gratH  = smoothstep(0.01, 0.0, abs(gratUV.x - 0.5)) * 0.08;
    float  gratV  = smoothstep(0.01, 0.0, abs(gratUV.y - 0.5)) * 0.08;
    // Main axes slightly brighter
    float2 mainAxis = smoothstep(0.008, 0.0, abs(uv - 0.5));
    float  axes    = (mainAxis.x + mainAxis.y) * 0.12;
    col += float3(0.0, gratH + gratV + axes, 0.0);

    // Oscilloscope background — near black with faint green ambient
    col += float3(0.0, 0.008, 0.003);

    // Slight beam flicker — electron gun power supply ripple
    float flicker = 0.95 + 0.05 * sin(time * 120.0);
    col *= flicker;

    // Phosphor noise
    col.g += (hash21(uv + frac(time * 53.1)) - 0.5) * 0.012;

    // Scope face vignette
    float2 vig = uv * (1.0 - uv);
    col *= pow(vig.x * vig.y * 14.0, 0.3);

    return float4(saturate(col), 1.0);
}
