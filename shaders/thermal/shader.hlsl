// Thermal — military FLIR infrared camera shader
// Heat signature palette + edge detection + sensor noise + targeting reticle ghost
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

// ── Helpers ──────────────────────────────────────────────────────────────────

float hash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// ── FLIR color palette ────────────────────────────────────────────────────────
// Classic "iron/hot" FLIR: black -> purple -> red -> orange -> yellow -> white
// t in [0,1] maps cold->hot
float3 flirPalette(float t)
{
    t = saturate(t);

    // 5 control points
    float3 c0 = float3(0.00, 0.00, 0.00); // cold — black
    float3 c1 = float3(0.28, 0.00, 0.42); // cool  — deep purple
    float3 c2 = float3(0.78, 0.05, 0.05); // warm  — red
    float3 c3 = float3(1.00, 0.55, 0.00); // hot   — orange
    float3 c4 = float3(1.00, 1.00, 1.00); // fire  — white

    float3 col;
    if      (t < 0.25) col = lerp(c0, c1, t * 4.0);
    else if (t < 0.50) col = lerp(c1, c2, (t - 0.25) * 4.0);
    else if (t < 0.75) col = lerp(c2, c3, (t - 0.50) * 4.0);
    else               col = lerp(c3, c4, (t - 0.75) * 4.0);

    return col;
}

// ── Sobel edge detection ──────────────────────────────────────────────────────
float sobelLuma(float2 uv, float2 texelSize)
{
    float tl = dot(tex0.Sample(sampler0, uv + texelSize * float2(-1,-1)).rgb, float3(0.299,0.587,0.114));
    float tc = dot(tex0.Sample(sampler0, uv + texelSize * float2( 0,-1)).rgb, float3(0.299,0.587,0.114));
    float tr = dot(tex0.Sample(sampler0, uv + texelSize * float2( 1,-1)).rgb, float3(0.299,0.587,0.114));
    float ml = dot(tex0.Sample(sampler0, uv + texelSize * float2(-1, 0)).rgb, float3(0.299,0.587,0.114));
    float mr = dot(tex0.Sample(sampler0, uv + texelSize * float2( 1, 0)).rgb, float3(0.299,0.587,0.114));
    float bl = dot(tex0.Sample(sampler0, uv + texelSize * float2(-1, 1)).rgb, float3(0.299,0.587,0.114));
    float bc = dot(tex0.Sample(sampler0, uv + texelSize * float2( 0, 1)).rgb, float3(0.299,0.587,0.114));
    float br = dot(tex0.Sample(sampler0, uv + texelSize * float2( 1, 1)).rgb, float3(0.299,0.587,0.114));

    float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
    float gy = -tl - 2.0*tc - tr + bl + 2.0*bc + br;
    return saturate(sqrt(gx*gx + gy*gy) * 3.0);
}

