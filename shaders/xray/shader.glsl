// X-Ray — Medical radiograph / airport security scanner shader
// Luma inversion + edge bone-glow + density heatmap + film grain + lightbox backlight
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash21(vec2 p) { vec3 p3 = fract(vec3(p.xyx)*0.1031); p3 += dot(p3, p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }

float sobelLuma(vec2 uv, vec2 ts)
{
    float tl=dot(texture(iChannel0, uv+ts*vec2(-1,-1)).rgb,vec3(0.299,0.587,0.114));
    float tc=dot(texture(iChannel0, uv+ts*vec2( 0,-1)).rgb,vec3(0.299,0.587,0.114));
    float tr=dot(texture(iChannel0, uv+ts*vec2( 1,-1)).rgb,vec3(0.299,0.587,0.114));
    float ml=dot(texture(iChannel0, uv+ts*vec2(-1, 0)).rgb,vec3(0.299,0.587,0.114));
    float mr=dot(texture(iChannel0, uv+ts*vec2( 1, 0)).rgb,vec3(0.299,0.587,0.114));
    float bl=dot(texture(iChannel0, uv+ts*vec2(-1, 1)).rgb,vec3(0.299,0.587,0.114));
    float bc=dot(texture(iChannel0, uv+ts*vec2( 0, 1)).rgb,vec3(0.299,0.587,0.114));
    float br=dot(texture(iChannel0, uv+ts*vec2( 1, 1)).rgb,vec3(0.299,0.587,0.114));
    float gx=-tl-2.0*ml-bl+tr+2.0*mr+br;
    float gy=-tl-2.0*tc-tr+bl+2.0*bc+br;
    return clamp(sqrt(gx*gx+gy*gy)*4.0, 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 ts = 1.0 / iResolution.xy;
    vec4 raw  = texture(iChannel0, uv);
    float  luma = dot(raw.rgb, vec3(0.299, 0.587, 0.114));

    // ── Core inversion — dense = dark (blocks X-rays), empty = bright ─────
    float density  = 1.0 - luma;
    float inverted = pow(density, 1.4);   // slight gamma to compress shadow end

    // ── Edge glow — structural boundaries appear as bright white lines ────
    float edge     = sobelLuma(uv, ts);
    // Edges are very bright on X-ray — bone and metal boundaries
    float edgeGlow = pow(edge, 0.6) * 0.7;

    // ── Combine into monochrome radiograph base ────────────────────────────
    float xray = clamp(inverted + edgeGlow, 0.0, 1.0);

    // ── Lightbox backlight — slight cool blue-white glow at the centre ────
    vec2 fromCenter = uv - 0.5;
    float  lightbox   = exp(-dot(fromCenter, fromCenter) * 2.5) * 0.06;

    // ── Film base colour — X-ray film is blue-tinted, not pure grey ───────
    // Dense areas (bright on film) lean cooler; thin areas lean warm
    vec3 filmColor;
    filmColor.r = xray * 0.82;
    filmColor.g = xray * 0.92;
    filmColor.b = xray * 1.00 + lightbox;

    // Hot-spot density map: very dense areas get a faint orange-red tint
    // (like a radiologist's highlight on a suspicious area)
    float hotspot = smoothstep(0.75, 1.0, xray);
    filmColor    += hotspot * vec3(0.08, 0.02, -0.05);

    // ── Film grain — X-ray film is coarse ─────────────────────────────────
    float grain  = hash21(uv * vec2(960.0, 540.0) + fract(iTime * 11.1)) - 0.5;
    filmColor   += grain * 0.04;

    // ── Scan line artifact — some X-ray digitizers leave horizontal lines ─
    float scanArt = 1.0 - 0.04 * step(0.95, fract(fragCoord.y * 0.25));
    filmColor    *= scanArt;

    // ── Lightbox frame edge — the physical light panel is slightly visible ─
    vec2 frame  = smoothstep(0.0, 0.02, uv) * smoothstep(1.0, 0.98, uv);
    float  frameMask = frame.x * frame.y;
    filmColor    *= mix(0.3, 1.0, frameMask);

    fragColor = vec4(clamp(filmColor, 0.0, 1.0), 1.0);
}
