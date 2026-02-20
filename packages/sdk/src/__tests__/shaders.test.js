/**
 * @junctionrelay/shader-sdk — Shader Test Suite
 * MIT License — Copyright (c) 2024-present Jonathan Mills, CatapultCase
 *
 * Auto-discovers all shaders in ../../shaders/ and validates:
 *   A. Package metadata (package.json fields)
 *   B. GLSL compilation (glslang WASM → SPIR-V) + structural contract
 *   C. HLSL conversion + structural validation
 *
 * For full HLSL compilation testing with fxc (Windows SDK), see:
 *   devops/windows-ssh-setup.md → "HLSL Compilation Validation"
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const fs = require('fs');
const { convertGlslToHlsl } = require('../glslToHlsl');

// ---------------------------------------------------------------------------
// GLSL compiler (glslang WASM → SPIR-V) — lazy init
// ---------------------------------------------------------------------------
let glslang = null;
let glslangReady = null;

function getGlslang() {
  if (!glslangReady) {
    glslangReady = require('@webgpu/glslang')().then(g => { glslang = g; });
  }
  return glslangReady;
}

/**
 * Adapt GLSL ES 300 source for SPIR-V compilation.
 * The shader logic, types, and functions are validated — only the
 * header/binding qualifiers change for the Vulkan SPIR-V target.
 */
function adaptForSpirv(src) {
  return src
    .replace('#version 300 es', '#version 310 es')
    .replace('uniform sampler2D iChannel0;',
      'layout(binding=0) uniform sampler2D iChannel0;')
    .replace('uniform float iTime;',
      'layout(std140, binding=1) uniform TimeBlock { float iTime; };')
    .replace('out vec4 fragColor;',
      'layout(location=0) out vec4 fragColor;');
}

// ---------------------------------------------------------------------------
// Discover shaders
// ---------------------------------------------------------------------------
const shadersDir = path.resolve(__dirname, '../../../../shaders');
const shaderNames = fs.readdirSync(shadersDir).filter(name => {
  const dir = path.join(shadersDir, name);
  return fs.statSync(dir).isDirectory() && fs.existsSync(path.join(dir, 'package.json'));
});

assert.ok(shaderNames.length >= 20,
  `Expected at least 20 shaders, found ${shaderNames.length}`);

