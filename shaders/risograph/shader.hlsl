// Risograph — Trendy two-colour stencil print aesthetic
// Hard halftone dots + misregistered colour layers + paper texture + ink saturation
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}
float noise2(float2 p){float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);}

// Rotated halftone dot — classic print screen angle
float halftone(float2 uv, float frequency, float angle, float threshold)
{
    float s = sin(angle), c = cos(angle);
    float2 rotUV = float2(c*uv.x - s*uv.y, s*uv.x + c*uv.y);
    float2 cellUV = frac(rotUV * frequency) - 0.5;
    float  dotR = length(cellUV);
    return step(dotR, threshold * 0.5);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 raw = tex0.Sample(sampler0, uv);

    // Separate into two colour channels for the two ink passes
    float luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // Ink colour 1: Fluorescent pink / coral
    float3 ink1 = float3(0.95, 0.15, 0.35);
    // Ink colour 2: Deep teal / cyan
    float3 ink2 = float3(0.05, 0.60, 0.65);

    // Channel extraction — ink1 driven by warm tones, ink2 by cool tones
    float warm = saturate(raw.r - raw.b * 0.5);
    float cool = saturate(raw.b * 0.8 + raw.g * 0.4 - raw.r * 0.3);

    // Halftone for each ink at different angles (classic: 15° and 75°)
    float freq = 80.0;
    float dot1 = halftone(uv, freq, 0.26,  sqrt(warm) * 0.9);   // ~15°
    float dot2 = halftone(uv, freq, 1.31,  sqrt(cool) * 0.9);   // ~75°

    // Misregistration — each ink plate is slightly offset
    float2 misreg = float2(0.0015, 0.001);
    float dot1mis = halftone(uv + misreg, freq, 0.26, sqrt(warm) * 0.9);
    float dot2mis = halftone(uv - misreg, freq, 1.31, sqrt(cool) * 0.9);

    // Paper base — cream/off-white
    float3 paper = float3(0.96, 0.93, 0.86);

    // Paper texture — subtle noise
    float paperNoise = noise2(uv * float2(800, 500)) * 0.04
                     + noise2(uv * float2(200, 130)) * 0.02;
    paper -= paperNoise;

    // Compose: paper + ink layers (multiply blend like real ink on paper)
    float3 col = paper;
    // First ink pass
    col = lerp(col, col * ink1 * 1.1, dot1mis * 0.9);
    // Second ink pass (slightly offset)
    col = lerp(col, col * ink2 * 1.1, dot2mis * 0.9);
    // Overlap of both inks — creates a dark moiré colour
    float overlap = dot1 * dot2;
    col = lerp(col, ink1 * ink2 * 0.6, overlap);

    // Ink bleed — dots slightly fuzzy at edges (ink soaks into paper)
    float bleed1 = halftone(uv, freq * 0.95, 0.26, sqrt(warm) * 1.05);
    float bleed2 = halftone(uv, freq * 0.95, 1.31, sqrt(cool) * 1.05);
    col = lerp(col, col * 0.85, (bleed1 - dot1) * 0.3 + (bleed2 - dot2) * 0.3);

    // Slight ink saturation boost — Riso inks are very saturated
    float colLuma = dot(col, float3(0.299,0.587,0.114));
    col = lerp(float3(colLuma,colLuma,colLuma), col, 1.4);

    return float4(saturate(col), 1.0);
}
