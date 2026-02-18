// Lenticular — Flip-card lenticular print effect
// Content morphs between two states based on horizontal viewing angle (scan position)
// With lens ridge lines, colour fringing, and depth parallax shift
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Lenticular lens frequency — ridges per screen width
    float lensFreq   = 40.0;
    float lensPhase  = frac(uv.x * lensFreq);   // 0-1 within each lens

    // Simulate viewing angle oscillating slowly (or could be mouse-driven)
    // Time drives the "angle" — like tilting the card back and forth
    float viewAngle = sin(time * 0.4) * 0.5 + 0.5;   // 0=left view, 1=right view

    // Within each lens, left half shows image A, right half shows image B
    // The boundary shifts based on view angle
    float boundary  = viewAngle;
    float showA     = step(lensPhase, boundary);
    float showB     = 1.0 - showA;

    // Image A — the original content
    float4 imgA = tex0.Sample(sampler0, uv);

    // Image B — a processed version: desaturated, hue-shifted, slightly offset
    // (In real lenticular, this would be a completely different image;
    //  here we transform the source to make it visually distinct)
    float lumaB  = dot(imgA.rgb, float3(0.299, 0.587, 0.114));
    float3 rgbB  = float3(1.0 - lumaB * 0.8, lumaB * 0.9, lumaB * 1.1);   // inverted cool
    // Also sample with a slight parallax offset for depth
    float2 parallaxUV = saturate(uv + float2((viewAngle - 0.5) * 0.015, 0));
    float4 imgBsample = tex0.Sample(sampler0, parallaxUV);
    rgbB = lerp(rgbB, 1.0 - imgBsample.rgb, 0.4);
    float4 imgB = float4(rgbB, 1.0);

    // Mix the two images based on lens position
    float4 col = imgA * showA + imgB * showB;

    // Lens ridge lines — physical ridges catch light, appear as bright lines
    float ridge     = smoothstep(0.03, 0.0, abs(lensPhase - 0.0))
                    + smoothstep(0.03, 0.0, abs(lensPhase - 1.0));
    col.rgb        += ridge * 0.3;

    // Colour fringing at the boundary — lenses split white light like a prism
    float boundaryDist = abs(lensPhase - boundary);
    float fringe       = smoothstep(0.08, 0.0, boundaryDist);
    // Red bleeds one way, blue the other
    float rSample = tex0.Sample(sampler0, saturate(uv + float2( 0.003, 0))).r;
    float bSample = tex0.Sample(sampler0, saturate(uv - float2( 0.003, 0))).b;
    col.r += fringe * rSample * 0.4;
    col.b += fringe * bSample * 0.4;

    // Moire pattern — inevitable in lenticular prints
    float moire = sin(uv.x * lensFreq * 3.14159 * 2.0) * sin(uv.y * 35.0) * 0.03;
    col.rgb    += moire;

    // Print surface sheen — slight specular across the lens surface
    float sheen = pow(saturate(sin(uv.x * lensFreq * 6.28) * 0.5 + 0.5), 8.0) * 0.08;
    col.rgb    += sheen;

    // Vignette — card edge darkening
    float2 vig = uv * (1.0 - uv);
    col.rgb   *= lerp(0.6, 1.0, pow(vig.x * vig.y * 12.0, 0.3));

    return float4(saturate(col.rgb), 1.0);
}
