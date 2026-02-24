// Stream Lost — procedural CRT static with 7-segment digital clock
// Uses uWallTime (seconds since midnight) injected by FrameEngine

// ─── Noise ───────────────────────────────────────────────────
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float staticNoise(vec2 uv, float t) {
    float n = 0.0;
    n += noise(uv * 80.0 + t * 120.0) * 0.5;
    n += noise(uv * 160.0 - t * 90.0) * 0.3;
    n += noise(uv * 320.0 + t * 200.0) * 0.2;
    // Row-band modulation
    float band = noise(vec2(uv.y * 30.0, t * 15.0));
    n *= 0.6 + 0.4 * band;
    return n;
}

// ─── 7-segment digit SDF ────────────────────────────────────
// Segments:    _0_
//            |5   |1
//             _6_
//            |4   |2
//             _3_

// Segment presence for digits 0-9
// Each bit: seg0..seg6
const int SEG_TABLE[10] = int[10](
    0x7E, // 0: 1111110 = 0,1,2,3,4,5
    0x0C, // 1: 0001100 = 1,2
    0x76, // 2: 1110110 = 0,1,3,4,6
    0x5E, // 3: 1011110 = 0,1,2,3,6
    0x4E, // 4: 0001110 = 1,2,5,6  → fix: 0x4E = 1001110
    0x5A, // 5: 1011010 = 0,2,3,5,6  → fix: 0x5A
    0x7A, // 6: 1111010 = 0,2,3,4,5,6
    0x0E, // 7: 0001110 = 0,1,2
    0x7E, // 8: 1111110 = all but 6... wait
    0x5E  // 9: 1011110 = 0,1,2,3,5,6
);

// Better approach: use named bitmask per segment
// Segments numbered:  0=top, 1=top-right, 2=bot-right, 3=bottom, 4=bot-left, 5=top-left, 6=middle
bool segmentOn(int digit, int seg) {
    //          seg: 0  1  2  3  4  5  6
    // digit 0:      1  1  1  1  1  1  0
    // digit 1:      0  1  1  0  0  0  0
    // digit 2:      1  1  0  1  1  0  1
    // digit 3:      1  1  1  1  0  0  1
    // digit 4:      0  1  1  0  0  1  1
    // digit 5:      1  0  1  1  0  1  1
    // digit 6:      1  0  1  1  1  1  1
    // digit 7:      1  1  1  0  0  0  0
    // digit 8:      1  1  1  1  1  1  1
    // digit 9:      1  1  1  1  0  1  1
    const int table[10] = int[10](
        0x7E, 0x30, 0x6D, 0x79, 0x33,
        0x5B, 0x5F, 0x70, 0x7F, 0x7B
    );
    return (table[digit] & (1 << (6 - seg))) != 0;
}

// SDF for a single horizontal or vertical segment bar
float segmentSDF(vec2 p, vec2 a, vec2 b, float thickness) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    vec2 closest = a + t * ab;
    return length(p - closest) - thickness;
}

// Render a single digit at position, return intensity [0,1]
float renderDigit(vec2 uv, vec2 pos, float w, float h, float thick, int digit) {
    vec2 p = uv - pos;

    // Segment endpoints (relative to digit origin at bottom-left)
    float margin = thick * 1.5;
    float hw = w - margin * 2.0;  // horizontal segment width
    float hh = h * 0.5;           // half height

    float d = 1e6;

    // seg 0: top horizontal
    if (segmentOn(digit, 0)) {
        d = min(d, segmentSDF(p, vec2(margin, h), vec2(margin + hw, h), thick));
    }
    // seg 1: top-right vertical
    if (segmentOn(digit, 1)) {
        d = min(d, segmentSDF(p, vec2(w - margin, hh + margin), vec2(w - margin, h - margin), thick));
    }
    // seg 2: bottom-right vertical
    if (segmentOn(digit, 2)) {
        d = min(d, segmentSDF(p, vec2(w - margin, margin), vec2(w - margin, hh - margin), thick));
    }
    // seg 3: bottom horizontal
    if (segmentOn(digit, 3)) {
        d = min(d, segmentSDF(p, vec2(margin, 0.0), vec2(margin + hw, 0.0), thick));
    }
    // seg 4: bottom-left vertical
    if (segmentOn(digit, 4)) {
        d = min(d, segmentSDF(p, vec2(margin, margin), vec2(margin, hh - margin), thick));
    }
    // seg 5: top-left vertical
    if (segmentOn(digit, 5)) {
        d = min(d, segmentSDF(p, vec2(margin, hh + margin), vec2(margin, h - margin), thick));
    }
    // seg 6: middle horizontal
    if (segmentOn(digit, 6)) {
        d = min(d, segmentSDF(p, vec2(margin, hh), vec2(margin + hw, hh), thick));
    }

    return smoothstep(thick * 0.5, -thick * 0.3, d);
}

