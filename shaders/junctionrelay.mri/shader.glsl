// MRI — Medical magnetic resonance imaging display
// Greyscale with clinical blue tint + slice artifacts + k-space noise + field inhomogeneity
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec4 raw  = texture(iChannel0, uv);
    float  luma = dot(raw.rgb, vec3(0.299, 0.587, 0.114));

    // MRI signal is fundamentally T1/T2 weighted — remap tones
    // Bright = high signal (fat/fluid), dark = low signal (air/cortical bone)
    float mriSignal = pow(luma, 0.8);   // slight gamma lift — MRI images are bright

    // Field inhomogeneity — B0 field variation causes slow intensity shading
    // Simulated as a smooth low-frequency intensity gradient across the FOV
    float inhomo = noise2(uv * 2.5) * 0.12 - 0.06;
    mriSignal = clamp(mriSignal + inhomo, 0.0, 1.0);

    // Gibbs ringing / truncation artifact — bright edges produce oscillating bands
    // Approximate with a sin wave perpendicular to high-gradient areas
    vec2 ts = 1.0 / iResolution.xy;
    float  gx = texture(iChannel0, uv+ts*vec2(2,0)).r - texture(iChannel0, uv-ts*vec2(2,0)).r;
    float  gy = texture(iChannel0, uv+ts*vec2(0,2)).g - texture(iChannel0, uv-ts*vec2(0,2)).g;
    float  gradMag = clamp(sqrt(gx*gx+gy*gy) * 8.0, 0.0, 1.0);
    float  gibbs   = sin(luma * 60.0) * 0.03 * gradMag;
    mriSignal      = clamp(mriSignal + gibbs, 0.0, 1.0);

    // Gaussian noise — MRI has thermal noise from the receiver coil
    float noiseR = (hash21(fragCoord + vec2(iTime * 7.3, 0)) - 0.5);
    float noiseI = (hash21(fragCoord + vec2(0, iTime * 7.3)) - 0.5);
    // Rician noise (magnitude of complex Gaussian — standard in MRI)
    float ricianNoise = sqrt(noiseR*noiseR + noiseI*noiseI) * 0.025;
    mriSignal = clamp(mriSignal + ricianNoise - 0.012, 0.0, 1.0);

    // k-space spike — periodic ghosting from gradient errors
    // Creates faint copies of bright structures offset in phase-encode direction
    float ghost = dot(texture(iChannel0, vec2(uv.x, fract(uv.y + 0.15))).rgb, vec3(0.299,0.587,0.114)) * 0.06;
    mriSignal = clamp(mriSignal + ghost * gradMag, 0.0, 1.0);

    // Clinical blue-grey MRI monitor colour
    vec3 col;
    col.r = mriSignal * 0.82;
    col.g = mriSignal * 0.91;
    col.b = mriSignal * 1.00;

    // Windowing — MRI is always displayed with a specific window/level
    // Slight contrast enhancement in midtones (typical clinical window)
    col = clamp((col - 0.1) * 1.25, 0.0, 1.0);

    // PACS viewer black border
    vec2 border = smoothstep(0.0, 0.008, uv) * smoothstep(1.0, 0.992, uv);
    col *= border.x * border.y;

    // Measurement overlay — faint crosshair at image centre
    vec2 ch = smoothstep(0.002, 0.0, abs(uv - 0.5));
    col += clamp(ch.x + ch.y, 0.0, 1.0) * vec3(0.05, 0.1, 0.15) * 0.5;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
