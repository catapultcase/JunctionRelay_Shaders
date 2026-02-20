#version 300 es
precision mediump float;
// Predator — Active camouflage shimmer effect
// Content barely visible through chromatic displacement + heat distortion + edge plasma glow
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);}
float fbm(vec2 p){float v=0.0,a=0.5;mat2 r=mat2(0.8,-0.6,0.6,0.8);for(int i=0;i<5;i++){v+=a*noise2(p);p=r * p*2.1;a*=0.5;}return v;}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // Primary displacement — the cloaking device bends light around the wearer
    vec2 dispUV = uv * 4.0 + vec2(iTime * 0.15, iTime * 0.11);
    float  dispX  = fbm(dispUV) - 0.5;
    float  dispY  = fbm(dispUV + vec2(3.7, 1.9)) - 0.5;

    // Secondary micro-tremor — the cloak isn't perfect, it shimmers
    float  tremFreq = 22.0;
    float  tremX = sin(uv.y * tremFreq + iTime * 8.0) * 0.002;
    float  tremY = sin(uv.x * tremFreq * 1.3 - iTime * 6.5) * 0.001;

    vec2 displacement = vec2(dispX, dispY) * 0.03 + vec2(tremX, tremY);

    // Each colour channel displaced differently — chromatic aberration of cloaking
    vec2 uvR = clamp(uv + displacement * 1.20, 0.0, 1.0);
    vec2 uvG = clamp(uv + displacement * 1.00, 0.0, 1.0);
    vec2 uvB = clamp(uv + displacement * 0.82, 0.0, 1.0);

    float r = texture(iChannel0, uvR).r;
    float g = texture(iChannel0, uvG).g;
    float b = texture(iChannel0, uvB).b;

    // The cloaked form is mostly transparent — reduce visibility significantly
    vec3 col = vec3(r, g, b) * 0.35;

    // Edge plasma glow — the Predator's outline shimmers with bio-electric energy
    // Detected by sampling displaced vs undisplaced and finding the differential
    float lumaCloaked = dot(col, vec3(0.299, 0.587, 0.114));
    float lumaOrig    = dot(texture(iChannel0, uv).rgb, vec3(0.299, 0.587, 0.114));
    float edgeDiff    = abs(lumaCloaked - lumaOrig * 0.35);

    // Plasma colour — shifts between orange and blue-white like thermal discharge
    float plasmaShift = sin(iTime * 2.3 + uv.y * 8.0) * 0.5 + 0.5;
    vec3 plasma1    = vec3(1.0, 0.4, 0.1);   // hot orange
    vec3 plasma2    = vec3(0.3, 0.7, 1.0);   // cool blue
    vec3 plasmaCol  = mix(plasma1, plasma2, plasmaShift);

    float plasmaGlow = pow(edgeDiff, 0.6) * 1.5;
    col += plasmaGlow * plasmaCol;

    // Interference fringe — like a holographic diffraction pattern overlaid
    float fringe = sin(uv.x * 180.0 + dispX * 40.0 + iTime * 4.0) * 0.5 + 0.5;
    fringe      *= sin(uv.y * 140.0 + dispY * 35.0 - iTime * 3.2) * 0.5 + 0.5;
    fringe       = pow(fringe, 3.0) * 0.08;
    col         += fringe * vec3(0.2, 0.8, 1.0);

    // Very faint original scene underneath — the cloak isn't perfect
    col += texture(iChannel0, uv).rgb * 0.08;

    // Environmental darkness — the Predator's cloak absorbs some light
    vec2 vig = uv * (1.0 - uv);
    col *= mix(0.6, 1.0, pow(vig.x * vig.y * 12.0, 0.25));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
