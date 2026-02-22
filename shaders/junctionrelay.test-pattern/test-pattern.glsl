// Test Pattern — diagnostic shader for orientation, alignment, and edge detection
// Reveals flipping, mirroring, cropping, and color accuracy issues
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

// ── Helpers ──────────────────────────────────────────────────────────────────

// 7-segment digit renderer (segments: top, top-right, bot-right, bot, bot-left, top-left, mid)
float segment(vec2 p, float s) {
  // Horizontal segment
  return step(abs(p.x), 0.4 * s) * step(abs(p.y), 0.06 * s);
}

float segmentV(vec2 p, float s) {
  // Vertical segment
  return step(abs(p.x), 0.06 * s) * step(abs(p.y), 0.4 * s);
}

float digit(vec2 p, int d, float s) {
  float r = 0.0;
  // Scale into digit space
  vec2 q = p / s;

  // Segments: a=top, b=top-right, c=bot-right, d=bottom, e=bot-left, f=top-left, g=middle
  float a = segment(q - vec2(0.0, 0.8), 1.0);
  float b = segmentV(q - vec2(0.4, 0.4), 1.0);
  float c = segmentV(q - vec2(0.4, -0.4), 1.0);
  float dd = segment(q - vec2(0.0, -0.8), 1.0);
  float e = segmentV(q - vec2(-0.4, -0.4), 1.0);
  float f = segmentV(q - vec2(-0.4, 0.4), 1.0);
  float g = segment(q, 1.0);

  if (d == 0) r = a + b + c + dd + e + f;
  if (d == 1) r = b + c;
  if (d == 2) r = a + b + dd + e + g;
  if (d == 3) r = a + b + c + dd + g;
  if (d == 4) r = b + c + f + g;
  if (d == 5) r = a + c + dd + f + g;
  if (d == 6) r = a + c + dd + e + f + g;
  if (d == 7) r = a + b + c;
  if (d == 8) r = a + b + c + dd + e + f + g;
  if (d == 9) r = a + b + c + dd + f + g;

  return clamp(r, 0.0, 1.0);
}

// Arrow shape pointing up
float arrow(vec2 p, float size) {
  // Triangle head
  float head = step(abs(p.x), (0.5 - p.y / size) * size * 0.5) * step(0.0, p.y) * step(p.y, size * 0.5);
  // Shaft
  float shaft = step(abs(p.x), size * 0.08) * step(-size * 0.5, p.y) * step(p.y, 0.0);
  return clamp(head + shaft, 0.0, 1.0);
}

// Box outline
float box(vec2 p, vec2 half_size, float thickness) {
  vec2 d = abs(p) - half_size;
  float outer = step(d.x, 0.0) * step(d.y, 0.0);
  vec2 d2 = abs(p) - (half_size - vec2(thickness));
  float inner = step(d2.x, 0.0) * step(d2.y, 0.0);
  return outer - inner;
}

// Circle
float circle(vec2 p, float radius, float thickness) {
  float d = length(p);
  return step(radius - thickness, d) * step(d, radius);
}

