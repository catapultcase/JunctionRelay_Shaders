// Kaleidoscope — pass 1: bloom post-process
// Reads pass 0 output from iChannel0, applies a soft glow from trail data in alpha

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 src = texture(iChannel0, uv);

    // Simple 9-tap bloom kernel from trail luminance stored in alpha
    float bloom = 0.0;
    float px = 1.0 / iResolution.x;
    float py = 1.0 / iResolution.y;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 offset = vec2(float(x) * px * 3.0, float(y) * py * 3.0);
            bloom += texture(iChannel0, uv + offset).a;
        }
    }
    bloom /= 9.0;

    // Blend bloom glow into the original colour
    vec3 col = src.rgb + src.rgb * bloom * bloomAmount;

    // Tone-map to prevent clipping
    col = col / (1.0 + col);

    fragColor = vec4(col, 1.0);
}
