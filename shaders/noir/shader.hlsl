// Noir — Hard-boiled film noir shader
// Heavy contrast crush + venetian blind shadows + rain on glass + film grain + bleach bypass
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

float hash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float hash21(float2 p) { float3 p3 = frac(float3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return frac((p3.x+p3.y)*p3.z); }

float noise2(float2 p) {
    float2 i = floor(p); float2 f = frac(p); float2 u = f*f*(3.0-2.0*f);
    return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // ── Rain on glass — streaks and droplets distort the scene ────────────
    // Vertical streaks
    float2 rainUV = uv;
    float  streakCol  = floor(uv.x * 80.0);
    float  streakSeed = hash11(streakCol * 0.37);
    float  streakSpeed = 0.15 + streakSeed * 0.3;
    float  streakPhase = frac(streakSeed + time * streakSpeed);
    float  streakLen   = 0.06 + streakSeed * 0.12;
    float  inStreak    = step(streakPhase, uv.y) * step(uv.y, streakPhase + streakLen);
    inStreak          *= step(0.7, streakSeed);   // only some columns have streaks
    rainUV.x          += inStreak * sin(uv.y * 40.0 + time) * 0.003;

    // Droplets — small circular lens distortions
    float2 dropGrid  = uv * float2(18.0, 10.0);
    float2 dropCell  = floor(dropGrid);
    float2 dropFrac  = frac(dropGrid);
    float2 dropPos   = float2(hash21(dropCell), hash21(dropCell + 7.3));
    float  dropLife  = frac(hash21(dropCell + 3.1) + time * 0.08);
    float  dropR     = 0.15 + hash21(dropCell + 5.5) * 0.2;
    float2 dropDiff  = dropFrac - dropPos;
    float  dropDist  = length(dropDiff);
    float  dropMask  = step(dropDist, dropR) * step(0.3, dropLife);
    // Lens refraction — bends UVs inward toward droplet center
    rainUV          += dropMask * normalize(dropDiff) * (dropR - dropDist) * -0.04;

    float4 col = tex0.Sample(sampler0, saturate(rainUV));

    // ── Bleach bypass — desaturate + boost contrast (classic noir grade) ──
    float luma = dot(col.rgb, float3(0.299, 0.587, 0.114));
    col.rgb    = lerp(col.rgb, float3(luma, luma, luma), 0.85);  // near-mono

    // Hard S-curve contrast: crush blacks, blow highlights
    col.rgb = pow(saturate(col.rgb), 1.6);                        // darken mids
    col.rgb = saturate(col.rgb * 1.4 - 0.05);                    // push whites

    // ── Venetian blind shadows — angled light through horizontal slats ────
    float blindFreq  = 14.0;
    float blindAngle = 0.18;   // slight tilt
    float blindCoord = uv.y + uv.x * blindAngle;
    float blind      = step(0.42, frac(blindCoord * blindFreq));
    // Blinds cast a hard shadow — dark bands, not a soft gradient
    col.rgb         *= lerp(0.12, 1.0, blind);

    // ── Warm key light — single source, stage left ────────────────────────
    // The one light source in a noir scene: a bare bulb or streetlamp
    float2 lightPos = float2(0.15, 0.3);
    float  lightDist = length(uv - lightPos);
    float  keyLight  = smoothstep(0.7, 0.0, lightDist) * 0.25;
    col.rgb += float3(keyLight * 1.1, keyLight * 0.9, keyLight * 0.5); // warm

    // ── Film grain — coarse, 1950s stock ──────────────────────────────────
    float grain = hash21(uv * float2(512, 288) + frac(time * 23.7));
    grain       = (grain - 0.5);
    // Grain is larger in shadows (pushed pull processing look)
    float grainMask = 1.0 - luma;
    col.rgb        += grain * 0.09 * (1.0 + grainMask * 1.5);

    // ── Cigarette burn — top-right corner flash every ~20s ────────────────
    float burnCycle = frac(time / 20.0);
    float burnOn    = step(0.96, burnCycle);
    float2 burnUV   = float2(1.0 - uv.x, uv.y);   // top-right
    float  burnDist = length(burnUV - float2(0.04, 0.04));
    float  burn     = burnOn * step(burnDist, 0.025);
    col.rgb         = lerp(col.rgb, float3(1.0, 0.9, 0.6), burn);

    // ── Heavy vignette — dark corners, single-source lighting ────────────
    float2 vig  = uv * (1.0 - uv);
    float  vign = pow(vig.x * vig.y * 10.0, 0.6);
    col.rgb    *= lerp(0.0, 1.0, vign);

    // ── Slight sepia toning in the highlights ─────────────────────────────
    float hi     = smoothstep(0.6, 1.0, dot(col.rgb, float3(0.333,0.333,0.333)));
    col.rgb     += hi * float3(0.05, 0.02, -0.04);

    return saturate(col);
}
