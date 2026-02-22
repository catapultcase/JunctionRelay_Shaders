// Rain Window — Glass Rain Overlay
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Texture overlay: background viewed through wet, condensed glass.
// Drops cling to the glass, then slide with accelerating speed.
// Larger drops cling less and fall faster. Adjacent drops merge.
//
// Inputs: iChannel0, iTime, iResolution, rainAmount, fogAmount, dropSize, pathVariance

// ── Hash functions ────────────────────────────────────────────

float rng(float n) {
    return fract(cos(n * 71.97) * 41415.93);
}

float rng2(vec2 p) {
    return rng(dot(p, vec2(91.7, 173.3)));
}

vec2 rng22(vec2 p) {
    return vec2(rng2(p), rng2(p + 73.15));
}

// ── Rolling drops ─────────────────────────────────────────────
// Each column holds 4 independent drop slots. Every slot cycles through:
//   CLING  — held by surface tension, stationary
//   SLIDE  — released, falls with ease-in acceleration
//   RESET  — exits bottom, new drop forms near the top
//
// Larger drops cling for a shorter fraction of the cycle and
// accelerate more steeply (size → speed correlation).
// Three adjacent columns are sampled so drops near cell boundaries
// merge into a single shape via metaball field accumulation.
//
// hashSeed: per-layer offset so the two layers are decorrelated.
// Returns: vec2(dropHeight, trailClearing)

vec2 rollingDrops(vec2 uv, float t, float cols, float hashSeed, float speed) {
    float aspect = iResolution.x / iResolution.y;
    float colW   = aspect / cols;              // column width in UV units

    // Column index and fractional position within it
    float colX   = (uv.x / aspect + 0.5) * cols;
    float colId  = floor(colX);
    float colFrac = fract(colX);

    float field = 0.0;
    float trail = 0.0;

    // Check left, centre, right columns so nearby drops merge
    for (int dc = -1; dc <= 1; dc++) {
        float nCol  = colId + float(dc);
        float nFrac = colFrac - float(dc);   // x within neighbor column

        // Column sparsity — roughly one in four columns has no drops
        if (rng(nCol * 91.3 + hashSeed) < 0.25) continue;

        // ── 4 independent slots per column ──────────────────────────────
        for (int slot = 0; slot < 4; slot++) {
            float base = nCol * 7.13 + float(slot) * 53.7 + hashSeed;
            float sa = rng(base);
            float sb = rng(base + 111.5);
            float sc = rng(base + 222.3);   // used for sizeNorm
            float sd = rng(base + 333.7);

            float sizeNorm = sc;            // 0 = tiny, 1 = large
            float radius   = (0.03 + sizeNorm * 0.07) * dropSize;

            // Lifecycle timing
            //   - longer period for slow/rare large drops
            //   - big drops cling for a SMALLER fraction (less surface tension)
            float period    = mix(8.0, 22.0, sa) / speed;
            float clingFrac = mix(0.87, 0.48, sizeNorm);
            float clingDur  = period * clingFrac;
            float localT    = mod(t + sa * period * 3.71, period);

            // Y on screen: 0 = top, 1 = bottom
            // Drops form in the upper portion so we always see them start
            float startY = 0.03 + sd * 0.45;

            float dropY;
            float sliding;

            if (localT < clingDur) {
                // CLINGING — holds its position
                dropY   = startY;
                sliding = 0.0;
            } else {
                // SLIDING — ease-in: starts slow, accelerates as it gains momentum
                float slideT = (localT - clingDur) / (period - clingDur);
                float accel  = mix(1.5, 3.2, sizeNorm);  // large drops steepen faster
                dropY   = startY + pow(slideT, accel) * (1.08 - startY);
                sliding = 1.0;
            }

            // Skip drops that are fully off-screen
            if (dropY < -0.08 || dropY > 1.08) continue;

            // Horizontal centre within column; wobble only while sliding
            float cx = 0.25 + sa * 0.5;
            if (sliding > 0.5) {
                float w = sin(uv.y * 14.0 + t * (1.3 + sa) + sa * 6.28) * 0.04 * (pathVariance * 2.0)
                        + sin(uv.y * 7.3  + t * 0.7 + sb * 4.1) * 0.025 * (pathVariance * 2.0)
                        + sin(uv.y * 31.7 + t * (3.7 + sc) + sc * 9.2) * 0.02 * pathVariance;
                cx += w;
            }

            // Distance in UV space (dy converts screenY → uv.y)
            // Elongation varies with size: small drops are nearly circular,
            // large drops stretch slightly under gravity (physically accurate).
            float dx    = (nFrac - cx) * colW;
            float dy    = uv.y - (0.5 - dropY);
            float elong = mix(0.88, 0.72, sizeNorm);
            float d     = length(vec2(dx, dy * elong));
            float hit = smoothstep(radius, radius * 0.2, d);

            // Metaball accumulation — overlapping drops merge
            field += hit;

            // Wet trail: fog-clearing strip left behind a sliding drop
            if (dc == 0 && sliding > 0.5) {
                float bw    = radius * 2.2;
                float band  = smoothstep(bw, bw * 0.3, abs(dx));
                float above = smoothstep(-0.01, 0.35, uv.y - (0.5 - dropY));
                trail = max(trail, band * above * (1.0 - hit) * 0.6);
            }
        }
    }

    return vec2(clamp(field, 0.0, 1.0), trail);
}

