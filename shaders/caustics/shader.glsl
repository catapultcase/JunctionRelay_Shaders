#version 300 es
precision mediump float;
// Caustics — Dancing light grid projected onto content from above
// Bright summery pool-floor light patterns, animated interference of refracted rays
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p) { vec3 p3=fract(vec3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float noise2(vec2 p) {
    vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);
}

float causticPattern(vec2 p, float t)
{
    float c = 0.0;
    c += sin(p.x * 6.0 + sin(p.y * 4.0 + t * 0.7) + t * 1.1);
    c += sin(p.y * 5.0 + sin(p.x * 3.5 - t * 0.5) - t * 0.9);
    c += sin((p.x + p.y) * 4.5 + t * 0.6);
    return pow(clamp(c / 3.0 * 0.5 + 0.5, 0.0, 1.0), 4.0);
}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    vec4 col = texture(iChannel0, uv);

    vec2 waterUV = uv * 6.0;
    float dx = noise2(waterUV + vec2(iTime * 0.3, 0)) - 0.5;
    float dy = noise2(waterUV + vec2(0, iTime * 0.25)) - 0.5;

    vec2 causticUV = uv * 5.0 + vec2(dx, dy) * 0.3;
    float  c1 = causticPattern(causticUV, iTime);
    float  c2 = causticPattern(causticUV * 1.3 + 0.7, iTime * 1.1);
    float  caustic = (c1 + c2 * 0.5) / 1.5;

    vec3 lightColor = mix(vec3(0.6, 0.9, 1.0), vec3(1.0, 0.98, 0.85), caustic);
    col.rgb *= 1.0 + caustic * lightColor * 1.2;
    col.rgb = mix(col.rgb, col.rgb * vec3(0.75, 0.92, 1.0), 0.25);

    vec2 ripple = vec2(dx, dy) * 0.006;
    col.rgb = mix(col.rgb, texture(iChannel0, clamp(uv + ripple, 0.0, 1.0)).rgb, 0.3);

    vec2 vig = uv * (1.0 - uv);
    col.rgb *= mix(0.5, 1.0, pow(vig.x * vig.y * 12.0, 0.3));

    fragColor = clamp(col, 0.0, 1.0);
}
