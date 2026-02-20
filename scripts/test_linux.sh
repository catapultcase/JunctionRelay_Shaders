#!/usr/bin/env bash
# @junctionrelay/shader-sdk — Linux Test Script
#
# Validates all shaders in shaders/:
#   A. Package metadata (package.json fields)
#   B. GLSL compilation (glslang WASM → SPIR-V)
#   C. HLSL conversion + structural validation
#
# Usage:
#   ./scripts/test_linux.sh
#
# For HLSL compilation testing with fxc, run test_windows.sh on Windows.
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