// ── Settled droplets ──────────────────────────────────────────
// Tiny drops resting on the glass. Two overlapping hex-offset
// grids with desynchronized breathing for organic scatter.

float settledDrops(vec2 uv, float t) {
    float total = 0.0;

    for (int i = 0; i < 2; i++) {
        float scale = 32.0 + float(i) * 22.0;
        vec2 g = uv * scale;

        float row = floor(g.y);
        g.x += step(0.5, fract(row * 0.5)) * 0.5;

        vec2 id = floor(g);
        vec2 f  = fract(g) - 0.5;

        vec2 r  = rng22(id + float(i) * 500.0);
        vec2 c  = (r - 0.5) * 0.45;

        float d  = length(f - c);
        float sz = (0.04 + r.x * 0.11) * dropSize;

        float pulse = sin(t * 0.5 + r.y * 6.28) * 0.5 + 0.5;
        pulse *= pulse;

        total += smoothstep(sz, sz * 0.12, d) * pulse * step(0.5, r.y);
    }

    return total;
}

// ── Height field: all rain layers combined ────────────────────

vec2 heightField(vec2 uv, float t, float amount) {
    float wSettled = smoothstep(0.0,  0.5,  amount) * 1.5;
    float wLarge   = smoothstep(0.15, 0.7,  amount);
    float wSmall   = smoothstep(0.35, 1.0,  amount);

    float s  = settledDrops(uv, t) * wSettled;
    // Large slow drops (8 wide columns) and small fast drops (18 narrow columns)
    vec2  d1 = rollingDrops(uv, t,  8.0,  0.0,  1.0) * wLarge;
    vec2  d2 = rollingDrops(uv, t, 18.0, 17.5,  2.5) * wSmall;

    float height = clamp(s + d1.x + d2.x, 0.0, 1.0);
    float trail  = max(d1.y, d2.y);

    return vec2(height, trail);
}

// ── Background rain streaks ───────────────────────────────────
// Fast-moving vertical streaks seen through the glass in the scene beyond.
// Takes texUV (0..1 in both dimensions) so it is correctly refracted by the
// surface-normal offset already applied to bgUV in mainImage.
// Three layers at different densities and speeds give a sense of depth.

float bgRainLayer(vec2 uv, float t, float cols, float rowDensity, float speed, float seed) {
    float sx  = uv.x * cols;
    // texUV.y = 0 at bottom, 1 at top (WebGL convention).
    // Adding t*speed increases sy → rId, shifting pattern to lower uv.y = falling down.
    float sy  = uv.y * rowDensity + t * speed;

    float cId = floor(sx);
    float rId = floor(sy);
    float fx  = fract(sx);
    float fy  = fract(sy);

    float r1 = rng(cId * 7.13  + rId * 53.7  + seed);
    float r2 = rng(cId * 11.31 + rId * 37.1  + seed);
    float r3 = rng(cId * 17.33 + rId * 41.9  + seed);

    float live = step(0.72, r1);    // ~28% of cells contain a streak

    float cx = 0.15 + r2 * 0.70;   // x centre within column
    float xW = 0.03 + r3 * 0.04;   // streak half-width (3–7% of column)
    float x  = smoothstep(xW, 0.0, abs(fx - cx));

    // Smooth fade at cell edges so adjacent active cells blend seamlessly
    float y  = smoothstep(0.0, 0.18, fy) * smoothstep(1.0, 0.82, fy);

    return x * y * live * (0.15 + r3 * 0.30);
}

