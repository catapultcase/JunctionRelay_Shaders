// MRI — Medical magnetic resonance imaging display
// Greyscale with clinical blue tint + slice artifacts + k-space noise + field inhomogeneity
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}
float noise2(float2 p){float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 raw  = tex0.Sample(sampler0, uv);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // MRI signal is fundamentally T1/T2 weighted — remap tones
    // Bright = high signal (fat/fluid), dark = low signal (air/cortical bone)
    float mriSignal = pow(luma, 0.8);   // slight gamma lift — MRI images are bright

    // Field inhomogeneity — B0 field variation causes slow intensity shading
    // Simulated as a smooth low-frequency intensity gradient across the FOV
    float inhomo = noise2(uv * 2.5) * 0.12 - 0.06;
    mriSignal = saturate(mriSignal + inhomo);

    // Gibbs ringing / truncation artifact — bright edges produce oscillating bands
    // Approximate with a sin wave perpendicular to high-gradient areas
    float2 ts = float2(1.0/1920.0, 1.0/1080.0);
    float  gx = tex0.Sample(sampler0,uv+ts*float2(2,0)).r - tex0.Sample(sampler0,uv-ts*float2(2,0)).r;
    float  gy = tex0.Sample(sampler0,uv+ts*float2(0,2)).g - tex0.Sample(sampler0,uv-ts*float2(0,2)).g;
    float  gradMag = saturate(sqrt(gx*gx+gy*gy) * 8.0);
    float  gibbs   = sin(luma * 60.0) * 0.03 * gradMag;
    mriSignal      = saturate(mriSignal + gibbs);

    // Gaussian noise — MRI has thermal noise from the receiver coil
    float noiseR = (hash21(uv * float2(1920,1080) + float2(time * 7.3, 0)) - 0.5);
    float noiseI = (hash21(uv * float2(1920,1080) + float2(0, time * 7.3)) - 0.5);
    // Rician noise (magnitude of complex Gaussian — standard in MRI)
    float ricianNoise = sqrt(noiseR*noiseR + noiseI*noiseI) * 0.025;
    mriSignal = saturate(mriSignal + ricianNoise - 0.012);

    // k-space spike — periodic ghosting from gradient errors
    // Creates faint copies of bright structures offset in phase-encode direction
    float ghost = dot(tex0.Sample(sampler0, float2(uv.x, frac(uv.y + 0.15))).rgb, float3(0.299,0.587,0.114)) * 0.06;
    mriSignal = saturate(mriSignal + ghost * gradMag);

    // Clinical blue-grey MRI monitor colour
    float3 col;
    col.r = mriSignal * 0.82;
    col.g = mriSignal * 0.91;
    col.b = mriSignal * 1.00;

    // Windowing — MRI is always displayed with a specific window/level
    // Slight contrast enhancement in midtones (typical clinical window)
    col = saturate((col - 0.1) * 1.25);

    // PACS viewer black border
    float2 border = smoothstep(0.0, 0.008, uv) * smoothstep(1.0, 0.992, uv);
    col *= border.x * border.y;

    // Measurement overlay — faint crosshair at image centre
    float2 ch = smoothstep(0.002, 0.0, abs(uv - 0.5));
    col += saturate(ch.x + ch.y) * float3(0.05, 0.1, 0.15) * 0.5;

    return float4(saturate(col), 1.0);
}
