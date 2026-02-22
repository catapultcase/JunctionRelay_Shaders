// Noir — Hard-boiled film noir shader
// Heavy contrast crush + venetian blind shadows + rain on glass + film grain + bleach bypass
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }

float noise2(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // ── Rain on glass — streaks and droplets distort the scene ────────────
    // Vertical streaks
    vec2 rainUV = uv;
    float  streakCol  = floor(uv.x * 80.0);
    float  streakSeed = hash11(streakCol * 0.37);
    float  streakSpeed = 0.15 + streakSeed * 0.3;
    float  streakPhase = fract(streakSeed + iTime * streakSpeed);
    float  streakLen   = 0.06 + streakSeed * 0.12;
    float  inStreak    = step(streakPhase, uv.y) * step(uv.y, streakPhase + streakLen);
    inStreak          *= step(0.7, streakSeed);   // only some columns have streaks
    rainUV.x          += inStreak * sin(uv.y * 40.0 + iTime) * 0.003;

    // Droplets — small circular lens distortions
    vec2 dropGrid  = uv * vec2(18.0, 10.0);
    vec2 dropCell  = floor(dropGrid);
    vec2 dropFrac  = fract(dropGrid);
    vec2 dropPos   = vec2(hash21(dropCell), hash21(dropCell + 7.3));
    float  dropLife  = fract(hash21(dropCell + 3.1) + iTime * 0.08);
    float  dropR     = 0.15 + hash21(dropCell + 5.5) * 0.2;
    vec2 dropDiff  = dropFrac - dropPos;
    float  dropDist  = length(dropDiff);
    float  dropMask  = step(dropDist, dropR) * step(0.3, dropLife);
    // Lens refraction — bends UVs inward toward droplet center
    rainUV          += dropMask * normalize(dropDiff) * (dropR - dropDist) * -0.04;

    vec4 col = texture(iChannel0, clamp(rainUV, 0.0, 1.0));

    // ── Bleach bypass — desaturate + boost contrast (classic noir grade) ──
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb    = mix(col.rgb, vec3(luma, luma, luma), 0.85);  // near-mono

    // Hard S-curve contrast: crush blacks, blow highlights
    col.rgb = pow(clamp(col.rgb, 0.0, 1.0), vec3(1.6));                    // darken mids
    col.rgb = clamp(col.rgb * 1.4 - 0.05, 0.0, 1.0);                    // push whites

    // ── Venetian blind shadows — angled light through horizontal slats ────
    float blindFreq  = 14.0;
    float blindAngle = 0.18;   // slight tilt
    float blindCoord = uv.y + uv.x * blindAngle;
    float blind      = step(0.42, fract(blindCoord * blindFreq));
    // Blinds cast a hard shadow — dark bands, not a soft gradient
    col.rgb         *= mix(0.12, 1.0, blind);

    // ── Warm key light — single source, stage left ────────────────────────
    // The one light source in a noir scene: a bare bulb or streetlamp
    vec2 lightPos = vec2(0.15, 0.3);
    float  lightDist = length(uv - lightPos);
    float  keyLight  = smoothstep(0.7, 0.0, lightDist) * 0.25;
    col.rgb += vec3(keyLight * 1.1, keyLight * 0.9, keyLight * 0.5); // warm

    // ── Film grain — coarse, 1950s stock ──────────────────────────────────
    float grain = hash21(uv * vec2(512, 288) + fract(iTime * 23.7));
    grain       = (grain - 0.5);
    // Grain is larger in shadows (pushed pull processing look)
    float grainMask = 1.0 - luma;
    col.rgb        += grain * 0.09 * (1.0 + grainMask * 1.5);

    // ── Cigarette burn — top-right corner flash every ~20s ────────────────
    float burnCycle = fract(iTime / 20.0);
    float burnOn    = step(0.96, burnCycle);
    vec2 burnUV   = vec2(1.0 - uv.x, uv.y);   // top-right
    float  burnDist = length(burnUV - vec2(0.04, 0.04));
    float  burn     = burnOn * step(burnDist, 0.025);
    col.rgb         = mix(col.rgb, vec3(1.0, 0.9, 0.6), burn);

    // ── Heavy vignette — dark corners, single-source lighting ────────────
    vec2 vig  = uv * (1.0 - uv);
    float  vign = pow(vig.x * vig.y * 10.0, 0.6);
    col.rgb    *= mix(0.0, 1.0, vign);

    // ── Slight sepia toning in the highlights ─────────────────────────────
    float hi     = smoothstep(0.6, 1.0, dot(col.rgb, vec3(0.333,0.333,0.333)));
    col.rgb     += hi * vec3(0.05, 0.02, -0.04);

    fragColor = clamp(col, 0.0, 1.0);
}
