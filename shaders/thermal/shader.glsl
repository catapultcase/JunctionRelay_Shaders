#version 300 es
precision mediump float;
// Thermal — military FLIR infrared camera shader
// Heat signature palette + edge detection + sensor noise + targeting reticle ghost
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime


// ── Helpers ──────────────────────────────────────────────────────────────────


uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── FLIR color palette ────────────────────────────────────────────────────────
// Classic "iron/hot" FLIR: black -> purple -> red -> orange -> yellow -> white
// t in [0,1] maps cold->hot
vec3 flirPalette(float t)
{
    t = clamp(t, 0.0, 1.0);

    // 5 control points
    vec3 c0 = vec3(0.00, 0.00, 0.00); // cold — black
    vec3 c1 = vec3(0.28, 0.00, 0.42); // cool  — deep purple
    vec3 c2 = vec3(0.78, 0.05, 0.05); // warm  — red
    vec3 c3 = vec3(1.00, 0.55, 0.00); // hot   — orange
    vec3 c4 = vec3(1.00, 1.00, 1.00); // fire  — white

    vec3 col;
    if      (t < 0.25) col = mix(c0, c1, t * 4.0);
    else if (t < 0.50) col = mix(c1, c2, (t - 0.25) * 4.0);
    else if (t < 0.75) col = mix(c2, c3, (t - 0.50) * 4.0);
    else               col = mix(c3, c4, (t - 0.75) * 4.0);

    return col;
}

// ── Sobel edge detection ──────────────────────────────────────────────────────
float sobelLuma(vec2 uv, vec2 texelSize)
{
    float tl = dot(texture(iChannel0, uv + texelSize * vec2(-1,-1)).rgb, vec3(0.299,0.587,0.114));
    float tc = dot(texture(iChannel0, uv + texelSize * vec2( 0,-1)).rgb, vec3(0.299,0.587,0.114));
    float tr = dot(texture(iChannel0, uv + texelSize * vec2( 1,-1)).rgb, vec3(0.299,0.587,0.114));
    float ml = dot(texture(iChannel0, uv + texelSize * vec2(-1, 0)).rgb, vec3(0.299,0.587,0.114));
    float mr = dot(texture(iChannel0, uv + texelSize * vec2( 1, 0)).rgb, vec3(0.299,0.587,0.114));
    float bl = dot(texture(iChannel0, uv + texelSize * vec2(-1, 1)).rgb, vec3(0.299,0.587,0.114));
    float bc = dot(texture(iChannel0, uv + texelSize * vec2( 0, 1)).rgb, vec3(0.299,0.587,0.114));
    float br = dot(texture(iChannel0, uv + texelSize * vec2( 1, 1)).rgb, vec3(0.299,0.587,0.114));

    float gx = -tl - 2.0*ml - bl + tr + 2.0*mr + br;
    float gy = -tl - 2.0*tc - tr + bl + 2.0*bc + br;
    return clamp(sqrt(gx*gx + gy*gy) * 3.0, 0.0, 1.0);
}

