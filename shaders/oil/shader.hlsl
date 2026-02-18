// Oil — Iridescent oil slick / soap bubble refraction shader
// Thin film interference + surface normal perturbation + chromatic rainbow shift
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

float noise2(float2 p)
{
    float2 i = floor(p); float2 f = frac(p); float2 u = f*f*(3.0-2.0*f);
    return lerp(lerp(hash21(i), hash21(i+float2(1,0)), u.x), lerp(hash21(i+float2(0,1)), hash21(i+float2(1,1)), u.x), u.y);
}

float fbm(float2 p)
{
    float v=0.0, a=0.5;
    float2x2 r = float2x2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<5;i++){ v+=a*noise2(p); p=mul(r,p)*2.1; a*=0.5; }
    return v;
}

// Hue rotation — shift RGB around the colour wheel
float3 hueRotate(float3 col, float angle)
{
    float c = cos(angle), s = sin(angle);
    float3x3 m = float3x3(
        0.299+0.701*c+0.168*s, 0.587-0.587*c+0.330*s, 0.114-0.114*c-0.497*s,
        0.299-0.299*c-0.328*s, 0.587+0.413*c+0.035*s, 0.114-0.114*c+0.292*s,
        0.299-0.300*c+1.250*s, 0.587-0.588*c-1.050*s, 0.114+0.886*c-0.203*s);
    return saturate(mul(m, col));
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── Flowing surface normals — oil moves slowly ─────────────────────────
    float2 flowA = float2(time * 0.04,  time * 0.03);
    float2 flowB = float2(time * -0.02, time * 0.05);

    float heightA = fbm(uv * 4.0 + flowA);
    float heightB = fbm(uv * 6.5 + flowB);
    float height  = (heightA + heightB * 0.5) / 1.5;

    // Derive surface normal from height field gradient
    float eps = 0.002;
    float dhdx = fbm(float2(uv.x+eps, uv.y)*4.0+flowA) - fbm(float2(uv.x-eps, uv.y)*4.0+flowA);
    float dhdy = fbm(float2(uv.x, uv.y+eps)*4.0+flowA) - fbm(float2(uv.x, uv.y-eps)*4.0+flowA);
    float2 normal = float2(dhdx, dhdy) * 8.0;

    // ── Refracted UV — content seen through the oil layer ─────────────────
    float2 refractedUV = saturate(uv + normal * 0.018);
    float4 col = tex0.Sample(sampler0, refractedUV);

    // ── Thin film interference — the actual iridescence ────────────────────
    // Film thickness varies with height field; angle of incidence varies with UV
    float thickness   = height * 2.0 + 0.5;
    float viewAngle   = length(uv - 0.5) * 1.4;
    float filmPhase   = thickness * (1.0 + viewAngle * 0.3);

    // Each wavelength (R/G/B) interferes at a different phase offset
    // producing the characteristic rainbow sheen
    float interferR = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.00);
    float interferG = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.45);
    float interferB = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.90);
    float3 thinFilm = float3(interferR, interferG, interferB);

    // ── Hue-rotate the underlying content by the local film phase ──────────
    float hueShift = filmPhase * 2.1 + time * 0.08;
    float3 tinted  = hueRotate(col.rgb, hueShift);

    // ── Blend: darker areas show more iridescence (like a real oil slick) ──
    float luma      = dot(col.rgb, float3(0.299, 0.587, 0.114));
    float filmStrength = lerp(0.6, 0.15, luma);   // iridescence fades in bright areas

    col.rgb = lerp(col.rgb, tinted * (0.5 + thinFilm * 0.8), filmStrength);

    // ── Specular highlight — oil is shiny ──────────────────────────────────
    float spec = pow(saturate(1.0 - length(normal) * 0.4), 12.0);
    col.rgb   += spec * float3(1.0, 1.0, 1.0) * 0.3;

    // ── Edge darkening — pooling oil is thicker at edges ───────────────────
    float2 vig = uv * (1.0 - uv);
    col.rgb   *= lerp(0.7, 1.0, pow(vig.x * vig.y * 14.0, 0.3));

    return saturate(col);
}
