# JunctionRelay Shaders

GPU pixel shader plugins for JunctionRelay XSD. Shaders use the **Shadertoy convention** — any Shadertoy shader works with copy-paste. The `@junctionrelay/shader-sdk` auto-converts GLSL to HLSL SM5 for the Windows DX11 texture bridge.

Authors write standard GLSL effect code. The runtime provides uniforms (`iChannel0`, `iTime`, `iResolution`). The converter handles HLSL translation — you never touch HLSL.

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

**shader.glsl** — Shadertoy convention (effect code only, no boilerplate):
```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  vec4 color = texture(iChannel0, uv);

  // your effect here

  fragColor = color;
}
```

### Available Uniforms (provided by the runtime)

| Uniform | Type | Description |
|---------|------|-------------|
| `iChannel0` | `sampler2D` | Input texture (screen capture) |
| `iTime` | `float` | Elapsed time in seconds |
| `iResolution` | `vec3` | Viewport resolution (`iResolution.xy` for width/height) |

### Rules

- Entry point must be `void mainImage(out vec4 fragColor, in vec2 fragCoord)`
- Use `fragCoord` for pixel coordinates (not `gl_FragCoord`)
- Use `iResolution.xy` for resolution (never hardcode pixel dimensions)
- No `#version`, `precision`, `uniform`, or `out` declarations — the runtime adds these
- No `void main()` — the runtime wraps `mainImage` with the platform entry point
- Output to `fragColor` (the `out` parameter)

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
- `struct` uniforms — only `iChannel0`, `iTime`, and `iResolution` are available
- Multiple `out` variables — only `fragColor` is supported
- `#include` or multi-file shaders — everything must be in one file
- `discard` statements
- Geometry or vertex shader features

## Testing

Two scripts, one per OS:

| Script | OS | What it tests |
|--------|----|---------------|
| `scripts/test_linux.sh` | Linux | GLSL compilation (glslang WASM → SPIR-V) + structural HLSL checks |
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
