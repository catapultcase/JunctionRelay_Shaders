/**
 * @junctionrelay/shader-sdk
 * MIT License — Copyright (c) 2024-present Jonathan Mills, CatapultCase
 */

/**
 * Shader ID must be namespace.name dot-notation (e.g. "junctionrelay.rainwindow").
 * Each segment: starts with lowercase letter, then lowercase alphanumeric with optional hyphens.
 */
const SHADER_ID_PATTERN = /^[a-z][a-z0-9]*(-[a-z0-9]+)*\.[a-z][a-z0-9]*(-[a-z0-9]+)*$/;

module.exports = { ...require('./glslToHlsl'), SHADER_ID_PATTERN };
