#version 300 es
precision mediump float;
// VHS pixel shader — color bleeding, luminance noise, tracking glitches, tape warble.
// Self-contained: driven entirely by iTime + UV, no extra cbuffers needed.
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime


// ── Helpers ─────────────────────────────────────────────────────────────────

// Cheap hash — produces pseudo-random float in [0,1]

uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash(vec2 p)
{
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

// Smooth per-row hash (changes slowly with iTime) for tape warble
float rowHash(float row, float t)
{
    return hash(vec2(row, floor(t * 12.0)));
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // ── Tape warble: wobble U slightly based on scanline row and iTime ─────────
    float row        = floor(gl_FragCoord.y);
    float warble     = (rowHash(row, iTime) - 0.5) * 0.003;
    // Add a slower, broader wave on top
    warble          += sin(uv.y * 18.0 + iTime * 3.5) * 0.0008;
    vec2 warpedUV  = vec2(uv.x + warble, uv.y);

    // ── Horizontal tracking glitch bands ─────────────────────────────────────
    // A narrow band drifts up the screen every few seconds
    float bandSpeed  = fract(iTime * 0.18);
    float bandY      = fract(uv.y - bandSpeed);
    float glitchBand = step(0.97, bandY); // ~3% of screen height
    // Inside the band, shift U dramatically
    warpedUV.x      += glitchBand * (hash(vec2(floor(iTime * 6.0), row)) - 0.5) * 0.06;

    // ── Sample with channel separation (chroma bleed) ─────────────────────────
    float bleed = 0.004 + glitchBand * 0.012;
    float r = texture(iChannel0, vec2(warpedUV.x + bleed, warpedUV.y)).r;
    float g = texture(iChannel0, warpedUV).g;
    float b = texture(iChannel0, vec2(warpedUV.x - bleed, warpedUV.y)).b;
    vec4 col = vec4(r, g, b, 1.0);

    // ── VHS color grading: desaturate slightly, warm up whites ────────────────
    float luma    = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb       = mix(col.rgb, vec3(luma, luma, luma), 0.25); // mild desaturation
    col.rgb      *= vec3(1.05, 1.0, 0.88);                       // warm / slightly yellowed

    // ── Luminance noise (tape grain) ─────────────────────────────────────────
    float grain   = hash(vec2(uv.x + fract(iTime * 47.3), uv.y + fract(iTime * 31.7)));
    grain         = (grain - 0.5) * 0.08;
    col.rgb      += grain;

    // ── Scanlines (softer than hologram — VHS lines are subtle) ──────────────
    float scanline = 0.88 + 0.12 * sin(gl_FragCoord.y * 3.14159);
    col.rgb       *= scanline;

    // ── Horizontal luminance smear on the glitch band ─────────────────────────
    col.rgb       = mix(col.rgb, col.rgb * vec3(1.3, 1.1, 0.8), glitchBand * 0.6);

    // ── Vignette ──────────────────────────────────────────────────────────────
    vec2 vig    = uv * (1.0 - uv.yx);
    float  vign   = pow(vig.x * vig.y * 15.0, 0.4);
    col.rgb      *= mix(0.5, 1.0, vign);

    // ── Occasional full-frame brightness drop (tape dropout) ──────────────────
    float dropout  = 1.0 - 0.35 * step(0.97, fract(sin(floor(iTime * 5.0) * 127.1) * 43758.5));
    col.rgb       *= dropout;

    fragColor = clamp(col, 0.0, 1.0);
}
