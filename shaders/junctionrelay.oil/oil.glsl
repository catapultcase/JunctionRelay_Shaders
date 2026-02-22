// Oil — Iridescent oil slick / soap bubble refraction shader
// Thin film interference + surface normal perturbation + chromatic rainbow shift
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }

float noise2(vec2 p)
{
    vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
    return mix(mix(hash21(i), hash21(i+vec2(1,0)), u.x), mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), u.x), u.y);
}

float fbm(vec2 p)
{
    float v=0.0, a=0.5;
    mat2 r = mat2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<5;i++){ v+=a*noise2(p); p=r * p*2.1; a*=0.5; }
    return v;
}

// Hue rotation — shift RGB around the colour wheel
vec3 hueRotate(vec3 col, float angle)
{
    float c = cos(angle), s = sin(angle);
    mat3 m = mat3(
        0.299+0.701*c+0.168*s, 0.587-0.587*c+0.330*s, 0.114-0.114*c-0.497*s,
        0.299-0.299*c-0.328*s, 0.587+0.413*c+0.035*s, 0.114-0.114*c+0.292*s,
        0.299-0.300*c+1.250*s, 0.587-0.588*c-1.050*s, 0.114+0.886*c-0.203*s);
    return clamp(m * col, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // ── Flowing surface normals — oil moves slowly ─────────────────────────
    vec2 flowA = vec2(iTime * 0.04,  iTime * 0.03);
    vec2 flowB = vec2(iTime * -0.02, iTime * 0.05);

    float heightA = fbm(uv * 4.0 + flowA);
    float heightB = fbm(uv * 6.5 + flowB);
    float height  = (heightA + heightB * 0.5) / 1.5;

    // Derive surface normal from height field gradient
    float eps = 0.002;
    float dhdx = fbm(vec2(uv.x+eps, uv.y)*4.0+flowA) - fbm(vec2(uv.x-eps, uv.y)*4.0+flowA);
    float dhdy = fbm(vec2(uv.x, uv.y+eps)*4.0+flowA) - fbm(vec2(uv.x, uv.y-eps)*4.0+flowA);
    vec2 normal = vec2(dhdx, dhdy) * 8.0;

    // ── Refracted UV — content seen through the oil layer ─────────────────
    vec2 refractedUV = clamp(uv + normal * 0.018, 0.0, 1.0);
    vec4 col = texture(iChannel0, refractedUV);

    // ── Thin film interference — the actual iridescence ────────────────────
    // Film thickness varies with height field; angle of incidence varies with UV
    float thickness   = height * 2.0 + 0.5;
    float viewAngle   = length(uv - 0.5) * 1.4;
    float filmPhase   = thickness * (1.0 + viewAngle * 0.3);

    // Each wavelength (R/G/B) interferes at a different phase offset
    // producing the characteristic rainbow sheen
    float interferR = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.00);
    float interferG = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.45);
    float interferB = 0.5 + 0.5 * cos(filmPhase * 6.28 * 1.90);
    vec3 thinFilm = vec3(interferR, interferG, interferB);

    // ── Hue-rotate the underlying content by the local film phase ──────────
    float hueShift = filmPhase * 2.1 + iTime * 0.08;
    vec3 tinted  = hueRotate(col.rgb, hueShift);

    // ── Blend: darker areas show more iridescence (like a real oil slick) ──
    float luma      = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    float filmStrength = mix(0.6, 0.15, luma);   // iridescence fades in bright areas

    col.rgb = mix(col.rgb, tinted * (0.5 + thinFilm * 0.8), filmStrength);

    // ── Specular highlight — oil is shiny ──────────────────────────────────
    float spec = pow(clamp(1.0 - length(normal) * 0.4, 0.0, 1.0), 12.0);
    col.rgb   += spec * vec3(1.0, 1.0, 1.0) * 0.3;

    // ── Edge darkening — pooling oil is thicker at edges ───────────────────
    vec2 vig = uv * (1.0 - uv);
    col.rgb   *= mix(0.7, 1.0, pow(vig.x * vig.y * 14.0, 0.3));

    fragColor = clamp(col, 0.0, 1.0);
}
