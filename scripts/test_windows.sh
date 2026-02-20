#!/usr/bin/env bash
# @junctionrelay/shader-sdk — Windows Test Script
#
# Converts all GLSL shaders to HLSL and compiles each with fxc.exe to catch
# type errors (X3014, X3020, etc.) that structural tests can't detect.
#
# REQUIREMENTS:
#   - Windows 10/11 with Windows SDK installed
#   - Node.js (for the GLSL→HLSL converter)
#   - fxc.exe from Windows SDK (auto-detected below)
#
# Usage (from PowerShell on Windows):
#   bash scripts/test_windows.sh
#
# For GLSL compilation testing with glslang WASM, run test_linux.sh on Linux.

set -euo pipefail
cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------------
# Find fxc.exe
# ---------------------------------------------------------------------------
FXC=""

# Check PATH first
if command -v fxc.exe &>/dev/null; then
  FXC="fxc.exe"
fi

# Search Windows SDK paths (cmd.exe where command handles spaces reliably)
if [ -z "$FXC" ]; then
  FXC=$(cmd.exe /c "where /r \"C:\Program Files (x86)\Windows Kits\10\bin\" fxc.exe" 2>/dev/null | grep x64 | head -1 | tr -d '\r')
fi

if [ -z "$FXC" ]; then
  echo "ERROR: fxc.exe not found."
  echo ""
  echo "This script requires the Windows SDK. Install it via:"
  echo "  winget install Microsoft.VisualStudio.2022.BuildTools"
  echo "  (select 'Desktop development with C++' workload)"
  echo ""
  echo "Or install the standalone Windows SDK:"
  echo "  https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
  exit 1
fi

echo "=== HLSL Compilation Validation (fxc) ==="
echo "Using: $FXC"
echo ""

# ---------------------------------------------------------------------------
# Convert + compile each shader
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
FAILED_SHADERS=""
TEMP_DIR=$(mktemp -d)

for shader_dir in shaders/*/; do
  [ -f "$shader_dir/package.json" ] || continue

  # Read entry file from package.json
  ENTRY=$(node -e "
    const pkg = require('./${shader_dir}package.json');
    console.log(pkg.junctionrelay?.entry || '');
  ")

  if [ -z "$ENTRY" ] || [ ! -f "$shader_dir$ENTRY" ]; then
    continue
  fi

  SHADER_NAME=$(basename "$shader_dir")
  HLSL_FILE="$TEMP_DIR/${SHADER_NAME}.hlsl"

  # Convert GLSL → HLSL using the SDK converter
  node -e "
    const fs = require('fs');
    const { convertGlslToHlsl } = require('./packages/sdk/src/glslToHlsl');
    const glsl = fs.readFileSync('${shader_dir}${ENTRY}', 'utf8');
    const hlsl = convertGlslToHlsl(glsl);
    fs.writeFileSync('${HLSL_FILE}', hlsl);
  "

  # Compile with fxc (discard bytecode output with NUL on Windows)
  if "$FXC" /nologo /T ps_5_0 /E main "$HLSL_FILE" /Fo NUL 2>"$TEMP_DIR/${SHADER_NAME}.err"; then
    echo "  PASS  $SHADER_NAME"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $SHADER_NAME"
    cat "$TEMP_DIR/${SHADER_NAME}.err" | sed 's/^/        /'
    FAIL=$((FAIL + 1))
    FAILED_SHADERS="$FAILED_SHADERS  - $SHADER_NAME\n"
  fi
done

echo ""
echo "--- Results ---"
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Failed shaders:"
  echo -e "$FAILED_SHADERS"
  echo "HLSL files preserved in: $TEMP_DIR"
  exit 1
else
  rm -rf "$TEMP_DIR"
  echo "All shaders compile successfully."
fi
