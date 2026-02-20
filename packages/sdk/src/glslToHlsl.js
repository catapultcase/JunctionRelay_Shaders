/**
 * @junctionrelay/shader-sdk
 * MIT License — Copyright (c) 2024-present Jonathan Mills, CatapultCase
 *
 * GLSL -> HLSL On-Demand Converter
 *
 * Converts GLSL ES 300 fragment shaders (the canonical format) to HLSL for the
 * Windows DX11 texture bridge sidecar. The conversion is mechanical and constrained
 * to the JunctionRelay shader contract:
 *
 *   GLSL: uniform sampler2D iChannel0; uniform float iTime; out vec4 fragColor;
 *   HLSL: Texture2D tex0:t0; SamplerState sampler0:s0; cbuffer CB:b0 { float time; }
 *
 * No external dependencies — pure string manipulation.
 */

/**
 * Convert a GLSL ES 300 fragment shader to HLSL (SM5).
 * @param {string} glslSource - The GLSL shader source
 * @returns {string} HLSL shader source
 */
function convertGlslToHlsl(glslSource) {
  let s = glslSource;

  // 1. Strip #version and precision lines
  s = s.replace(/^#version\s+.*$/m, '');
  s = s.replace(/^precision\s+.*$/m, '');

  // 2. Replace uniform declarations with HLSL equivalents
  s = s.replace(/uniform\s+sampler2D\s+iChannel0\s*;/,
    'Texture2D tex0 : register(t0);\nSamplerState sampler0 : register(s0);');
  s = s.replace(/uniform\s+float\s+iTime\s*;/,
    'cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };');

  // 3. Remove out vec4 fragColor declaration
  s = s.replace(/out\s+vec4\s+fragColor\s*;/, '');

  // 4. Replace types (longer patterns first)
  s = s.replace(/\bmat4\b/g, 'float4x4');
  s = s.replace(/\bmat3\b/g, 'float3x3');
  s = s.replace(/\bmat2\b/g, 'float2x2');
  s = s.replace(/\bvec4\b/g, 'float4');
  s = s.replace(/\bvec3\b/g, 'float3');
  s = s.replace(/\bvec2\b/g, 'float2');

  // 4b. GLSL vec3(scalar) broadcasts to all components; HLSL float3(scalar) is invalid.
  // Convert single-arg floatN constructors to HLSL cast syntax: (floatN)(expr)
  s = replaceScalarBroadcastConstructors(s);

  // 5. Replace function names
  s = s.replace(/\bmix\b/g, 'lerp');
  s = s.replace(/\bfract\b/g, 'frac');
  s = s.replace(/\bmod\b/g, 'fmod');
  // atan(y,x) stays as atan2 — but in GLSL atan is used for both single and two-arg
  // Only replace two-arg atan calls (with a comma inside)
  s = s.replace(/\batan\s*\(/g, 'atan2(');

  // 6. Replace iTime -> time
  s = s.replace(/\biTime\b/g, 'time');

  // 7. Replace texture sampling
  s = s.replace(/texture\s*\(\s*iChannel0\s*,/g, 'tex0.Sample(sampler0,');

  // 8. Replace clamp(x, 0.0, 1.0) with saturate(x) for common patterns
  s = replaceSaturatePattern(s);

  // 9. Replace gl_FragCoord with pos in main body, and restructure main
  // First, find and replace the UV derivation line
  s = s.replace(/\s*float2\s+uv\s*=\s*gl_FragCoord\.xy\s*\/\s*float2\s*\(\s*1920\.0\s*,\s*1080\.0\s*\)\s*;/, '');

  // Replace gl_FragCoord with pos
  s = s.replace(/\bgl_FragCoord\b/g, 'pos');

  // 10. Replace main function signature
  s = s.replace(/void\s+main\s*\(\s*\)/,
    'float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target');

  // 11. Replace fragColor assignments with return statements
  s = s.replace(/fragColor\s*=\s*/g, 'return ');

  // 12. Handle GLSL array constructors -> HLSL array initializers
  // uint[64](...) -> { ... }  (replace both opening and closing)
  s = replaceArrayConstructors(s);

  // 13. const arrays inside functions need 'static const' in HLSL
  s = s.replace(/\bconst\s+(uint|int|float)\b/g, 'static const $1');

  // 14. Clean up excessive blank lines
  while (s.includes('\n\n\n\n')) {
    s = s.replace(/\n\n\n\n/g, '\n\n');
  }

  return s.trim() + '\n';
}

/**
 * Replace single-arg floatN() constructors with HLSL cast syntax.
 * GLSL: float3(0.88) broadcasts scalar to all components.
 * HLSL: float3(0.88) is invalid (X3014) — needs ((float3)(0.88)).
 *
 * Only rewrites when the constructor has exactly one top-level argument
 * (no commas at depth 0). Safe for both scalar broadcast and identity casts.
 */
function replaceScalarBroadcastConstructors(text) {
  // Match float2( float3( float4( — but not float2x2( etc.
  const pattern = /\b(float[234])\s*\(/g;
  let result = '';
  let lastEnd = 0;
  let match;

  while ((match = pattern.exec(text)) !== null) {
    const typeName = match[1];
    const openParen = match.index + match[0].length - 1;

    // Find the matching close paren
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const closeParen = pos - 1;
    const inner = text.slice(openParen + 1, closeParen);

    // Count top-level commas
    const args = splitTopLevelArgs(inner);
    if (args.length === 1) {
      // Single arg — rewrite to cast: (float3)(expr)
      result += text.slice(lastEnd, match.index);
      result += '((' + typeName + ')(' + args[0].trim() + '))';
      lastEnd = closeParen + 1;
    }
    // Multi-arg — leave unchanged, regex continues scanning
    pattern.lastIndex = closeParen + 1;
  }

  result += text.slice(lastEnd);
  return result;
}

/**
 * Replace GLSL array constructors with HLSL initializer-list syntax.
 * e.g. uint[70]( ... ) -> { ... }
 */
function replaceArrayConstructors(text) {
  // Match patterns like: uint[70](  or  float[4](
  const pattern = /\w+\[\d+\]\s*\(/g;
  let result = '';
  let lastEnd = 0;
  let match;

  while ((match = pattern.exec(text)) !== null) {
    // Append text before this match
    result += text.slice(lastEnd, match.index);

    // Find the opening paren position
    const openParen = match.index + match[0].length - 1;

    // Find the matching close paren
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const closeParen = pos - 1;

    // Extract inner content and wrap in braces
    const inner = text.slice(openParen + 1, closeParen);
    result += '{ ' + inner + '}';

    lastEnd = closeParen + 1;
    pattern.lastIndex = lastEnd;
  }

  result += text.slice(lastEnd);
  return result;
}

/**
 * Replace clamp(expr, 0.0, 1.0) with saturate(expr) — best-effort.
 * Handles nested parentheses correctly.
 */
function replaceSaturatePattern(text) {
  const target = 'clamp(';
  let result = '';
  let i = 0;

  while (i < text.length) {
    const idx = text.indexOf(target, i);
    if (idx === -1) {
      result += text.slice(i);
      break;
    }

    // Check word boundary
    if (idx > 0 && /[\w]/.test(text[idx - 1])) {
      result += text.slice(i, idx + target.length);
      i = idx + target.length;
      continue;
    }

    result += text.slice(i, idx);

    // Find matching close paren
    const openParen = idx + target.length - 1;
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const closeParen = pos - 1;
    const inner = text.slice(openParen + 1, closeParen);

    // Split args at top level
    const args = splitTopLevelArgs(inner);
    if (args.length === 3 &&
        args[1].trim() === '0.0' &&
        args[2].trim() === '1.0') {
      result += 'saturate(' + args[0] + ')';
    } else {
      result += 'clamp(' + inner + ')';
    }

    i = closeParen + 1;
  }

  return result;
}

function splitTopLevelArgs(s) {
  const parts = [];
  let depth = 0;
  let current = '';
  for (const c of s) {
    if (c === '(') depth++;
    else if (c === ')') depth--;
    if (c === ',' && depth === 0) {
      parts.push(current);
      current = '';
      continue;
    }
    current += c;
  }
  parts.push(current);
  return parts;
}

module.exports = { convertGlslToHlsl };
