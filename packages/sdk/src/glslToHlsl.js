/**
 * @junctionrelay/shader-sdk
 * MIT License — Copyright (c) 2024-present Jonathan Mills, CatapultCase
 *
 * GLSL -> HLSL On-Demand Converter
 *
 * Converts Shadertoy-convention GLSL fragment shaders to HLSL for the
 * Windows DX11 texture bridge sidecar. Shaders use the mainImage entry point:
 *
 *   GLSL: void mainImage(out vec4 fragColor, in vec2 fragCoord)
 *   HLSL: float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
 *
 * The runtime provides iChannel0, iTime, and iResolution — shaders contain
 * only effect code. Any Shadertoy shader works with copy-paste.
 *
 * No external dependencies — pure string manipulation.
 */

/**
 * Convert a Shadertoy-convention GLSL fragment shader to HLSL (SM5).
 * @param {string} glslSource - The GLSL shader source (mainImage format)
 * @returns {string} HLSL shader source
 */
function convertGlslToHlsl(glslSource) {
  let s = glslSource;

  // 1. Prepend HLSL header (mainImage shaders have no declarations)
  s = 'Texture2D tex0 : register(t0);\n' +
      'SamplerState sampler0 : register(s0);\n' +
      'cbuffer TimeBuffer : register(b0) { float time; float _pad; float2 resolution; };\n\n' +
      s;

  // 2. Replace types (longer patterns first)
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

  // 2b. GLSL mat * vec → HLSL mul()
  s = replaceMatrixMultiply(s);

  // 2c. GLSL vec3(scalar) → HLSL cast syntax ((float3)(scalar))
  s = replaceScalarBroadcastConstructors(s);

  // 3. Replace function names
  s = s.replace(/\bmix\b/g, 'lerp');
  s = s.replace(/\bfract\b/g, 'frac');
  s = s.replace(/\bmod\b/g, 'fmod');
  s = s.replace(/\binversesqrt\b/g, 'rsqrt');
  s = s.replace(/\bdFdx\b/g, 'ddx');
  s = s.replace(/\bdFdy\b/g, 'ddy');
  s = replaceAtanCalls(s);

  // 4. Replace uniform names
  s = s.replace(/\biResolution\b/g, 'resolution');
  s = s.replace(/\biTime\b/g, 'time');

  // 5. Replace texture sampling
  s = s.replace(/textureLod\s*\(\s*iChannel0\s*,/g, 'tex0.SampleLevel(sampler0,');
  s = s.replace(/texture\s*\(\s*iChannel0\s*,/g, 'tex0.Sample(sampler0,');

  // 6. Replace clamp(x, 0.0, 1.0) with saturate(x)
  s = replaceSaturatePattern(s);

  // 7. Strip uv = fragCoord / resolution derivation (UV provided as TEXCOORD0)
  s = s.replace(/\s*float2\s+uv\s*=\s*fragCoord(?:\.xy)?\s*\/\s*resolution\.xy\s*;/, '');

  // 8. Convert mainImage signature to HLSL main
  s = s.replace(
    /void\s+mainImage\s*\(\s*out\s+float4\s+fragColor\s*,\s*in\s+float2\s+fragCoord\s*\)/,
    'float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target');

  // 8b. Add Y-flip and fragCoord alias after opening brace of main
  s = s.replace(
    /float4 main\(float4 pos : SV_Position, float2 uv : TEXCOORD0\) : SV_Target\s*\{/,
    'float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target\n{\n  pos.y = resolution.y - pos.y;\n  float2 fragCoord = pos.xy;');

  // 9. Replace fragColor assignments with return statements
  s = s.replace(/fragColor\s*=\s*/g, 'return ');

  // 10. Handle GLSL array constructors → HLSL initializer lists
  s = replaceArrayConstructors(s);

  // 11. const arrays inside functions need 'static const' in HLSL
  s = s.replace(/\bconst\s+(uint|int|float)\b/g, 'static const $1');

  // 12. Clean up excessive blank lines
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
 */
function replaceMatrixMultiply(text) {
  const matVars = new Set();
  const declPattern = /\bfloat[234]x[234]\s+(\w+)/g;
  let m;
  while ((m = declPattern.exec(text)) !== null) {
    matVars.add(m[1]);
  }
  for (const name of matVars) {
    const lhs = new RegExp('\\b(' + name + ')\\s*\\*\\s*(\\w+)', 'g');
    text = text.replace(lhs, 'mul($1, $2)');
    const rhs = new RegExp('(\\w+)\\s*\\*\\s*(' + name + ')\\b', 'g');
    text = text.replace(rhs, 'mul($1, $2)');
  }
  return text;
}

/**
 * Replace single-arg floatN() constructors with HLSL cast syntax.
 * GLSL: float3(0.88) → HLSL: ((float3)(0.88))
 */
function replaceScalarBroadcastConstructors(text) {
  const pattern = /\b(float[234])\s*\(/g;
  let result = '';
  let lastEnd = 0;
  let match;

  while ((match = pattern.exec(text)) !== null) {
    const typeName = match[1];
    const openParen = match.index + match[0].length - 1;

    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const closeParen = pos - 1;
    const inner = text.slice(openParen + 1, closeParen);

    const args = splitTopLevelArgs(inner);
    if (args.length === 1) {
      result += text.slice(lastEnd, match.index);
      result += '((' + typeName + ')(' + args[0].trim() + '))';
      lastEnd = closeParen + 1;
    }
    pattern.lastIndex = closeParen + 1;
  }

  result += text.slice(lastEnd);
  return result;
}

/**
 * Replace GLSL array constructors with HLSL initializer-list syntax.
 * e.g. uint[70]( ... ) → { ... }
 */
function replaceArrayConstructors(text) {
  const pattern = /\w+\[\d+\]\s*\(/g;
  let result = '';
  let lastEnd = 0;
  let match;

  while ((match = pattern.exec(text)) !== null) {
    result += text.slice(lastEnd, match.index);

    const openParen = match.index + match[0].length - 1;
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < text.length) {
      if (text[pos] === '(') depth++;
      else if (text[pos] === ')') depth--;
      pos++;
    }
    const closeParen = pos - 1;
    const inner = text.slice(openParen + 1, closeParen);
    result += '{ ' + inner + '}';

    lastEnd = closeParen + 1;
    pattern.lastIndex = lastEnd;
  }

  result += text.slice(lastEnd);
  return result;
}

/**
 * Replace clamp(expr, 0.0, 1.0) with saturate(expr).
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

    if (idx > 0 && /[\w]/.test(text[idx - 1])) {
      result += text.slice(i, idx + target.length);
      i = idx + target.length;
      continue;
    }

    result += text.slice(i, idx);

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