// Render colon (two dots)
float renderColon(vec2 uv, vec2 pos, float h, float dotSize) {
    float d1 = length(uv - pos - vec2(0.0, h * 0.3)) - dotSize;
    float d2 = length(uv - pos - vec2(0.0, h * 0.7)) - dotSize;
    float d = min(d1, d2);
    return smoothstep(dotSize * 0.3, -dotSize * 0.2, d);
}

// ─── CRT effects ─────────────────────────────────────────────
float scanlines(vec2 uv, float weight, vec3 res) {
    float sl = sin(uv.y * res.y * 3.14159) * 0.5 + 0.5;
    return 1.0 - weight * (1.0 - sl);
}

float vignette(vec2 uv, float amount) {
    vec2 q = uv * 2.0 - 1.0;
    return 1.0 - amount * dot(q * q, q * q);
}

// ─── Main ────────────────────────────────────────────────────
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime;

    // ── Background static ──
    float n = staticNoise(uv, t);
    vec3 bg = bgColor * n * bgIntensity;

    // ── Scanlines on background ──
    bg *= scanlines(uv, scanlineWeight, iResolution);

    // ── Clock ──
    float wallTime = uWallTime;
    int totalSec = int(wallTime);
    int hours = totalSec / 3600;
    int minutes = (totalSec / 60) - hours * 60;
    int seconds = totalSec - hours * 3600 - minutes * 60;

    // Clock dimensions (relative to screen)
    float digitW = clockScale * 0.06;
    float digitH = clockScale * 0.14;
    float thick = clockScale * 0.006;
    float gap = clockScale * 0.015;
    float colonW = clockScale * 0.025;
    float dotSize = clockScale * 0.008;

    // Total width: 6 digits + 2 colons + gaps
    float totalW = 6.0 * digitW + 2.0 * colonW + 7.0 * gap;
    float aspect = iResolution.x / iResolution.y;

    // Center the clock, offset by clockOffsetY
    vec2 clockOrigin = vec2(
        0.5 - totalW * 0.5 * aspect,
        0.5 - digitH * 0.5 + clockOffsetY
    );

    // Scale UV to account for aspect ratio in x
    vec2 clockUV = vec2(uv.x * aspect, uv.y);
    vec2 origin = vec2(clockOrigin.x * aspect, clockOrigin.y);

    float clockMask = 0.0;
    float x = 0.0;

    // HH
    int d0 = hours / 10;
    int d1 = hours - d0 * 10;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d0));
    x += digitW + gap;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d1));
    x += digitW + gap;

    // Colon 1
    float colonAlpha = colonBlink > 0.5 ? (sin(t * 6.28318) * 0.5 + 0.5) : 1.0;
    clockMask = max(clockMask, renderColon(clockUV, origin + vec2(x, 0.0), digitH, dotSize) * colonAlpha);
    x += colonW + gap;

    // MM
    int d2 = minutes / 10;
    int d3 = minutes - d2 * 10;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d2));
    x += digitW + gap;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d3));
    x += digitW + gap;

    // Colon 2
    clockMask = max(clockMask, renderColon(clockUV, origin + vec2(x, 0.0), digitH, dotSize) * colonAlpha);
    x += colonW + gap;

    // SS
    int d4 = seconds / 10;
    int d5 = seconds - d4 * 10;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d4));
    x += digitW + gap;
    clockMask = max(clockMask, renderDigit(clockUV, origin + vec2(x, 0.0), digitW, digitH, thick, d5));

    // Apply clock color + glow
    float glow = clockMask * clockOpacity;
    vec3 clockCol = clockColor * glow;

    // Subtle bloom around digits
    float bloom = smoothstep(0.0, 0.8, clockMask) * 0.15 * clockOpacity;
    vec3 bloomCol = clockColor * bloom;

    // ── Composite ──
    vec3 col = bg + clockCol + bloomCol;

    // Vignette
    col *= vignette(uv, vignetteAmount);

    fragColor = vec4(col, 1.0);
}
