// Rain Window — Glass Rain Overlay
// Copyright (C) 2024-present Jonathan Mills, CatapultCase
// All rights reserved.
//
// Texture overlay: background viewed through wet, condensed glass.
// Drops roll down the surface, trails cut through fog, tiny droplets
// scatter across the pane. The scene behind refracts through each drop.
//
// Inputs: iChannel0, iTime, iResolution, rainAmount, fogAmount

// ── Hash functions ────────────────────────────────────────────
// cos-polynomial family

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
// Scrolling grid: cells drift downward over time, each containing
// one raindrop at a jittered position. The scroll creates the
// illusion of continuous falling.
//
// Returns: vec2(dropHeight, trailClearing)

vec2 rollingDrops(vec2 uv, float t, float cols, float rows, float speed) {
    vec2 grid = vec2(cols, rows);
    vec2 st = uv * grid;

    // Rain falls: scroll grid downward
    st.y += t * speed;

    // Desync each column vertically so drops don't align in rows
    float colId = floor(st.x);
    st.y += rng(colId * 43.71) * 87.3;

    vec2 cellId = floor(st);
    vec2 f = fract(st); // 0..1 in cell

    // Per-cell randoms
    float ra = rng2(cellId);
    float rb = rng2(cellId + 331.0);
    float rc = rng2(cellId + 719.0);

    // Column sparsity: some columns have no drops
    float alive = step(0.3, rng(colId * 91.3));

    // Drop center within cell
    float cx = 0.5 + (ra - 0.5) * 0.4;
    float cy = 0.25 + rb * 0.45;

    // Horizontal wobble: two harmonics for organic meandering
    float wobble = sin(uv.y * 14.0 + t * (1.3 + ra) + ra * 6.28) * 0.04
                 + sin(uv.y * 7.3  + t * 0.7 + rb * 4.1) * 0.025;
    cx += wobble;

    // Elliptical drop shape (slightly taller than wide)
    vec2 delta = vec2(f.x - cx, (f.y - cy) * 0.65);
    float radius = 0.055 + rc * 0.03;
    float dist = length(delta);
    float drop = smoothstep(radius, radius * 0.2, dist);

    // Trail: narrow band of cleared fog above the drop
    float bw = radius * 2.2;
    float band = smoothstep(bw, bw * 0.3, abs(f.x - cx));
    float above = smoothstep(cy - 0.01, cy + 0.4, f.y);
    float trail = band * above * (1.0 - drop) * 0.5;

    return vec2(drop, trail) * alive;
}

// ── Settled droplets ──────────────────────────────────────────
// Tiny drops resting on the glass. Two overlapping hex-offset
// grids with desynchronized breathing for organic scatter.

float settledDrops(vec2 uv, float t) {
    float total = 0.0;

    for (int i = 0; i < 2; i++) {
        float scale = 32.0 + float(i) * 22.0;
        vec2 g = uv * scale;

        // Hex offset: shift every other row by half a cell
        float row = floor(g.y);
        g.x += step(0.5, fract(row * 0.5)) * 0.5;

        vec2 id = floor(g);
        vec2 f = fract(g) - 0.5;

        vec2 r = rng22(id + float(i) * 500.0);
        vec2 center = (r - 0.5) * 0.45;

        float d = length(f - center);
        float sz = 0.04 + r.x * 0.11;

        // Breathing: smooth pulse, each drop on its own cycle
        float pulse = sin(t * 0.5 + r.y * 6.28) * 0.5 + 0.5;
        pulse *= pulse; // sharpen the on-phase

        total += smoothstep(sz, sz * 0.12, d) * pulse * step(0.5, r.y);
    }

    return total;
}

// ── Height field: all rain layers combined ────────────────────

vec2 heightField(vec2 uv, float t, float amount) {
    // Layer weights ramp in as rain amount increases
    float wSettled = smoothstep(0.0, 0.5, amount) * 1.5;
    float wLarge   = smoothstep(0.15, 0.7, amount);
    float wSmall   = smoothstep(0.35, 1.0, amount);

    float s  = settledDrops(uv, t) * wSettled;
    vec2  d1 = rollingDrops(uv, t, 8.0, 20.0, 2.5) * wLarge;
    vec2  d2 = rollingDrops(uv * 1.7 + 100.0, t, 12.0, 28.0, 4.0) * wSmall;

    float height = clamp(s + d1.x + d2.x, 0.0, 1.0);
    float trail  = max(d1.y, d2.y);

    return vec2(height, trail);
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
    c += texture(iChannel0, uv + vec2( px.x,  px.y));
    c += texture(iChannel0, uv + vec2(-px.x,  px.y));
    c += texture(iChannel0, uv + vec2( px.x, -px.y));
    c += texture(iChannel0, uv + vec2(-px.x, -px.y));
    c += texture(iChannel0, uv + vec2( px2.x, 0.0 ));
    c += texture(iChannel0, uv + vec2(-px2.x, 0.0 ));
    c += texture(iChannel0, uv + vec2( 0.0,  px2.y));
    c += texture(iChannel0, uv + vec2( 0.0, -px2.y));
    return c.rgb / 24.0;
}

// ── Main ──────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;
    vec2 texUV = fragCoord / iResolution.xy;
    float t = iTime;

    // Blur radius in pixels from fog parameter
    float blurHi = mix(0.0, 10.0, fogAmount);          // open glass: 0–10 px
    float blurLo = mix(0.0,  1.5, fogAmount * 0.5);    // through a drop: stays sharp

    // Rain height field
    vec2 hf = heightField(uv, t, rainAmount);

    // Surface normals via forward differences
    float eps = 0.0008;
    float hR = heightField(uv + vec2(eps, 0.0), t, rainAmount).x;
    float hU = heightField(uv + vec2(0.0, eps), t, rainAmount).x;
    vec2 n = vec2(hR - hf.x, hU - hf.x);

    // Blur radius: drops clear the fog (sharp), trails thin it, glass stays foggy
    float blurR = mix(blurHi - hf.y * blurHi * 0.5, blurLo, smoothstep(0.05, 0.25, hf.x));

    // Sample background through wet glass with manual blur
    vec3 col = fogBlur(texUV + n, blurR);

    // Gentle vignette
    vec2 vc = texUV - 0.5;
    col *= 1.0 - dot(vc, vc) * 0.7;

    fragColor = vec4(col, 1.0);
}
