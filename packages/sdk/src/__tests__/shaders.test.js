/**
 * @junctionrelay/shader-sdk — Shader Test Suite
 * MIT License — Copyright (c) 2024-present Jonathan Mills, CatapultCase
 *
 * Auto-discovers all shaders in ../../shaders/ and validates:
 *   A. Package metadata (package.json fields)
 *   B. GLSL compilation (glslang WASM → SPIR-V via child process)
 *   C. GLSL structural contract (Shadertoy convention)
 *   D. HLSL conversion + structural validation
 *
 * Shaders use the Shadertoy convention: void mainImage(out vec4 fragColor, in vec2 fragCoord)
 * The runtime provides iChannel0, iTime, and iResolution as uniforms.
 *
 * Note: SPIR-V compilation runs in a child process because @webgpu/glslang
 * WASM deadlocks the node:test event loop on Node 22+.
 *
 * For full HLSL compilation testing with fxc (Windows SDK), see:
 *   devops/windows-ssh-setup.md → "HLSL Compilation Validation"
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');
const os = require('os');
const { convertGlslToHlsl } = require('../glslToHlsl');

/**
 * Map manifest uniform type to GLSL type.
 */
function uniformGlslType(type) {
  if (type === 'color') return 'vec3';
  return type; // float, vec2, vec3, vec4
}

/**
 * Wrap a mainImage shader in a full GLSL program for SPIR-V compilation.
 * Optionally injects custom uniform declarations from the manifest.
 */
function wrapForSpirv(src, customUniforms = []) {
  let customBlock = '';
  if (customUniforms.length > 0) {
    const members = customUniforms.map(u =>
      `  ${uniformGlslType(u.type)} ${u.name};`
    ).join('\n');
    customBlock = `layout(std140, binding=2) uniform CustomUB {\n${members}\n};\n`;
  }

  return '#version 310 es\nprecision mediump float;\n' +
    'layout(binding=0) uniform sampler2D iChannel0;\n' +
    'layout(std140, binding=1) uniform UB { float iTime; float _pad; vec4 iResolution; };\n' +
    customBlock +
    'layout(location=0) out vec4 _fragColor;\n\n' +
    src + '\n' +
    'void main() { mainImage(_fragColor, gl_FragCoord.xy); }\n';
}

/**
 * Compile GLSL to SPIR-V in a child process (avoids WASM + node:test deadlock).
 * Writes GLSL to a temp file to avoid command-line length limits.
 * Returns { ok: true, bytes: N } or { ok: false, error: 'message' }.
 */
function compileToSpirvSync(glslSource, customUniforms = []) {
  const wrapped = wrapForSpirv(glslSource, customUniforms);
  const tmpFile = path.join(os.tmpdir(), `spirv_test_${process.pid}.glsl`);
  const scriptFile = path.join(os.tmpdir(), `spirv_test_${process.pid}.js`);
  try {
    fs.writeFileSync(tmpFile, wrapped);
    const rootDir = path.resolve(__dirname, '../../../..');
    fs.writeFileSync(scriptFile, `
      const fs = require('fs');
      const glsl = fs.readFileSync(${JSON.stringify(tmpFile)}, 'utf8');
      require(${JSON.stringify(path.join(rootDir, 'node_modules/@webgpu/glslang'))})().then(g => {
        try {
          const spirv = g.compileGLSL(glsl, 'fragment');
          process.stdout.write(JSON.stringify({ ok: true, bytes: spirv.byteLength }));
        } catch (e) {
          process.stdout.write(JSON.stringify({ ok: false, error: e.message }));
        }
        process.exit(0);
      });
    `);
    const result = execSync(`node ${JSON.stringify(scriptFile)}`, {
      cwd: path.resolve(__dirname, '../../../..'),
      timeout: 30000,
      encoding: 'utf8',
    });
    return JSON.parse(result);
  } catch (e) {
    return { ok: false, error: e.message.split('\n')[0] };
  } finally {
    try { fs.unlinkSync(tmpFile); } catch {}
    try { fs.unlinkSync(scriptFile); } catch {}
  }
}

// ---------------------------------------------------------------------------
// Discover shaders
// ---------------------------------------------------------------------------
const shadersDir = path.resolve(__dirname, '../../../../shaders');
const shaderNames = fs.readdirSync(shadersDir).filter(name => {
  const dir = path.join(shadersDir, name);
  return fs.statSync(dir).isDirectory() && fs.existsSync(path.join(dir, 'package.json'));
});

assert.ok(shaderNames.length > 0,
  'No shaders found in shaders/ directory');

const VALID_UNIFORM_TYPES = new Set(['float', 'vec2', 'vec3', 'vec4', 'color']);