float backgroundRain(vec2 uv, float t) {
    float r = 0.0;
    r += bgRainLayer(uv, t, 30.0, 18.0, 12.0,  0.0);  // coarse / slow
    r += bgRainLayer(uv, t, 55.0, 32.0, 28.0, 19.3);  // medium
    r += bgRainLayer(uv, t, 88.0, 55.0, 50.0, 43.7);  // fine / fast
    return min(r, 1.0);
}

// ── Fog blur — 13-tap weighted kernel ────────────────────────
// textureLod requires mipmaps; this works with any texture filter.
// Ring 1 (cardinal, weight 2): taps at ±r on each axis.
// Ring 2 (diagonal, weight 1): taps at ±r on each diagonal.
// Ring 3 (wide cardinal, weight 1): taps at ±2.3r on each axis.
// Total weight: 4 + 8 + 8 + 4 = 24.

vec3 fogBlur(vec2 uv, float r) {
    if (r < 0.5) return texture(iChannel0, uv).rgb;
    vec2 px  = r / iResolution.xy;
    vec2 px2 = px * 2.3;
    vec3 c = texture(iChannel0, uv).rgb * 4.0;
    c += texture(iChannel0, uv + vec2( px.x,  0.0 )).rgb * 2.0;
    c += texture(iChannel0, uv + vec2(-px.x,  0.0 )).rgb * 2.0;
    c += texture(iChannel0, uv + vec2( 0.0,   px.y)).rgb * 2.0;
    c += texture(iChannel0, uv + vec2( 0.0,  -px.y)).rgb * 2.0;
    c += texture(iChannel0, uv + vec2( px.x,  px.y)).rgb;
    c += texture(iChannel0, uv + vec2(-px.x,  px.y)).rgb;
    c += texture(iChannel0, uv + vec2( px.x, -px.y)).rgb;
    c += texture(iChannel0, uv + vec2(-px.x, -px.y)).rgb;
    c += texture(iChannel0, uv + vec2( px2.x, 0.0 )).rgb;
    c += texture(iChannel0, uv + vec2(-px2.x, 0.0 )).rgb;
    c += texture(iChannel0, uv + vec2( 0.0,  px2.y)).rgb;
    c += texture(iChannel0, uv + vec2( 0.0, -px2.y)).rgb;
    return c / 24.0;
}

// ── Main ──────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    vec2 texUV = fragCoord / iResolution.xy;
    float t = iTime;

    float blurHi = mix(0.0, 10.0, fogAmount);
    float blurLo = mix(0.0,  1.5, fogAmount * 0.5);

    vec2 hf = heightField(uv, t, rainAmount);

    float eps = 0.0008;
    float hR = heightField(uv + vec2(eps, 0.0), t, rainAmount).x;
    float hU = heightField(uv + vec2(0.0, eps), t, rainAmount).x;
    vec2 n = vec2(hR - hf.x, hU - hf.x);

    float blurR = mix(blurHi - hf.y * blurHi * 0.5, blurLo, smoothstep(0.05, 0.25, hf.x));

    // bgUV carries the drop-normal refraction offset — fog blur and background
    // rain both sample at this position so rain streaks refract through each drop.
    vec2 bgUV = texUV + n;
    vec3 col  = fogBlur(bgUV, blurR);

    // Background rain: falling in the scene outside the glass.
    // Fades with fog (can't see distant rain through heavy condensation).
    float bgRain = backgroundRain(bgUV, t) * rainAmount * mix(0.30, 0.02, fogAmount);
    col += bgRain * vec3(0.78, 0.86, 1.0);  // cool blue-white rain tint

    vec2 vc = texUV - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.7;

    fragColor = vec4(col, 1.0);
}
