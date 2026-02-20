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
  s = s.replace(/\bivec4\b/g, 'int4');
  s = s.replace(/\bivec3\b/g, 'int3');
  s = s.replace(/\bivec2\b/g, 'int2');
  s = s.replace(/\buvec4\b/g, 'uint4');
  s = s.replace(/\buvec3\b/g, 'uint3');
  s = s.replace(/\buvec2\b/g, 'uint2');
  s = s.replace(/\bbvec4\b/g, 'bool4');
  s = s.replace(/\bbvec3\b/g, 'bool3');
  s = s.replace(/\bbvec2\b/g, 'bool2');
  s = s.replace(/\bvec4\b/g, 'float4');
  s = s.replace(/\bvec3\b/g, 'float3');
  s = s.replace(/\bvec2\b/g, 'float2');

  // 4b. GLSL mat * vec uses overloaded * for matrix multiply; HLSL requires mul().
  // Find all floatNxN variable names and rewrite: var * expr → mul(var, expr)
  s = replaceMatrixMultiply(s);

  // 4c. GLSL vec3(scalar) broadcasts to all components; HLSL float3(scalar) is invalid.
  // Convert single-arg floatN constructors to HLSL cast syntax: (floatN)(expr)
  s = replaceScalarBroadcastConstructors(s);

  // 5. Replace function names
  s = s.replace(/\bmix\b/g, 'lerp');
  s = s.replace(/\bfract\b/g, 'frac');
  s = s.replace(/\bmod\b/g, 'fmod');
  s = s.replace(/\binversesqrt\b/g, 'rsqrt');
  s = s.replace(/\bdFdx\b/g, 'ddx');
  s = s.replace(/\bdFdy\b/g, 'ddy');
  // atan: GLSL atan(x) = HLSL atan(x), GLSL atan(y,x) = HLSL atan2(y,x)
  // Only replace two-arg atan calls
  s = replaceAtanCalls(s);

  // 6. Replace iTime -> time
  s = s.replace(/\biTime\b/g, 'time');

  // 7. Replace texture sampling
  s = s.replace(/textureLod\s*\(\s*iChannel0\s*,/g, 'tex0.SampleLevel(sampler0,');
  s = s.replace(/texture\s*\(\s*iChannel0\s*,/g, 'tex0.Sample(sampler0,');

  // 8. Replace clamp(x, 0.0, 1.0) with saturate(x) for common patterns
  s = replaceSaturatePattern(s);

  // 9. Replace gl_FragCoord with pos in main body, and restructure main
  // Strip any uv = gl_FragCoord derivation line (uv is provided as a parameter)
  s = s.replace(/\s*float2\s+uv\s*=\s*gl_FragCoord\.xy\s*\/[^;]+;/, '');

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
 * Replace GLSL atan(y, x) with HLSL atan2(y, x).
 * Leave single-arg atan(x) unchanged (valid in both languages).
 */
function replaceAtanCalls(text) {
  const pattern = /\batan\s*\(/g;
  let result = '';
  let lastEnd = 0;
  let match;

  while ((match = pattern.exec(text)) !== null) {
    const openParen = match.index + match[0].length - 1;
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const inner = text.slice(openParen + 1, pos - 1);
    const args = splitTopLevelArgs(inner);

    result += text.slice(lastEnd, match.index);
    if (args.length >= 2) {
      result += 'atan2(' + inner + ')';
    } else {
      result += 'atan(' + inner + ')';
    }
    lastEnd = pos;
    pattern.lastIndex = pos;
  }

  result += text.slice(lastEnd);
  return result;
}

/**
 * Replace GLSL matrix * vector multiplication with HLSL mul().
 * GLSL: mat2 r = ...; p = r * p;
 * HLSL: float2x2 r = ...; p = mul(r, p);
 */
function replaceMatrixMultiply(text) {
  const matVars = new Set();
  const declPattern = /\bfloat[234]x[234]\s+(\w+)/g;
  let m;
  while ((m = declPattern.exec(text)) !== null) {
    matVars.add(m[1]);
  }
  for (const name of matVars) {
    // mat * expr → mul(mat, expr)
    const lhs = new RegExp('\\b(' + name + ')\\s*\\*\\s*(\\w+)', 'g');
    text = text.replace(lhs, 'mul($1, $2)');
    // expr * mat → mul(expr, mat)
    const rhs = new RegExp('(\\w+)\\s*\\*\\s*(' + name + ')\\b', 'g');
    text = text.replace(rhs, 'mul($1, $2)');
  }
  return text;
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
