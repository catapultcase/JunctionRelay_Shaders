// X-Ray — Medical radiograph / airport security scanner shader
// Luma inversion + edge bone-glow + density heatmap + film grain + lightbox backlight
//
// Bridge contract:
//   - Input texture bound to t0 (captured WebView2 frame)
//   - Sampler bound to s0 (linear clamp)
//   - TimeBuffer cbuffer at b0 (float time + 12 bytes padding)
//   - VS provides: float4 pos : SV_Position, float2 uv : TEXCOORD0

Texture2D    tex0     : register(t0);
SamplerState sampler0 : register(s0);

cbuffer TimeBuffer : register(b0)
{
    float time;
    float3 _pad;
};

float hash21(float2 p) { float3 p3 = frac(float3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return frac((p3.x+p3.y)*p3.z); }

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
    return saturate(sqrt(gx*gx+gy*gy)*4.0);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 ts = float2(1.0/1920.0, 1.0/1080.0);
    float4 raw  = tex0.Sample(sampler0, uv);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // ── Core inversion — dense = dark (blocks X-rays), empty = bright ─────
    float density  = 1.0 - luma;
    float inverted = pow(density, 1.4);   // slight gamma to compress shadow end

    // ── Edge glow — structural boundaries appear as bright white lines ────
    float edge     = sobelLuma(uv, ts);
    // Edges are very bright on X-ray — bone and metal boundaries
    float edgeGlow = pow(edge, 0.6) * 0.7;

    // ── Combine into monochrome radiograph base ────────────────────────────
    float xray = saturate(inverted + edgeGlow);

    // ── Lightbox backlight — slight cool blue-white glow at the centre ────
    float2 fromCenter = uv - 0.5;
    float  lightbox   = exp(-dot(fromCenter, fromCenter) * 2.5) * 0.06;

    // ── Film base colour — X-ray film is blue-tinted, not pure grey ───────
    // Dense areas (bright on film) lean cooler; thin areas lean warm
    float3 filmColor;
    filmColor.r = xray * 0.82;
    filmColor.g = xray * 0.92;
    filmColor.b = xray * 1.00 + lightbox;

    // Hot-spot density map: very dense areas get a faint orange-red tint
    // (like a radiologist's highlight on a suspicious area)
    float hotspot = smoothstep(0.75, 1.0, xray);
    filmColor    += hotspot * float3(0.08, 0.02, -0.05);

    // ── Film grain — X-ray film is coarse ─────────────────────────────────
    float grain  = hash21(uv * float2(960.0, 540.0) + frac(time * 11.1)) - 0.5;
    filmColor   += grain * 0.04;

    // ── Scan line artifact — some X-ray digitizers leave horizontal lines ─
    float scanArt = 1.0 - 0.04 * step(0.95, frac(pos.y * 0.25));
    filmColor    *= scanArt;

    // ── Lightbox frame edge — the physical light panel is slightly visible ─
    float2 frame  = smoothstep(0.0, 0.02, uv) * smoothstep(1.0, 0.98, uv);
    float  frameMask = frame.x * frame.y;
    filmColor    *= lerp(0.3, 1.0, frameMask);

    return float4(saturate(filmColor), 1.0);
}
