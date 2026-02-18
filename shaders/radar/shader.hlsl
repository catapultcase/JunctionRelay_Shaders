// Radar — Military PPI radar sweep display
// Rotating scan line + contact paint & decay + green phosphor + range rings
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 centered = uv * 2.0 - 1.0;
    centered.x *= 1920.0 / 1080.0;   // aspect correct

    float dist  = length(centered);
    float angle = atan2(centered.y, centered.x);   // -PI to PI

    // Sweep angle — full rotation every 4 seconds
    float sweepSpeed = 3.14159 * 2.0 / 4.0;
    float sweepAngle = fmod(time * sweepSpeed, 3.14159 * 2.0) - 3.14159;

    // Angular distance from sweep beam (accounting for wrap)
    float angleDiff = angle - sweepAngle;
    angleDiff = angleDiff - floor((angleDiff + 3.14159) / (2.0 * 3.14159)) * 2.0 * 3.14159;

    // Sweep beam — bright leading edge, trailing phosphor decay
    float beamWidth   = 0.05;
    float decayLength = 1.8;   // radians of trail
    float beam = 0.0;
    if (angleDiff > -beamWidth && angleDiff < 0.0)
        beam = 1.0;   // leading edge
    else if (angleDiff < 0.0 && angleDiff > -decayLength)
        beam = exp(angleDiff * 2.5);   // exponential phosphor decay

    // Sample source for contact detection
    float4 raw  = tex0.Sample(sampler0, uv);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // Contacts — bright areas in the source become radar returns
    // Only visible in the sweep wake (phosphor painted and decaying)
    float decayMask = exp(min(angleDiff, 0.0) * 1.8) * step(angleDiff, 0.0);
    float contact   = luma * decayMask * 1.5;

    // Combine beam and contacts
    float signal = saturate(beam * 0.8 + contact);

    // Green phosphor glow
    float3 phosphor = float3(0.05, signal, 0.05 * signal);
    phosphor       += float3(0.0, pow(signal, 0.5) * 0.3, 0.0);   // bloom

    // Range rings — concentric circles at fixed intervals
    float ringSpacing = 0.25;
    float ring = smoothstep(0.008, 0.0, abs(fmod(dist, ringSpacing) - 0.0));
    ring      += smoothstep(0.004, 0.0, abs(fmod(dist, ringSpacing) - ringSpacing * 0.5)) * 0.3;
    phosphor  += float3(0.0, ring * 0.25, 0.0);

    // Crosshair
    float ch = smoothstep(0.003, 0.0, abs(centered.x)) + smoothstep(0.003, 0.0, abs(centered.y));
    phosphor += float3(0.0, saturate(ch) * 0.2, 0.0);

    // Clip to circular display area
    float circleMask = step(dist, 1.0);
    phosphor *= circleMask;

    // Bezel — dark border outside the scope face
    float3 col = phosphor + float3(0.0, 0.01, 0.0) * circleMask;

    // Phosphor grain
    col.g += (hash21(uv + frac(time * 47.0)) - 0.5) * 0.015 * circleMask;

    return float4(saturate(col), 1.0);
}
