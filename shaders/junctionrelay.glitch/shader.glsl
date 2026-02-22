// Glitch — Digital signal corruption shader
// RGB channel splitting + block displacement + bit-crush + datamosh smear
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // ── Glitch event timing — irregular bursts ─────────────────────────────
    float eventT    = floor(iTime * 3.7);
    float eventRand = hash11(eventT);
    float burstOn   = step(0.65, eventRand);   // fires ~35% of the iTime

    // ── Block displacement — macroblocks shift horizontally ────────────────
    float blockSize  = mix(0.04, 0.12, hash11(eventT + 1.1));
    float blockRow   = floor(uv.y / blockSize);
    float blockShift = 0.0;
    if (burstOn > 0.0)
    {
        float rowRand = hash21(vec2(blockRow, eventT));
        blockShift    = (rowRand > 0.75)
                      ? (hash21(vec2(blockRow, eventT + 5.3)) - 0.5) * 0.18
                      : 0.0;
    }

    // ── Scanline-level jitter ──────────────────────────────────────────────
    float lineJitter = 0.0;
    if (burstOn > 0.0)
    {
        float lineRand = hash21(vec2(floor(uv.y * iResolution.y), eventT));
        lineJitter     = (lineRand > 0.92) ? (hash21(vec2(uv.y, eventT)) - 0.5) * 0.06 : 0.0;
    }

    vec2 warpedUV = clamp(vec2(uv.x + blockShift + lineJitter, uv.y), 0.0, 1.0);

    // ── RGB channel split — each channel displaced independently ───────────
    float splitAmt = burstOn * mix(0.002, 0.022, hash11(eventT + 2.2));
    float splitDir = (hash11(eventT + 3.3) - 0.5) * 2.0;

    float r = texture(iChannel0, clamp(warpedUV + vec2( splitAmt * splitDir, 0), 0.0, 1.0)).r;
    float g = texture(iChannel0, warpedUV).g;
    float b = texture(iChannel0, clamp(warpedUV - vec2( splitAmt * splitDir, 0), 0.0, 1.0)).b;
    vec4 col = vec4(r, g, b, 1.0);

    // ── Bit crush — quantize to simulate low bit-depth corruption ──────────
    float crushAmount = burstOn * mix(4.0, 24.0, hash11(eventT + 4.4));
    if (crushAmount > 0.5)
        col.rgb = floor(col.rgb * crushAmount) / crushAmount;

    // ── Datamosh smear — rows of solid colour bleed from above ────────────
    if (burstOn > 0.0)
    {
        float smearRow  = hash11(eventT + 6.6);
        float smearH    = 0.03 + hash11(eventT + 7.7) * 0.08;
        float inSmear   = step(smearRow, uv.y) * step(uv.y, smearRow + smearH);
        vec3 smearCol = texture(iChannel0, vec2(uv.x, smearRow)).rgb;
        col.rgb         = mix(col.rgb, smearCol, inSmear * 0.85);
    }

    // ── Random full-row colour flash ───────────────────────────────────────
    float flashRow  = hash11(floor(uv.y * iResolution.y) + eventT * 13.7);
    float flashOn   = burstOn * step(0.97, flashRow);
    vec3 flashCol = vec3(hash11(eventT + 8.0), hash11(eventT + 9.0), hash11(eventT + 10.0));
    col.rgb         = mix(col.rgb, flashCol, flashOn);

    // ── Subtle always-on digital noise ────────────────────────────────────
    col.rgb += (hash21(uv + fract(iTime * 47.3)) - 0.5) * 0.03;

    fragColor = clamp(col, 0.0, 1.0);
}