for (const shaderName of shaderNames) {
  describe(`shader: ${shaderName}`, () => {
    const shaderDir = path.join(shadersDir, shaderName);
    const pkgPath = path.join(shaderDir, 'package.json');

    // -----------------------------------------------------------------------
    // A. Package validation
    // -----------------------------------------------------------------------
    describe('package.json', () => {
      let pkg;

      it('parses as valid JSON', () => {
        pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      });

      it('has junctionrelay.type = "shader"', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        assert.equal(pkg.junctionrelay?.type, 'shader');
      });

      it('has shaderName', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        assert.ok(pkg.junctionrelay?.shaderName, 'missing shaderName');
      });

      it('has displayName', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        assert.ok(pkg.junctionrelay?.displayName, 'missing displayName');
      });

      it('has entry field', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        assert.ok(pkg.junctionrelay?.entry, 'missing entry');
      });

      it('entry file exists on disk', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        const entryPath = path.join(shaderDir, pkg.junctionrelay.entry);
        assert.ok(fs.existsSync(entryPath), `entry file not found: ${entryPath}`);
      });
    });

    // -----------------------------------------------------------------------
    // B. GLSL — compilation + structural contract
    // -----------------------------------------------------------------------
    describe('GLSL', () => {
      let glsl;

      it('compiles (glslang → SPIR-V)', async () => {
        await getGlslang();
        glsl = loadGlsl(shaderDir, pkgPath);
        const adapted = adaptForSpirv(glsl);
        let spirv;
        try {
          spirv = glslang.compileGLSL(adapted, 'fragment');
        } catch (e) {
          assert.fail(`GLSL compilation failed:\n${e.message}`);
        }
        assert.ok(spirv.byteLength > 0, 'SPIR-V output is empty');
      });

      it('has #version 300 es', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /#version\s+300\s+es/);
      });

      it('has precision mediump float', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /precision\s+mediump\s+float/);
      });

      it('has uniform sampler2D iChannel0', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /uniform\s+sampler2D\s+iChannel0\s*;/);
      });

      it('has uniform float iTime', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /uniform\s+float\s+iTime\s*;/);
      });

      it('has out vec4 fragColor', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /out\s+vec4\s+fragColor\s*;/);
      });

      it('has void main()', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /void\s+main\s*\(\s*\)/);
      });

      it('assigns to fragColor', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /fragColor\s*=/);
      });
    });

    // -----------------------------------------------------------------------
    // C. HLSL — conversion + compilation + structural validation
    // -----------------------------------------------------------------------
    describe('HLSL', () => {
      let hlsl;

      it('converts without throwing', () => {
        const glsl = loadGlsl(shaderDir, pkgPath);
        hlsl = convertGlslToHlsl(glsl);
        assert.ok(hlsl.length > 0, 'HLSL output is empty');
      });

      // -- Expected HLSL constructs --

      it('has Texture2D tex0', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /Texture2D\s+tex0/);
      });

      it('has SamplerState sampler0', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /SamplerState\s+sampler0/);
      });

      it('has cbuffer TimeBuffer', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /cbuffer\s+TimeBuffer/);
      });

      it('has float4 main(float4 pos : SV_Position', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /float4\s+main\s*\(\s*float4\s+pos\s*:\s*SV_Position/);
      });

      it('main body has return statement', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /\breturn\s+/);
      });

      // -- No leftover GLSL --

      it('no vec2/vec3/vec4 types', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bvec[234]\b/);
      });

      it('no fract( calls', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bfract\s*\(/);
      });

      it('no mix( calls', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bmix\s*\(/);
      });

      it('no gl_FragCoord', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bgl_FragCoord\b/);
      });

      it('no fragColor', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bfragColor\b/);
      });

      it('no #version directive', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /#version/);
      });

      it('no precision mediump', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /precision\s+mediump/);
      });

      it('iTime replaced with time', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\biTime\b/);
        assert.match(hlsl, /\btime\b/);
      });

      it('texture(iChannel0 replaced with tex0.Sample(sampler0', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /texture\s*\(\s*iChannel0/);
        assert.match(hlsl, /tex0\.Sample\(sampler0/);
      });

      it('const arrays use static const', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        const constArrays = hlsl.match(/(?<!static\s)\bconst\s+(uint|int|float)\b/g);
        assert.equal(constArrays, null,
          `Found non-static const arrays: ${constArrays}`);
      });

      it('no GLSL array constructors', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\w+\[\d+\]\s*\(/,
          'Found GLSL-style array constructor');
      });

      // -- HLSL type-safety: catch fxc X3014 errors --

      it('no single-arg floatN constructors (X3014)', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        const matches = findSingleArgFloatConstructors(hlsl);
        assert.equal(matches.length, 0,
          `Invalid single-arg float constructors (fxc X3014):\n${matches.join('\n')}`);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function loadGlsl(shaderDir, pkgPath) {
  const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  const entryPath = path.join(shaderDir, pkg.junctionrelay.entry);
  return fs.readFileSync(entryPath, 'utf8');
}

function convertShader(shaderDir, pkgPath) {
  return convertGlslToHlsl(loadGlsl(shaderDir, pkgPath));
}

/**
 * Find float2/3/4(single_arg) patterns in HLSL that fxc rejects with X3014.
 * Ignores cast syntax ((float3)(x)) since that's valid HLSL.
 */
function findSingleArgFloatConstructors(hlsl) {
  const pattern = /\bfloat([234])\s*\(/g;
  const results = [];
  let match;

  while ((match = pattern.exec(hlsl)) !== null) {
    // Skip cast syntax: preceded by ( — e.g. ((float3)(x))
    if (match.index > 0 && hlsl[match.index - 1] === '(') {
      continue;
    }

    const openParen = match.index + match[0].length - 1;
    let depth = 1;
    let pos = openParen + 1;
    while (depth > 0 && pos < hlsl.length) {
      if (hlsl[pos] === '(') depth++;
      else if (hlsl[pos] === ')') depth--;
      pos++;
    }
    const inner = hlsl.slice(openParen + 1, pos - 1);

    // Count top-level commas
    let commaDepth = 0;
    let commas = 0;
    for (const c of inner) {
      if (c === '(') commaDepth++;
      else if (c === ')') commaDepth--;
      else if (c === ',' && commaDepth === 0) commas++;
    }

    const dim = parseInt(match[1]);
    if (commas === 0 && dim > 1) {
      const lineNum = hlsl.slice(0, match.index).split('\n').length;
      results.push(`  line ${lineNum}: float${dim}(${inner.trim()})`);
    }

    pattern.lastIndex = pos;
  }

  return results;
}
