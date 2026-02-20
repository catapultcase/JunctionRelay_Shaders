# JunctionRelay Shaders

GLSL ES 300 fragment shaders for JunctionRelay. Shaders run in WebGL2 (browser preview) and are auto-converted to HLSL SM5 for the Windows DX11 texture bridge.

Authors write standard GLSL. The converter handles the HLSL translation — you never touch HLSL.

## Creating a Shader

Each shader is a directory in `shaders/` with two files:

```
shaders/my-shader/
  package.json
  shader.glsl
```

**package.json:**
```json
{
  "name": "@junctionrelay/shader-my-shader",
  "version": "1.0.0",
  "description": "Short description of the effect",
  "junctionrelay": {
    "type": "shader",
    "shaderName": "my-shader",
    "displayName": "My Shader",
    "description": "Longer description of the effect",
    "entry": "shader.glsl"
  }
}
```

**shader.glsl** — must start with this exact header:
```glsl
#version 300 es
precision mediump float;

uniform sampler2D iChannel0;  // input texture (screen capture)
uniform float iTime;          // elapsed time in seconds
out vec4 fragColor;           // output color

void main() {
  vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
  vec4 color = texture(iChannel0, uv);

  // your effect here

  fragColor = color;
}
```

## Supported GLSL

Your shader is auto-converted to HLSL. Use these GLSL features freely — they all convert correctly:

**Types:**
`float`, `int`, `uint`, `bool`, `vec2/3/4`, `ivec2/3/4`, `uvec2/3/4`, `bvec2/3/4`, `mat2/3/4`

**Functions:**
`mix`, `fract`, `mod`, `atan` (1 or 2 args), `inversesqrt`, `dFdx`, `dFdy`, `clamp`, `smoothstep`, `step`, `pow`, `sin`, `cos`, `tan`, `exp`, `log`, `sqrt`, `abs`, `sign`, `floor`, `ceil`, `round`, `min`, `max`, `dot`, `cross`, `normalize`, `length`, `distance`, `reflect`, `refract`

**Texture sampling:**
`texture(iChannel0, uv)`, `textureLod(iChannel0, uv, lod)`

**Matrix math:**
`mat2 * vec2`, `vec2 * mat2` (auto-converted to `mul()`)

**Other:**
`const` arrays, `#define` macros, helper functions, `for`/`while` loops, ternary `? :`, swizzles (`.xyz`, `.rg`, etc.)

## What to Avoid

These GLSL features do NOT convert and will break on Windows:

- `texelFetch`, `textureGrad`, `textureSize` — only `texture()` and `textureLod()` are supported
- `lessThan`, `greaterThan`, `equal`, `notEqual` — use component-wise comparison operators instead
- `matrixCompMult` — use component-wise multiply manually
- `struct` uniforms — only `iChannel0` and `iTime` are available
- Multiple `out` variables — only `fragColor` is supported
- `#include` or multi-file shaders — everything must be in one file

## Testing

Two scripts, one per OS:

| Script | OS | What it tests |
|--------|----|---------------|
| `scripts/test_linux.sh` | Linux | GLSL compilation (glslang WASM) + structural HLSL checks |
| `scripts/test_windows.ps1` | Windows | HLSL compilation (fxc.exe) |

```bash
# Linux
./scripts/test_linux.sh
```

```powershell
# Windows (PowerShell)
.\scripts\test_windows.ps1
```

Both must pass. If your shader compiles in the browser preview but fails the Windows test, you're using an unsupported GLSL feature — check the "What to Avoid" list above.

## License

MIT
