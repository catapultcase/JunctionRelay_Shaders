// Kinescope — 1940s TV broadcast recorded off a CRT onto 16mm film
// Softer and ghostlier than VHS — bloom halation, phosphor persistence, film weave
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash11(float p){p=fract(p*0.1031);p*=p+33.33;p*=p+p;return fract(p);}
float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // Film weave — the 16mm frame physically wobbles in the gate
    float frameT = floor(iTime * 18.0);   // 18fps kinescope
    float weaveX = (hash11(frameT * 0.37) - 0.5) * 0.004;
    float weaveY = (hash11(frameT * 0.71) - 0.5) * 0.002;
    vec2 weavedUV = clamp(uv + vec2(weaveX, weaveY), 0.0, 1.0);

    vec4 col = texture(iChannel0, weavedUV);
    float  luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));

    // Monochrome — kinescopes were B&W
    col.rgb = vec3(luma, luma, luma);

    // Phosphor persistence / ghosting — CRT phosphor holds image briefly
    // Approximated with a slight upward smear (phosphor decays as beam moves on)
    float ghostLuma = dot(texture(iChannel0, clamp(weavedUV - vec2(0, 0.003), 0.0, 1.0)).rgb, vec3(0.299,0.587,0.114));
    col.rgb = mix(col.rgb, vec3(ghostLuma,ghostLuma,ghostLuma), 0.2);

    // Bloom halation — CRT highlights bleed into surrounding film emulsion
    float bloom = 0.0;
    bloom += dot(texture(iChannel0, clamp(weavedUV + vec2( 0.003, 0), 0.0, 1.0)).rgb, vec3(0.299,0.587,0.114));
    bloom += dot(texture(iChannel0, clamp(weavedUV + vec2(-0.003, 0), 0.0, 1.0)).rgb, vec3(0.299,0.587,0.114));
    bloom += dot(texture(iChannel0, clamp(weavedUV + vec2(0,  0.003), 0.0, 1.0)).rgb, vec3(0.299,0.587,0.114));
    bloom += dot(texture(iChannel0, clamp(weavedUV + vec2(0, -0.003), 0.0, 1.0)).rgb, vec3(0.299,0.587,0.114));
    bloom /= 4.0;
    float halation = pow(bloom, 2.5) * 0.35;
    col.rgb += halation;

    // Warm base tint — 1940s film stock had a warm silver-gelatin base
    col.rgb *= vec3(1.05, 1.0, 0.90);

    // Contrast curve — kinescopes were contrasty with crushed shadows
    col.rgb = pow(clamp(col.rgb, 0.0, 1.0), vec3(1.3));
    col.rgb = clamp(col.rgb * 1.15 - 0.05, 0.0, 1.0);

    // Scanlines — CRT raster visible through the film
    float scanline = 0.82 + 0.18 * step(0.5, fract(fragCoord.y * 0.5));
    col.rgb *= scanline;

    // Coarse film grain — 16mm is grainy
    float grain = hash21(weavedUV * vec2(480.0, 270.0) + fract(iTime * 31.3)) - 0.5;
    col.rgb += grain * 0.07;

    // Frame flicker — exposure variation between frames
    float flicker = 0.88 + 0.12 * hash11(frameT * 0.13);
    col.rgb *= flicker;

    // Vertical scratch — rare but persistent frame scratch on the film
    float scratchX = 0.63;
    float scratchMask = step(abs(uv.x - scratchX), 0.001) * step(0.8, hash11(floor(uv.y * 200.0) + frameT * 0.1));
    col.rgb += scratchMask * 0.5;

    // Vignette — lens falloff on the kinescope camera filming the CRT
    vec2 vig = uv * (1.0 - uv);
    col.rgb *= pow(vig.x * vig.y * 16.0, 0.4);

    fragColor = clamp(col, 0.0, 1.0);
}
