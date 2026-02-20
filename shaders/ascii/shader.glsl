#version 300 es
precision mediump float;
// ASCII — Terminal character-cell rendering shader
// Converts the scene into a grid of brightness-mapped ASCII characters
// rendered as filled block glyphs in green-on-black terminal style
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }

// 8x8 bitmap font — 10 density glyphs ordered light to dark:
// space, period, colon, dash, plus, percent, hash, @ (8 total, indexed 0-7 by brightness)
// Each row is an 8-bit mask (bit7 = leftmost pixel)
float bitmapDensity(int level, int cx, int cy)
{
    if (cx < 0 || cx > 7 || cy < 0 || cy > 7) return 0.0;
    level = clamp(level, 0, 7);

    // 8 glyphs x 8 rows — flattened [level * 8 + row]
    const uint glyphs[64] = uint[64](
        // 0: space (empty)
        0x00u,0x00u,0x00u,0x00u,0x00u,0x00u,0x00u,0x00u,
        // 1: period  .
        0x00u,0x00u,0x00u,0x00u,0x00u,0x00u,0x18u,0x00u,
        // 2: colon   :
        0x00u,0x18u,0x18u,0x00u,0x00u,0x18u,0x18u,0x00u,
        // 3: dash    -
        0x00u,0x00u,0x00u,0x7Eu,0x00u,0x00u,0x00u,0x00u,
        // 4: plus    +
        0x00u,0x18u,0x18u,0x7Eu,0x7Eu,0x18u,0x18u,0x00u,
        // 5: percent %
        0x62u,0x66u,0x0Cu,0x18u,0x30u,0x66u,0x46u,0x00u,
        // 6: hash    #
        0x24u,0x24u,0xFFu,0x24u,0xFFu,0x24u,0x24u,0x00u,
        // 7: at      @ (densest)
        0x3Cu,0x42u,0x99u,0xA5u,0xA5u,0x9Eu,0x40u,0x3Cu
    );

    uint row = glyphs[level * 8 + cy];
    return ((row >> (7 - cx)) & 1u) != 0u ? 1.0 : 0.0;
}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // ── Cell grid — 8x8 px character cells ───────────────────────────────
    int   cellW   = 8;
    int   cellH   = 8;
    float cellCol = floor(gl_FragCoord.x / cellW);
    float cellRow = floor(gl_FragCoord.y / cellH);

    // UV of the cell's center for sampling source brightness
    vec2 cellUV = vec2(
        (cellCol + 0.5) * cellW / 1920.0,
        (cellRow + 0.5) * cellH / 1080.0);

    // ── Sample brightness of source at this cell ──────────────────────────
    float luma = dot(texture(iChannel0, cellUV).rgb, vec3(0.299, 0.587, 0.114));

    // ── Select glyph by brightness level ──────────────────────────────────
    int level = int(luma * 7.99);

    // ── Position within the 8x8 cell ──────────────────────────────────────
    int cx = int(mod(gl_FragCoord.x, float(cellW)));
    int cy = int(mod(gl_FragCoord.y, float(cellH)));

    // ── Look up bitmap pixel ───────────────────────────────────────────────
    float bit = bitmapDensity(level, cx, cy);

    // ── Terminal green palette with phosphor warmth ────────────────────────
    // Foreground: bright phosphor green
    // Background: near-black with faint green tint
    vec3 fg = vec3(0.10, 1.00, 0.25) * (0.8 + 0.2 * luma);   // brighter for hot areas
    vec3 bg = vec3(0.00, 0.04, 0.01);

    vec3 col = mix(bg, fg, bit);

    // ── Scanline darkening between cell rows ──────────────────────────────
    float scanline = 1.0 - 0.2 * step(6.5, mod(gl_FragCoord.y, float(cellH)));
    col *= scanline;

    // ── CRT flicker ───────────────────────────────────────────────────────
    float flicker = 0.94 + 0.06 * sin(iTime * 11.3);
    col *= flicker;

    // ── Phosphor glow — bright cells bleed into surroundings ─────────────
    // Sample neighbours to accumulate glow
    float glowLuma = 0.0;
    glowLuma += dot(texture(iChannel0, cellUV + vec2( 8.0/1920.0, 0)).rgb, vec3(0.299,0.587,0.114));
    glowLuma += dot(texture(iChannel0, cellUV + vec2(-8.0/1920.0, 0)).rgb, vec3(0.299,0.587,0.114));
    glowLuma += dot(texture(iChannel0, cellUV + vec2(0,  8.0/1080.0)).rgb, vec3(0.299,0.587,0.114));
    glowLuma += dot(texture(iChannel0, cellUV + vec2(0, -8.0/1080.0)).rgb, vec3(0.299,0.587,0.114));
    glowLuma /= 4.0;
    col.g += glowLuma * 0.06 * (1.0 - bit);   // bleeds into dark areas only

    // ── Vignette ──────────────────────────────────────────────────────────
    vec2 vig = uv * (1.0 - uv);
    col *= pow(vig.x * vig.y * 16.0, 0.35);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
