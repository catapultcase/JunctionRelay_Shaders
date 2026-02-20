// Radar — Military PPI radar sweep display
// Rotating scan line + contact paint & decay + green phosphor + range rings
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 centered = uv * 2.0 - 1.0;
    centered.x *= iResolution.x / iResolution.y;   // aspect correct

    float dist  = length(centered);
    float angle = atan(centered.y, centered.x);   // -PI to PI

    // Sweep angle — full rotation every 4 seconds
    float sweepSpeed = 3.14159 * 2.0 / 4.0;
    float sweepAngle = mod(iTime * sweepSpeed, 3.14159 * 2.0) - 3.14159;

    // Angular distance from sweep beam (accounting for wrap)
    float angleDiff = angle - sweepAngle;
    angleDiff = angleDiff - floor((angleDiff + 3.14159) / (2.0 * 3.14159)) * 2.0 * 3.14159;

    // Sweep beam — bright leading edge, trailing phosphor decay
    float beamWidth   = 0.05;
    float decayLength = 1.8;   // radians of trail
    float beam = 0.0;
    if (angleDiff > -beamWidth && angleDiff < 0.0)
        beam = 1.0;   // leading edge
    else if (angleDiff < 0.0 && angleDiff > -decayLength)
        beam = exp(angleDiff * 2.5);   // exponential phosphor decay

    // Sample source for contact detection
    vec4 raw  = texture(iChannel0, uv);
    float  luma = dot(raw.rgb, vec3(0.299, 0.587, 0.114));

    // Contacts — bright areas in the source become radar returns
    // Only visible in the sweep wake (phosphor painted and decaying)
    float decayMask = exp(min(angleDiff, 0.0) * 1.8) * step(angleDiff, 0.0);
    float contact   = luma * decayMask * 1.5;

    // Combine beam and contacts
    float signal = clamp(beam * 0.8 + contact, 0.0, 1.0);

    // Green phosphor glow
    vec3 phosphor = vec3(0.05, signal, 0.05 * signal);
    phosphor       += vec3(0.0, pow(signal, 0.5) * 0.3, 0.0);   // bloom

    // Range rings — concentric circles at fixed intervals
    float ringSpacing = 0.25;
    float ring = smoothstep(0.008, 0.0, abs(mod(dist, ringSpacing) - 0.0));
    ring      += smoothstep(0.004, 0.0, abs(mod(dist, ringSpacing) - ringSpacing * 0.5)) * 0.3;
    phosphor  += vec3(0.0, ring * 0.25, 0.0);

    // Crosshair
    float ch = smoothstep(0.003, 0.0, abs(centered.x)) + smoothstep(0.003, 0.0, abs(centered.y));
    phosphor += vec3(0.0, clamp(ch, 0.0, 1.0) * 0.2, 0.0);

    // Clip to circular display area
    float circleMask = step(dist, 1.0);
    phosphor *= circleMask;

    // Bezel — dark border outside the scope face
    vec3 col = phosphor + vec3(0.0, 0.01, 0.0) * circleMask;

    // Phosphor grain
    col.g += (hash21(uv + fract(iTime * 47.0)) - 0.5) * 0.015 * circleMask;

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