// ── Main ─────────────────────────────────────────────────────────────────────

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    vec2 texelSize = vec2(1.0 / 1920.0, 1.0 / 1080.0);

    // ── 1. Sensor micro-jitter — FLIR cameras have slight registration noise ──
    float jitterT  = floor(iTime * 24.0);   // 24fps sensor tick
    vec2 jitter  = vec2(
        (hash21(vec2(jitterT, 0.3)) - 0.5) * 0.0008,
        (hash21(vec2(jitterT, 0.7)) - 0.5) * 0.0004);
    vec2 sampleUV = clamp(uv + jitter, 0.0, 1.0);

    // ── 2. Sample and convert to heat luminance ───────────────────────────────
    vec4 raw  = texture(iChannel0, sampleUV);
    float  luma = dot(raw.rgb, vec3(0.299, 0.587, 0.114));

    // Slight local blur approximation — thermal sensors have lower resolution
    // than visible light; average with neighbours
    float lumaBlur = luma;
    lumaBlur += dot(texture(iChannel0, sampleUV + texelSize * vec2( 1, 0)).rgb, vec3(0.299,0.587,0.114));
    lumaBlur += dot(texture(iChannel0, sampleUV + texelSize * vec2(-1, 0)).rgb, vec3(0.299,0.587,0.114));
    lumaBlur += dot(texture(iChannel0, sampleUV + texelSize * vec2( 0, 1)).rgb, vec3(0.299,0.587,0.114));
    lumaBlur += dot(texture(iChannel0, sampleUV + texelSize * vec2( 0,-1)).rgb, vec3(0.299,0.587,0.114));
    lumaBlur /= 5.0;

    // Gamma-push the heat map so midtones read as warmer
    float heat = pow(lumaBlur, 0.75);

    // ── 3. Apply FLIR palette ─────────────────────────────────────────────────
    vec3 col = flirPalette(heat);

    // ── 4. Sobel edges — hot white outlines like thermal contrast ─────────────
    float edge = sobelLuma(sampleUV, texelSize);
    // Edges push toward white-hot
    col = mix(col, vec3(1.0, 1.0, 1.0), edge * 0.6);

    // ── 5. Sensor noise — fixed pattern + temporal random ─────────────────────
    // Fixed pattern noise (FPN): each pixel has a slight persistent offset
    float fpn  = (hash21(uv * vec2(1920.0, 1080.0)) - 0.5) * 0.025;
    // Temporal noise: changes every frame
    float tn   = (hash21(uv * vec2(1920.0, 1080.0) + fract(iTime * 317.7)) - 0.5) * 0.018;
    col       += fpn + tn;

    // ── 6. Scan artifact — horizontal banding from detector array readout ──────
    // Real FLIR detectors read out row by row; creates very subtle banding
    float band = 1.0 + 0.012 * sin(uv.y * 1080.0 * 0.5 + iTime * 60.0);
    col       *= band;

    // ── 7. Ghosting — thermal lag (hot objects leave a faint echo) ────────────
    // Sample a slightly offset-in-iTime position — approximate with spatial offset
    float ghostLuma = dot(
        texture(iChannel0, sampleUV + vec2(0.002, 0.001)).rgb,
        vec3(0.299, 0.587, 0.114));
    vec3 ghost = flirPalette(pow(ghostLuma, 0.75));
    col          = mix(col, ghost, 0.08);   // 8% ghost bleed

    // ── 8. Lens vignette — FLIR optics are germanium, heavy falloff ───────────
    vec2 vig  = uv * (1.0 - uv);
    float  vign = pow(vig.x * vig.y * 14.0, 0.45);
    col        *= mix(0.3, 1.0, vign);      // doesn't go fully black — sensor glow

    // ── 9. HUD overlay — minimal targeting reticle ────────────────────────────
    vec2 c     = uv - 0.5;               // centered coords
    float  cx    = abs(c.x);
    float  cy    = abs(c.y);

    // Crosshair gap: lines start at 0.015 from center, end at 0.06
    float  hLine = step(0.015, cx) * step(cx, 0.055) * step(cy, 0.0008);
    float  vLine = step(0.015, cy) * step(cy, 0.055) * step(cx, 0.0008);
    float  cross = clamp(hLine + vLine, 0.0, 1.0);

    // Corner brackets at ±0.08 from center
    float bx = step(0.070, cx) * step(cx, 0.090);
    float by = step(0.070, cy) * step(cy, 0.090);
    // Only show where one axis is in bracket range AND other is within bracket width
    float bracket = clamp(
        bx * step(cy, 0.0012) +   // horizontal bracket arms
        by * step(cx, 0.0012), 0.0, 1.0);    // vertical bracket arms

    // Pulsing reticle — slow breathing
    float pulse  = 0.7 + 0.3 * sin(iTime * 1.8);
    float hud    = clamp(cross + bracket, 0.0, 1.0) * pulse;

    // HUD is white-hot on the palette
    col = mix(col, vec3(1.0, 1.0, 1.0), hud * 0.9);

    // ── 10. Slight green tint on the HUD text zone — sensor status ────────────
    // Adds a barely-visible pale green tinge across the top strip (status bar area)
    float statusBar = smoothstep(0.04, 0.0, uv.y) * 0.15;
    col.g          += statusBar;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
