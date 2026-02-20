# @junctionrelay/shader-sdk

GLSL-to-HLSL converter and test suite for JunctionRelay shaders. Converts GLSL ES 300 fragment shaders to HLSL SM5 for the Windows DX11 texture bridge.

## Converter

```js
const { convertGlslToHlsl } = require('@junctionrelay/shader-sdk');

const hlsl = convertGlslToHlsl(glslSource);
```

Handles type replacement (`vec3` → `float3`), function renaming (`mix` → `lerp`, `fract` → `frac`), texture sampling, array constructors, scalar broadcast, and main function restructuring. No external dependencies.

## Shader Contract

GLSL shaders must follow this contract:

```glsl
#version 300 es
precision mediump float;
uniform sampler2D iChannel0;
uniform float iTime;
out vec4 fragColor;

void main() {
  // ...
  fragColor = result;
}
```

## Testing

Two scripts, one per OS:

| Script | OS | What it tests |
|--------|----|---------------|
| `scripts/test_linux.sh` | Linux | GLSL compilation (glslang WASM → SPIR-V) + structural HLSL checks |
| `scripts/test_windows.ps1` | Windows | HLSL compilation (fxc.exe → bytecode) |

```bash
# Linux
./scripts/test_linux.sh
```

```powershell
# Windows (PowerShell)
.\scripts\test_windows.ps1
```

## License

MIT
