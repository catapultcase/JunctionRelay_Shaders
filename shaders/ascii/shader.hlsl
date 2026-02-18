// ASCII — Terminal character-cell rendering shader
// Converts the scene into a grid of brightness-mapped ASCII characters
// rendered as filled block glyphs in green-on-black terminal style
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

// 8x8 bitmap font — 10 density glyphs ordered light to dark:
// space, period, colon, dash, plus, percent, hash, @ (8 total, indexed 0-7 by brightness)
// Each row is an 8-bit mask (bit7 = leftmost pixel)
float bitmapDensity(int level, int cx, int cy)
{
    if (cx < 0 || cx > 7 || cy < 0 || cy > 7) return 0.0;
    level = clamp(level, 0, 7);

    // 8 glyphs x 8 rows
    static const uint glyphs[8][8] = {
        // 0: space (empty)
        { 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 },
        // 1: period  .
        { 0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x00 },
        // 2: colon   :
        { 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00 },
        // 3: dash    -
        { 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00 },
        // 4: plus    +
        { 0x00,0x18,0x18,0x7E,0x7E,0x18,0x18,0x00 },
        // 5: percent %
        { 0x62,0x66,0x0C,0x18,0x30,0x66,0x46,0x00 },
        // 6: hash    #
        { 0x24,0x24,0xFF,0x24,0xFF,0x24,0x24,0x00 },
        // 7: at      @ (densest)
        { 0x3C,0x42,0x99,0xA5,0xA5,0x9E,0x40,0x3C },
    };

    uint row = glyphs[level][cy];
    return ((row >> (7 - cx)) & 1u) ? 1.0 : 0.0;
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── Cell grid — 8x8 px character cells ───────────────────────────────
    int   cellW   = 8;
    int   cellH   = 8;
    float cellCol = floor(pos.x / cellW);
    float cellRow = floor(pos.y / cellH);

    // UV of the cell's center for sampling source brightness
    float2 cellUV = float2(
        (cellCol + 0.5) * cellW / 1920.0,
        (cellRow + 0.5) * cellH / 1080.0);

    // ── Sample brightness of source at this cell ──────────────────────────
    float luma = dot(tex0.Sample(sampler0, cellUV).rgb, float3(0.299, 0.587, 0.114));

    // ── Select glyph by brightness level ──────────────────────────────────
    int level = (int)(luma * 7.99);

    // ── Position within the 8x8 cell ──────────────────────────────────────
    int cx = (int)fmod(pos.x, (float)cellW);
    int cy = (int)fmod(pos.y, (float)cellH);

    // ── Look up bitmap pixel ───────────────────────────────────────────────
    float bit = bitmapDensity(level, cx, cy);

    // ── Terminal green palette with phosphor warmth ────────────────────────
    // Foreground: bright phosphor green
    // Background: near-black with faint green tint
    float3 fg = float3(0.10, 1.00, 0.25) * (0.8 + 0.2 * luma);   // brighter for hot areas
    float3 bg = float3(0.00, 0.04, 0.01);

    float3 col = lerp(bg, fg, bit);

    // ── Scanline darkening between cell rows ──────────────────────────────
    float scanline = 1.0 - 0.2 * step(6.5, fmod(pos.y, (float)cellH));
    col *= scanline;

    // ── CRT flicker ───────────────────────────────────────────────────────
    float flicker = 0.94 + 0.06 * sin(time * 11.3);
    col *= flicker;

    // ── Phosphor glow — bright cells bleed into surroundings ─────────────
    // Sample neighbours to accumulate glow
    float glowLuma = 0.0;
    glowLuma += dot(tex0.Sample(sampler0, cellUV + float2( 8.0/1920.0, 0)).rgb, float3(0.299,0.587,0.114));
    glowLuma += dot(tex0.Sample(sampler0, cellUV + float2(-8.0/1920.0, 0)).rgb, float3(0.299,0.587,0.114));
    glowLuma += dot(tex0.Sample(sampler0, cellUV + float2(0,  8.0/1080.0)).rgb, float3(0.299,0.587,0.114));
    glowLuma += dot(tex0.Sample(sampler0, cellUV + float2(0, -8.0/1080.0)).rgb, float3(0.299,0.587,0.114));
    glowLuma /= 4.0;
    col.g += glowLuma * 0.06 * (1.0 - bit);   // bleeds into dark areas only

    // ── Vignette ──────────────────────────────────────────────────────────
    float2 vig = uv * (1.0 - uv);
    col *= pow(vig.x * vig.y * 16.0, 0.35);

    return float4(saturate(col), 1.0);
}