for (const shaderName of shaderNames) {
  describe(`shader: ${shaderName}`, () => {
    const shaderDir = path.join(shadersDir, shaderName);
    const pkgPath = path.join(shaderDir, 'package.json');

    // Load manifest metadata once per shader for conditional tests
    const shaderPkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
    const jr = shaderPkg.junctionrelay || {};
    const usesTexture = jr.usesTexture;
    const customUniforms = jr.uniforms;

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

      it('shaderName matches namespace.name pattern', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        const pattern = /^[a-z][a-z0-9]*(-[a-z0-9]+)*\.[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
        assert.match(pkg.junctionrelay.shaderName, pattern,
          `shaderName "${pkg.junctionrelay.shaderName}" must be namespace.name (e.g. junctionrelay.rainwindow)`);
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

      it('has usesTexture boolean', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        assert.notEqual(pkg.junctionrelay?.usesTexture, undefined,
          'missing required field: usesTexture');
        assert.equal(typeof pkg.junctionrelay.usesTexture, 'boolean',
          'usesTexture must be a boolean');
      });

      it('has uniforms array', () => {
        pkg = pkg || JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
        const uniforms = pkg.junctionrelay?.uniforms;
        assert.notEqual(uniforms, undefined,
          'missing required field: uniforms');
        assert.ok(Array.isArray(uniforms), 'uniforms must be an array');
        for (const u of uniforms) {
          assert.ok(u.name, `uniform missing name`);
          assert.match(u.name, /^[a-zA-Z_]\w*$/, `invalid uniform name: ${u.name}`);
          assert.ok(u.displayName, `uniform ${u.name} missing displayName`);
          assert.ok(VALID_UNIFORM_TYPES.has(u.type),
            `uniform ${u.name} has invalid type: ${u.type}`);
          assert.notEqual(u.default, undefined,
            `uniform ${u.name} missing default`);
        }
      });
    });

    // -----------------------------------------------------------------------
    // B. GLSL — SPIR-V compilation (child process)
    // -----------------------------------------------------------------------
    describe('GLSL compilation', () => {
      it('compiles (glslang → SPIR-V)', () => {
        const glsl = loadGlsl(shaderDir, pkgPath);
        const result = compileToSpirvSync(glsl, customUniforms);
        assert.ok(result.ok, `GLSL compilation failed: ${result.error || 'unknown'}`);
        assert.ok(result.bytes > 0, 'SPIR-V output is empty');
      });
    });

    // -----------------------------------------------------------------------
    // C. GLSL — structural contract (Shadertoy convention)
    // -----------------------------------------------------------------------
    describe('GLSL structure', () => {
      let glsl;

      it('has void mainImage(out vec4 fragColor, in vec2 fragCoord)', () => {
        glsl = loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /void\s+mainImage\s*\(\s*out\s+vec4\s+fragColor\s*,\s*in\s+vec2\s+fragCoord\s*\)/);
      });

      it('assigns to fragColor', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.match(glsl, /fragColor\s*=/);
      });

      it('has no #version directive', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /#version/);
      });

      it('has no precision qualifier', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /precision\s+mediump/);
      });

      it('has no uniform declarations', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /\buniform\b/);
      });

      it('has no out vec4 declaration', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /out\s+vec4\s+fragColor\s*;/);
      });

      it('has no void main()', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /void\s+main\s*\(\s*\)/);
      });

      it('has no gl_FragCoord', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /\bgl_FragCoord\b/);
      });

      it('has no hardcoded 1920x1080 resolution', () => {
        glsl = glsl || loadGlsl(shaderDir, pkgPath);
        assert.doesNotMatch(glsl, /1920\.0/);
        assert.doesNotMatch(glsl, /1080\.0/);
      });
    });

    // -----------------------------------------------------------------------
    // D. HLSL — conversion + structural validation
    // -----------------------------------------------------------------------
    describe('HLSL', () => {
      let hlsl;

      it('converts without throwing', () => {
        const glsl = loadGlsl(shaderDir, pkgPath);
        hlsl = convertGlslToHlsl(glsl, customUniforms);
        assert.ok(hlsl.length > 0, 'HLSL output is empty');
      });

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

      it('iResolution replaced with resolution', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\biResolution\b/);
      });

      it('iChannel0 sampling replaced with tex0.Sample/SampleLevel', { skip: !usesTexture }, () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /texture\s*\(\s*iChannel0/);
        assert.doesNotMatch(hlsl, /textureLod\s*\(\s*iChannel0/);
        assert.match(hlsl, /tex0\.Sample(?:Level)?\(sampler0/);
      });

      it('custom uniforms declared in cbuffer', { skip: !customUniforms || customUniforms.length === 0 }, () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.match(hlsl, /cbuffer\s+CustomUniforms/,
          'Missing cbuffer CustomUniforms for shader with custom uniforms');
        for (const u of customUniforms) {
          assert.match(hlsl, new RegExp('\\b' + u.name + '\\b'),
            `Custom uniform ${u.name} not found in HLSL`);
        }
      });

      it('no float2 uv redefinition (uv is a main parameter)', () => {
        hlsl = hlsl || convertShader(shaderDir, pkgPath);
        assert.doesNotMatch(hlsl, /\bfloat2\s+uv\s*=/,
          'Found float2 uv declaration — should be assignment (uv =) since uv is a main() parameter');
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
  const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  const uniforms = pkg.junctionrelay?.uniforms;
  return convertGlslToHlsl(loadGlsl(shaderDir, pkgPath), uniforms);
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
