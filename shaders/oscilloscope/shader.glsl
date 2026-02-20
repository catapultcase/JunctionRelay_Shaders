#version 300 es
precision mediump float;
// Oscilloscope — Edge-detected content rendered as a glowing vector beam
// Lissajous-style display with electron beam bloom and phosphor persistence
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}

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
    return clamp(sqrt(gx*gx+gy*gy)*5.0, 0.0, 1.0);
}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    vec2 ts = vec2(1.0/1920.0, 1.0/1080.0);

    // Edge detection — these become the "beam traces"
    float edge = sobelLuma(uv, ts);

    // Thicken edges slightly — beam has physical width
    float edgeBlur = 0.0;
    edgeBlur += sobelLuma(uv + ts * vec2( 1,  0), ts);
    edgeBlur += sobelLuma(uv + ts * vec2(-1,  0), ts);
    edgeBlur += sobelLuma(uv + ts * vec2( 0,  1), ts);
    edgeBlur += sobelLuma(uv + ts * vec2( 0, -1), ts);
    edgeBlur /= 4.0;
    float beam = clamp(edge * 1.5 + edgeBlur * 0.5, 0.0, 1.0);

    // Electron beam bloom — bright beam bleeds into surrounding phosphor
    float bloom = 0.0;
    vec2 offsets[8] = vec2[8](
        vec2(2,0),vec2(-2,0),vec2(0,2),vec2(0,-2),
        vec2(1.4,1.4),vec2(-1.4,1.4),vec2(1.4,-1.4),vec2(-1.4,-1.4)
    );
    for(int i=0;i<8;i++)
        bloom += sobelLuma(uv + ts * offsets[i] * 2.0, ts);
    bloom /= 8.0;
    float glowBeam = clamp(beam + bloom * 0.4, 0.0, 1.0);

    // Phosphor colour — classic green P31 oscilloscope phosphor
    vec3 col = vec3(0.0, glowBeam, glowBeam * 0.15);
    // Core of beam is brighter white-green
    col += vec3(beam * 0.1, beam * 0.2, beam * 0.05);

    // Graticule — the grid lines on the oscilloscope face
    vec2 gratUV = fract(uv * vec2(10.0, 8.0));
    float  gratH  = smoothstep(0.01, 0.0, abs(gratUV.x - 0.5)) * 0.08;
    float  gratV  = smoothstep(0.01, 0.0, abs(gratUV.y - 0.5)) * 0.08;
    // Main axes slightly brighter
    vec2 mainAxis = smoothstep(0.008, 0.0, abs(uv - 0.5));
    float  axes    = (mainAxis.x + mainAxis.y) * 0.12;
    col += vec3(0.0, gratH + gratV + axes, 0.0);

    // Oscilloscope background — near black with faint green ambient
    col += vec3(0.0, 0.008, 0.003);

    // Slight beam flicker — electron gun power supply ripple
    float flicker = 0.95 + 0.05 * sin(iTime * 120.0);
    col *= flicker;

    // Phosphor noise
    col.g += (hash21(uv + fract(iTime * 53.1)) - 0.5) * 0.012;

    // Scope face vignette
    vec2 vig = uv * (1.0 - uv);
    col *= pow(vig.x * vig.y * 14.0, 0.3);

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