// Filled circle
float disc(vec2 p, float radius) {
  return step(length(p), radius);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 res = iResolution.xy;
  vec2 uv = fragCoord.xy / res;
  vec2 px = fragCoord.xy;

  // Background: dim passthrough of the input texture
  vec4 tex = texture(iChannel0, uv);
  vec3 col = tex.rgb * 0.15;

  // ── Grid ────────────────────────────────────────────────────────────────
  // Major grid (10% intervals)
  float gridMajor = step(mod(uv.x, 0.1), 0.001) + step(mod(uv.y, 0.1), 0.001);
  // Minor grid (5% intervals)
  float gridMinor = step(mod(uv.x, 0.05), 0.0005) + step(mod(uv.y, 0.05), 0.0005);
  col += vec3(0.15) * clamp(gridMinor, 0.0, 1.0);
  col += vec3(0.15) * clamp(gridMajor, 0.0, 1.0);

  // ── Center crosshair ───────────────────────────────────────────────────
  vec2 center = px - res * 0.5;
  float crossH = step(abs(center.y), 1.0) * step(abs(center.x), 80.0);
  float crossV = step(abs(center.x), 1.0) * step(abs(center.y), 80.0);
  float centerCircle = circle(center, 40.0, 2.0);
  float centerCircle2 = circle(center, 20.0, 1.5);
  col += vec3(1.0, 1.0, 1.0) * clamp(crossH + crossV + centerCircle + centerCircle2, 0.0, 1.0);

  // ── Corner markers (numbered 1-4, clockwise from top-left) ─────────────
  float cornerSize = 60.0;
  float boxHalf = 30.0;

  // Top-left: "1" — red box with digit inside
  vec2 tl = px - vec2(cornerSize, res.y - cornerSize);
  col += vec3(1.0, 0.0, 0.0) * box(tl, vec2(boxHalf), 3.0);
  col += vec3(1.0, 0.0, 0.0) * digit(tl, 1, 18.0);

  // Top-right: "2" — green box with digit inside
  vec2 tr = px - vec2(res.x - cornerSize, res.y - cornerSize);
  col += vec3(0.0, 1.0, 0.0) * box(tr, vec2(boxHalf), 3.0);
  col += vec3(0.0, 1.0, 0.0) * digit(tr, 2, 18.0);

  // Bottom-left: "3" — blue box with digit inside
  vec2 bl = px - vec2(cornerSize, cornerSize);
  col += vec3(0.0, 0.5, 1.0) * box(bl, vec2(boxHalf), 3.0);
  col += vec3(0.0, 0.5, 1.0) * digit(bl, 3, 18.0);

  // Bottom-right: "4" — yellow box with digit inside
  vec2 br = px - vec2(res.x - cornerSize, cornerSize);
  col += vec3(1.0, 1.0, 0.0) * box(br, vec2(boxHalf), 3.0);
  col += vec3(1.0, 1.0, 0.0) * digit(br, 4, 18.0);

  // ── Directional arrows ─────────────────────────────────────────────────
  float arrowSize = 40.0;

  // Top arrow (pointing UP) — white
  vec2 topA = px - vec2(res.x * 0.5, res.y - 80.0);
  col += vec3(1.0) * arrow(topA, arrowSize);

  // Bottom arrow (pointing DOWN) — white
  vec2 botA = px - vec2(res.x * 0.5, 80.0);
  col += vec3(1.0) * arrow(vec2(botA.x, -botA.y), arrowSize);

  // Left arrow (pointing LEFT) — white
  vec2 leftA = px - vec2(80.0, res.y * 0.5);
  col += vec3(1.0) * arrow(vec2(leftA.y, -leftA.x), arrowSize);

  // Right arrow (pointing RIGHT) — white
  vec2 rightA = px - vec2(res.x - 80.0, res.y * 0.5);
  col += vec3(1.0) * arrow(vec2(-rightA.y, rightA.x), arrowSize);

  // ── Color bars (bottom strip) ──────────────────────────────────────────
  if (uv.y < 0.06) {
    float barIdx = floor(uv.x * 8.0);
    if (barIdx == 0.0) col = vec3(1.0, 1.0, 1.0);      // White
    else if (barIdx == 1.0) col = vec3(1.0, 1.0, 0.0);  // Yellow
    else if (barIdx == 2.0) col = vec3(0.0, 1.0, 1.0);  // Cyan
    else if (barIdx == 3.0) col = vec3(0.0, 1.0, 0.0);  // Green
    else if (barIdx == 4.0) col = vec3(1.0, 0.0, 1.0);  // Magenta
    else if (barIdx == 5.0) col = vec3(1.0, 0.0, 0.0);  // Red
    else if (barIdx == 6.0) col = vec3(0.0, 0.0, 1.0);  // Blue
    else col = vec3(0.0, 0.0, 0.0);                      // Black
  }

  // ── Grayscale ramp (top strip) ─────────────────────────────────────────
  if (uv.y > 0.94) {
    col = vec3(uv.x);
  }

  // ── Corner-to-corner diagonal lines (detect rotation/skew) ─────────────
  // Top-left to bottom-right
  float diag1 = step(abs(px.y - (res.y - px.x * res.y / res.x)), 1.5);
  // Top-right to bottom-left
  float diag2 = step(abs(px.y - px.x * res.y / res.x), 1.5);
  col += vec3(0.3, 0.0, 0.3) * clamp(diag1 + diag2, 0.0, 1.0);

  // ── Animated sweep line (proves iTime is working) ──────────────────────
  float sweep = mod(iTime * 0.2, 1.0);
  float sweepLine = step(abs(uv.x - sweep), 0.002);
  col += vec3(0.0, 1.0, 0.5) * sweepLine;

  // ── Aspect ratio circles (should be perfectly round if aspect is correct) ─
  col += vec3(0.4) * circle(center, 200.0, 1.5);
  col += vec3(0.4) * circle(center, 400.0, 1.5);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
