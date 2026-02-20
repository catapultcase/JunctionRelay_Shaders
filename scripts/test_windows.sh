#!/usr/bin/env bash
# test_windows.sh — HLSL compilation with fxc (Windows only)
set -euo pipefail
cd "$(dirname "$0")/.."

FXC=$(cmd.exe /c "where /r \"C:\Program Files (x86)\Windows Kits\10\bin\" fxc.exe" 2>/dev/null | grep x64 | head -1 | tr -d '\r')
if [ -z "$FXC" ]; then echo "fxc.exe not found. Install Windows SDK."; exit 1; fi

echo "Using: $FXC"
echo ""

PASS=0
FAIL=0
TEMP_DIR=$(mktemp -d)

for shader_dir in shaders/*/; do
  [ -f "$shader_dir/package.json" ] || continue
  ENTRY=$(node -e "const p=require('./${shader_dir}package.json');console.log(p.junctionrelay?.entry||'')")
  [ -z "$ENTRY" ] || [ ! -f "$shader_dir$ENTRY" ] && continue

  NAME=$(basename "$shader_dir")
  HLSL="$TEMP_DIR/${NAME}.hlsl"

  node -e "
    const fs=require('fs');
    const{convertGlslToHlsl}=require('./packages/sdk/src/glslToHlsl');
    fs.writeFileSync('${HLSL}',convertGlslToHlsl(fs.readFileSync('${shader_dir}${ENTRY}','utf8')));
  "

  if "$FXC" /nologo /T ps_5_0 /E main "$HLSL" /Fo NUL 2>"$TEMP_DIR/${NAME}.err"; then
    echo "  PASS  $NAME"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $NAME"
    cat "$TEMP_DIR/${NAME}.err" | sed 's/^/        /'
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ $FAIL -gt 0 ] && echo "HLSL files: $TEMP_DIR" && exit 1
rm -rf "$TEMP_DIR"
