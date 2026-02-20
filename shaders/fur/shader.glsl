// Fur — Directional strand overlay with anisotropic sheen
// Elongated noise strands + flow field clumping + Kajiya-Kay specular + root/tip gradient
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash11(float p){p=fract(p*0.1031);p*=p+33.33;p*=p+p;return fract(p);}
float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float hash22x(vec2 p){return hash21(p);}
float hash22y(vec2 p){return hash21(p+vec2(37.1,67.3));}

float noise2(vec2 p){
    vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),
                mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);
}
float fbm2(vec2 p){
    float v=0.0,a=0.5;
    mat2 r=mat2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<3;i++){v+=a*noise2(p);p=r * p*2.1;a*=0.5;}
    return v;
}

// ── Strand function ───────────────────────────────────────────────────────────
// Given a UV and a strand direction, returns how much strand is present
// and how far along the strand we are (0=root, 1=tip)
vec2 strandSample(vec2 uv, vec2 dir, float freq, float seed)
{
    // Rotate UV into strand space: one axis along strand, one across
    vec2 perp = vec2(-dir.y, dir.x);
    float  along = dot(uv, dir);
    float  across = dot(uv, perp);

    // Cell grid across strands
    float cellAcross = floor(across * freq);
    float fracAcross = fract(across * freq);

    // Each strand column gets a random offset along its length (staggered roots)
    float strandSeed  = hash11(cellAcross * 0.137 + seed);
    float strandPhase = hash11(cellAcross * 0.371 + seed + 1.3);

    // Strand position within cell (slight random wobble side to side)
    float strandCenter = 0.5 + (hash11(cellAcross + seed * 7.3) - 0.5) * 0.3;
    float distAcross   = abs(fracAcross - strandCenter);

    // Strand width: thin at tip, wider at root
    float strandLen  = 0.5 + strandSeed * 0.5;   // varying lengths
    float alongNorm  = fract(along * freq * 0.2 + strandPhase);   // 0=root, 1=tip
    float tipT       = 1.0 - alongNorm;           // 1 at root, 0 at tip
    float strandWidth = mix(0.05, 0.18, tipT);   // wider at root

    float inStrand = step(distAcross, strandWidth) * step(alongNorm, strandLen);

    return vec2(inStrand, tipT);   // x=presence, y=root-to-tip (0=tip,1=root)
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec4 baseCol = texture(iChannel0, uv);
    float  luma    = dot(baseCol.rgb, vec3(0.299, 0.587, 0.114));

    // ── 1. Flow field — fur lies in locally consistent directions ─────────────
    // Low-frequency noise field drives the strand angle per region
    float flowAngle  = fbm2(uv * 2.5) * 6.28318;
    // Add a gentle global lean (fur naturally falls with gravity)
    flowAngle       += 1.1;   // ~63 degrees — diagonal lean
    vec2 flowDir   = vec2(cos(flowAngle), sin(flowAngle));

    // Slight secondary flow for parting/clumping variation
    float flow2Angle = fbm2(uv * 1.8 + vec2(3.7, 1.2)) * 3.14159 - 1.57;
    vec2 flowDir2  = vec2(cos(flow2Angle), sin(flow2Angle));

    // ── 2. Multi-layer strands — fine, medium, and coarse for depth ───────────

    // Fine layer — dense underlayer
    vec2 s1 = strandSample(uv * vec2(1.78, 1.0), flowDir,  90.0, 0.0);
    // Medium layer — main visible fur
    vec2 s2 = strandSample(uv * vec2(1.78, 1.0), flowDir,  55.0, 3.7);
    // Coarse layer — guard hairs, longer and sparser
    vec2 s3 = strandSample(uv * vec2(1.78, 1.0), flowDir2, 28.0, 7.1);

    // Combine — coarser layers on top
    float strandMask = clamp(s1.x * 0.4 + s2.x * 0.7 + s3.x * 1.0, 0.0, 1.0);
    float tipT       = s2.x > 0.5 ? s2.y : (s3.x > 0.5 ? s3.y : s1.y);

    // ── 3. Strand colour — root darker, tip lighter (natural fur gradient) ────
    // Sample content colour at the "root" position (pulled back along strand dir)
    vec2 rootUV  = clamp(uv - flowDir * 0.012, 0.0, 1.0);
    vec4 rootCol = texture(iChannel0, rootUV);

    // Root: darker, more saturated version of the base colour
    vec3 rootColor = rootCol.rgb * vec3(0.55, 0.52, 0.50);
    // Tip: lighter, slightly desaturated
    float rootLuma  = dot(rootCol.rgb, vec3(0.299,0.587,0.114));
    vec3 tipColor = mix(rootCol.rgb, vec3(rootLuma,rootLuma,rootLuma)*1.4, 0.3)
                    * vec3(1.15, 1.12, 1.08);

    vec3 strandColor = mix(tipColor, rootColor, tipT);

    // ── 4. Anisotropic specular — Kajiya-Kay model ────────────────────────────
    // Light direction (fixed overhead-slightly-front)
    vec3 lightDir = normalize(vec3(0.3, -0.7, 0.6));
    vec3 viewDir  = vec3(0.0, 0.0, 1.0);

    // Strand tangent in 3D (treat UV strand dir as XY, Z=0)
    vec3 tangent  = normalize(vec3(flowDir.x, flowDir.y, 0.15));

    // Kajiya-Kay: sinTheta = sqrt(1 - dot(tangent,lightDir)^2)
    float  TdotL    = dot(tangent, lightDir);
    float  sinTL    = sqrt(clamp(1.0 - TdotL * TdotL, 0.0, 1.0));
    float  TdotV    = dot(tangent, viewDir);
    float  sinTV    = sqrt(clamp(1.0 - TdotV * TdotV, 0.0, 1.0));

    // Diffuse + specular lobes
    float  furDiffuse  = sinTL * 0.7 + 0.3;   // wrap lighting
    float  furSpecular = pow(clamp(sinTL * sinTV + TdotL * TdotV, 0.0, 1.0), 18.0);

    // Specular band sits near tips
    float  specMask = pow(1.0 - tipT, 2.0);   // stronger at tips
    vec3 specColor = vec3(1.0, 0.97, 0.92) * furSpecular * specMask * 1.2;

    // ── 5. Compose ────────────────────────────────────────────────────────────
    // Base: original content tinted by fur diffuse shading
    vec3 col = baseCol.rgb * furDiffuse * 0.6;

    // Fur strand overlay
    col = mix(col, strandColor * furDiffuse + specColor, strandMask * 0.92);

    // ── 6. Inter-strand shadow — dark gaps between strands read as depth ───────
    float shadow = (1.0 - strandMask) * 0.5;
    col         *= 1.0 - shadow * 0.6;

    // ── 7. Subtle surface normal shimmer — fur sheen shifts with position ──────
    float sheen = pow(clamp(sin(dot(uv, flowDir) * 180.0) * 0.5 + 0.5, 0.0, 1.0), 6.0) * 0.08;
    col        += sheen * vec3(1.0, 0.98, 0.94);

    // ── 8. Slight warmth — most fur has warm undertones ───────────────────────
    col *= vec3(1.04, 1.01, 0.96);

    // ── 9. Vignette ───────────────────────────────────────────────────────────
    vec2 vig = uv * (1.0 - uv);
    col *= mix(0.6, 1.0, pow(vig.x * vig.y * 14.0, 0.3));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
