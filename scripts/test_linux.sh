#!/usr/bin/env bash
# test_linux.sh — GLSL compilation + structural HLSL validation (Linux only)
set -euo pipefail
cd "$(dirname "$0")/.."
npm test
