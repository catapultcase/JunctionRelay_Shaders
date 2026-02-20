#!/usr/bin/env bash
# @junctionrelay/shader-sdk — Run shader test suite
#
# Validates all shaders in shaders/:
#   A. Package metadata (package.json fields)
#   B. GLSL compilation (glslang WASM → SPIR-V)
#   C. HLSL conversion + structural validation
#
# Usage:
#   ./scripts/test.sh
#
# Prerequisites:
#   npm install (from repo root — pulls @webgpu/glslang for GLSL compilation)

set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Shader SDK Test Suite ==="
echo ""

# Ensure dependencies are installed
if [ ! -d "node_modules/@webgpu/glslang" ]; then
  echo "Installing dependencies..."
  npm install
  echo ""
fi

npm test
