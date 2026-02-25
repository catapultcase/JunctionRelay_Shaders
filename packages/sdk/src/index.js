/**
 * @junctionrelay/shader-sdk
 * MIT License - Copyright (c) 2024-present Jonathan Mills, CatapultCase
 */

/**
 * Shader ID must be namespace.name dot-notation (e.g. "junctionrelay.rainwindow").
 * Each segment: starts with lowercase letter, then lowercase alphanumeric with optional hyphens.
 */
const SHADER_ID_PATTERN = /^[a-z][a-z0-9]*(-[a-z0-9]+)*\.[a-z][a-z0-9]*(-[a-z0-9]+)*$/;

/** Valid uniform types and their expected default value shapes. */
const UNIFORM_TYPES = {
  float: { defaultCheck: v => typeof v === 'number' },
  vec2:  { defaultCheck: v => Array.isArray(v) && v.length === 2 && v.every(n => typeof n === 'number') },
  vec3:  { defaultCheck: v => Array.isArray(v) && v.length === 3 && v.every(n => typeof n === 'number') },
  vec4:  { defaultCheck: v => Array.isArray(v) && v.length === 4 && v.every(n => typeof n === 'number') },
  color: { defaultCheck: v => Array.isArray(v) && v.length === 3 && v.every(n => typeof n === 'number' && n >= 0 && n <= 1) },
};

/**
 * Validate a shader manifest (package.json contents).
 * Returns { valid: true } or { valid: false, errors: string[] }.
 */
function validateManifest(pkg) {
  const errors = [];
  const jr = pkg.junctionrelay;

  if (!jr || jr.type !== 'shader') {
    errors.push('Missing or invalid junctionrelay.type (must be "shader")');
    return { valid: false, errors };
  }

  const shaderId = jr.shaderName || pkg.name;
  if (!SHADER_ID_PATTERN.test(shaderId)) {
    errors.push(`Invalid shaderName "${shaderId}": must be namespace.name (e.g. junctionrelay.plasma)`);
  }

  if (!Array.isArray(jr.passes) || jr.passes.length === 0) {
    errors.push('Missing or empty passes array');
  } else {
    for (const pass of jr.passes) {
      if (!pass.entry || typeof pass.entry !== 'string') {
        errors.push('Each pass must have a string "entry" field');
      }
    }
  }

  if (Array.isArray(jr.uniforms)) {
    for (const u of jr.uniforms) {
      if (!u.name || typeof u.name !== 'string') {
        errors.push('Each uniform must have a string "name" field');
        continue;
      }
      const typeInfo = UNIFORM_TYPES[u.type];
      if (!typeInfo) {
        errors.push(`Uniform "${u.name}": unknown type "${u.type}" (valid: ${Object.keys(UNIFORM_TYPES).join(', ')})`);
        continue;
      }
      if (u.default !== undefined && !typeInfo.defaultCheck(u.default)) {
        const hint = u.type === 'color'
          ? 'must be [r, g, b] floats 0-1 (not a hex string)'
          : `must match ${u.type} shape`;
        errors.push(`Uniform "${u.name}": invalid default for type "${u.type}": ${hint}`);
      }
    }
  }

  return errors.length === 0 ? { valid: true } : { valid: false, errors };
}

module.exports = { ...require('./glslToHlsl'), SHADER_ID_PATTERN, UNIFORM_TYPES, validateManifest };
