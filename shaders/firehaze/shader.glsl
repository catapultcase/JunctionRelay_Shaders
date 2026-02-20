#version 300 es
precision mediump float;
// FireHaze — Content seen through rising heat distortion with fire emission glow
// Hot air refractive shimmer + ember particles + infrared bloom on bright areas
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash11(float p) { p=fract(p*0.1031); p*=p+33.33; p*=p+p; return fract(p); }
float hash21(vec2 p) { vec3 p3=fract(vec3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float noise2(vec2 p) {
    vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);
}
float fbm(vec2 p) {
    float v=0.0,a=0.5;
    mat2 r=mat2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<4;i++){v+=a*noise2(p);p=r * p*2.1;a*=0.5;}
    return v;
}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // Heat rises from the bottom — strongest distortion near base
    float heatStrength = pow(1.0 - uv.y, 2.0) * 0.5 + 0.05;

    // Turbulent rising columns of hot air
    vec2 heatUV = vec2(uv.x * 3.0, uv.y * 2.0 - iTime * 0.4);
    float  heatX  = fbm(heatUV) - 0.5;
    float  heatY  = fbm(heatUV + vec2(5.2, 1.3)) - 0.5;

    vec2 distort = vec2(heatX, heatY * 0.3) * heatStrength * 0.04;
    vec2 warpedUV = clamp(uv + distort, 0.0, 1.0);

    vec4 col = texture(iChannel0, warpedUV);
    float  luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));

    // Colour shift — heat shifts the spectrum toward red/orange
    float heatTint = heatStrength * 0.6;
    col.rgb = mix(col.rgb, col.rgb * vec3(1.15, 0.85, 0.55), heatTint);

    // Bloom on bright areas — fire makes everything around it glow orange
    float bloom = smoothstep(0.6, 1.0, luma);
    col.rgb += bloom * vec3(0.4, 0.15, 0.0) * heatStrength * 2.0;

    // Ember particles — tiny bright orange sparks rising
    vec2 emberGrid = vec2(uv.x * 120.0, uv.y * 70.0 + iTime * 1.8);
    vec2 emberCell = floor(emberGrid);
    vec2 emberFrac = fract(emberGrid);
    vec2 emberPos  = vec2(hash21(emberCell), hash21(emberCell + 7.3));
    // Sparks drift sideways slightly as they rise
    emberPos.x      += sin(iTime * (0.5 + hash21(emberCell) * 2.0) + emberCell.y) * 0.3;
    float emberLife  = fract(hash21(emberCell + 2.1) + iTime * (0.3 + hash21(emberCell) * 0.4));
    float emberDist  = length(emberFrac - emberPos);
    float ember      = step(emberDist, 0.04) * emberLife * (1.0 - uv.y);
    // Only spawn embers in lower 2/3 of screen
    ember           *= step(uv.y, 0.7);
    col.rgb         += ember * vec3(1.0, 0.4, 0.05) * 2.0;

    // Smoke darkening in upper areas
    float smoke = fbm(vec2(uv.x * 2.0, uv.y * 1.5 - iTime * 0.15)) * smoothstep(0.3, 0.0, uv.y);
    col.rgb     *= 1.0 - smoke * 0.4;

    // Vignette — darkness at edges like looking through flames
    vec2 vig = uv * (1.0 - uv);
    col.rgb   *= mix(0.3, 1.0, pow(vig.x * vig.y * 10.0, 0.4));

    fragColor = clamp(col, 0.0, 1.0);
}