// ── Main ─────────────────────────────────────────────────────────────────────

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 texelSize = float2(1.0 / 1920.0, 1.0 / 1080.0);

    // ── 1. Sensor micro-jitter — FLIR cameras have slight registration noise ──
    float jitterT  = floor(time * 24.0);   // 24fps sensor tick
    float2 jitter  = float2(
        (hash21(float2(jitterT, 0.3)) - 0.5) * 0.0008,
        (hash21(float2(jitterT, 0.7)) - 0.5) * 0.0004);
    float2 sampleUV = saturate(uv + jitter);

    // ── 2. Sample and convert to heat luminance ───────────────────────────────
    float4 raw  = tex0.Sample(sampler0, sampleUV);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // Slight local blur approximation — thermal sensors have lower resolution
    // than visible light; average with neighbours
    float lumaBlur = luma;
    lumaBlur += dot(tex0.Sample(sampler0, sampleUV + texelSize * float2( 1, 0)).rgb, float3(0.299,0.587,0.114));
    lumaBlur += dot(tex0.Sample(sampler0, sampleUV + texelSize * float2(-1, 0)).rgb, float3(0.299,0.587,0.114));
    lumaBlur += dot(tex0.Sample(sampler0, sampleUV + texelSize * float2( 0, 1)).rgb, float3(0.299,0.587,0.114));
    lumaBlur += dot(tex0.Sample(sampler0, sampleUV + texelSize * float2( 0,-1)).rgb, float3(0.299,0.587,0.114));
    lumaBlur /= 5.0;

    // Gamma-push the heat map so midtones read as warmer
    float heat = pow(lumaBlur, 0.75);

    // ── 3. Apply FLIR palette ─────────────────────────────────────────────────
    float3 col = flirPalette(heat);

    // ── 4. Sobel edges — hot white outlines like thermal contrast ─────────────
    float edge = sobelLuma(sampleUV, texelSize);
    // Edges push toward white-hot
    col = lerp(col, float3(1.0, 1.0, 1.0), edge * 0.6);

    // ── 5. Sensor noise — fixed pattern + temporal random ─────────────────────
    // Fixed pattern noise (FPN): each pixel has a slight persistent offset
    float fpn  = (hash21(uv * float2(1920.0, 1080.0)) - 0.5) * 0.025;
    // Temporal noise: changes every frame
    float tn   = (hash21(uv * float2(1920.0, 1080.0) + frac(time * 317.7)) - 0.5) * 0.018;
    col       += fpn + tn;

    // ── 6. Scan artifact — horizontal banding from detector array readout ──────
    // Real FLIR detectors read out row by row; creates very subtle banding
    float band = 1.0 + 0.012 * sin(uv.y * 1080.0 * 0.5 + time * 60.0);
    col       *= band;

    // ── 7. Ghosting — thermal lag (hot objects leave a faint echo) ────────────
    // Sample a slightly offset-in-time position — approximate with spatial offset
    float ghostLuma = dot(
        tex0.Sample(sampler0, sampleUV + float2(0.002, 0.001)).rgb,
        float3(0.299, 0.587, 0.114));
    float3 ghost = flirPalette(pow(ghostLuma, 0.75));
    col          = lerp(col, ghost, 0.08);   // 8% ghost bleed

    // ── 8. Lens vignette — FLIR optics are germanium, heavy falloff ───────────
    float2 vig  = uv * (1.0 - uv);
    float  vign = pow(vig.x * vig.y * 14.0, 0.45);
    col        *= lerp(0.3, 1.0, vign);      // doesn't go fully black — sensor glow

    // ── 9. HUD overlay — minimal targeting reticle ────────────────────────────
    float2 c     = uv - 0.5;               // centered coords
    float  cx    = abs(c.x);
    float  cy    = abs(c.y);

    // Crosshair gap: lines start at 0.015 from center, end at 0.06
    float  hLine = step(0.015, cx) * step(cx, 0.055) * step(cy, 0.0008);
    float  vLine = step(0.015, cy) * step(cy, 0.055) * step(cx, 0.0008);
    float  cross = saturate(hLine + vLine);

    // Corner brackets at ±0.08 from center
    float bx = step(0.070, cx) * step(cx, 0.090);
    float by = step(0.070, cy) * step(cy, 0.090);
    // Only show where one axis is in bracket range AND other is within bracket width
    float bracket = saturate(
        bx * step(cy, 0.0012) +   // horizontal bracket arms
        by * step(cx, 0.0012));    // vertical bracket arms

    // Pulsing reticle — slow breathing
    float pulse  = 0.7 + 0.3 * sin(time * 1.8);
    float hud    = saturate(cross + bracket) * pulse;

    // HUD is white-hot on the palette
    col = lerp(col, float3(1.0, 1.0, 1.0), hud * 0.9);

    // ── 10. Slight green tint on the HUD text zone — sensor status ────────────
    // Adds a barely-visible pale green tinge across the top strip (status bar area)
    float statusBar = smoothstep(0.04, 0.0, uv.y) * 0.15;
    col.g          += statusBar;

    return float4(saturate(col), 1.0);
}
