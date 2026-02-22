# JunctionRelay Shaders

GPU pixel shader plugins for JunctionRelay XSD. Shaders use the **Shadertoy convention** — any Shadertoy shader works with copy-paste. The `@junctionrelay/shader-sdk` auto-converts GLSL to HLSL SM5 for the Windows DX11 texture bridge.

Authors write standard GLSL effect code. The runtime provides uniforms (`iChannel0`, `iChannel1`, `iTime`, `iResolution`, `iFrame`). The converter handles HLSL translation — you never touch HLSL.

## Architecture

Every shader uses the **multi-pass pipeline**, even single-pass effects. Each pass is an independent GLSL file compiled to its own pixel shader. Passes execute in order — the output of pass N becomes the input (`iChannel0`) of pass N+1. The final pass renders to screen.

Shaders that set `feedback: true` get access to `iChannel1` — a texture containing the **previous frame's final output**. This enables temporal effects like motion trails, persistence, and accumulation.

```
Pass 0               Pass 1              Screen
┌──────────┐        ┌──────────┐        ┌──────────┐
│ rain.glsl │──────▶│bloom.glsl │──────▶│  output   │
│           │       │           │       │           │
│ iChannel0 │       │ iChannel0 │       └──────────┘
│ = capture │       │ = pass 0  │
│ iChannel1 │       │ iChannel1 │──────┐
│ = prev    │       │ = prev    │      │
│   frame   │       │   frame   │      │ feedback
└──────────┘        └──────────┘      │ (copy final
                                       │  output to
                                       │  iChannel1)
                                       ▼
                                   next frame
```

## Creating a Shader

Each shader is a directory under `shaders/` named `junctionrelay.<effect-name>`:

```
shaders/junctionrelay.my-effect/
  package.json
  my-effect.glsl
```

Name the GLSL file after the effect — `crt.glsl`, `vhs.glsl`, `bloom.glsl` — not `shader.glsl`.

### Single-Pass Shader (most common)

**package.json:**
```json
{
  "name": "@junctionrelay/shader-my-effect",
  "version": "1.0.0",
  "junctionrelay": {
    "type": "shader",
    "shaderName": "junctionrelay.my-effect",
    "displayName": "My Effect",
    "description": "What the effect does",
    "feedback": false,
    "opaque": true,
    "passes": [
      { "entry": "my-effect.glsl" }
    ],
    "usesTexture": true,
    "uniforms": []
  }
}
```

**my-effect.glsl:**
```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  vec4 color = texture(iChannel0, uv);

  // your effect here

  fragColor = color;
}
```

### Multi-Pass Shader

Multiple passes with ordered execution. Each pass is a separate GLSL file.

**package.json:**
```json
{
  "name": "@junctionrelay/shader-rain-window",
  "version": "3.0.0",
  "junctionrelay": {
    "type": "shader",
    "shaderName": "junctionrelay.rain-window",
    "displayName": "Rain Window",
    "description": "Rainy window with bloom",
    "feedback": true,
    "opaque": true,
    "passes": [
      { "entry": "rain.glsl" },
      { "entry": "bloom.glsl" }
    ],
    "usesTexture": true,
    "uniforms": []
  }
}
```

Pass 0 (`rain.glsl`) receives the captured screen on `iChannel0`. Pass 1 (`bloom.glsl`) receives pass 0's output on `iChannel0`. Both passes can read the previous frame's final output from `iChannel1` when `feedback` is `true`.

### Manifest Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `shaderName` | `string` | Yes | Unique ID in `namespace.name` dot-notation (e.g. `junctionrelay.crt`). Must match `SHADER_ID_PATTERN`: each segment starts with a lowercase letter, then lowercase alphanumeric with optional hyphens. Bundled shaders use the `junctionrelay` namespace; third-party authors use their own. |
| `feedback` | `boolean` | Yes | `true` = previous frame output available on `iChannel1`. `false` = no feedback texture. |
| `opaque` | `boolean` | Yes | `true` = pipeline forces alpha=1.0 on the final output (solid display). `false` = shader's output alpha passes through to the Presenter for desktop transparency. |
| `passes` | `array` | Yes | Ordered array of `{ "entry": "<file>.glsl" }` objects. Every shader uses this — even single-pass effects. |
| `usesTexture` | `boolean` | Yes | `true` = postprocessing shader (reads `iChannel0`), `false` = generative shader (no texture input). |
| `uniforms` | `array` | Yes | Custom uniforms exposed to the UI (see [Custom Uniforms](#custom-uniforms)). |

### Available Uniforms (provided by the runtime)

| Uniform | Type | Description |
|---------|------|-------------|
| `iChannel0` | `sampler2D` | Pass input — screen capture (pass 0) or previous pass output (pass 1+) |
| `iChannel1` | `sampler2D` | Previous frame's final output (only when `feedback: true`) |
| `iTime` | `float` | Elapsed time in seconds |
| `iResolution` | `vec3` | Viewport resolution (`iResolution.xy` for width/height) |
| `iFrame` | `int` | Frame counter (0 on first frame, increments each frame) |

### Rules

- Entry point must be `void mainImage(out vec4 fragColor, in vec2 fragCoord)`
- Use `fragCoord` for pixel coordinates (not `gl_FragCoord`)
- Use `iResolution.xy` for resolution (never hardcode pixel dimensions)
- No `#version`, `precision`, `uniform`, or `out` declarations — the runtime adds these
- No `void main()` — the runtime wraps `mainImage` with the platform entry point
- Output to `fragColor` (the `out` parameter)
- Each pass file must be self-contained — no `#include` across files

### Feedback Pattern

Use `iChannel1` to read the previous frame and `iFrame` to skip the first frame (where no previous data exists):

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  vec4 current = texture(iChannel0, uv);

  // Read previous frame (skip frame 0 — no data yet)
  float trail = 0.0;
  if (iFrame > 0) {
    trail = texture(iChannel1, uv).a;
  }

  // Decay and accumulate
  trail = max(trail * 0.995, current.a);

  fragColor = vec4(current.rgb, trail);
}
```

The alpha channel is a good place to store temporal state — it survives feedback but doesn't affect visual output if the next pass only reads `.rgb`.

### Custom Uniforms

Shaders can declare custom uniforms that appear as sliders/inputs in the UI. Declare them in `package.json` and reference them directly in GLSL — the runtime injects them.

```json
"uniforms": [
  {
    "name": "rainAmount",
    "displayName": "Rain Amount",
    "type": "float",
    "default": 0.7,
    "min": 0.0,
    "max": 1.0,
    "description": "Density of rain"
  }
]
```

| Uniform Field | Required | Description |
|---------------|----------|-------------|
| `name` | Yes | GLSL identifier (must match `[a-zA-Z_]\w*`) |
| `displayName` | Yes | UI label |
| `type` | Yes | `float`, `vec2`, `vec3`, `vec4`, or `color` |
| `default` | Yes | Default value |
| `min` / `max` | No | Range for float sliders |
| `description` | No | Tooltip text |

In your GLSL, just use the name directly — no declaration needed:

```glsl
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // rainAmount is available as a variable — no 'uniform' declaration
  float intensity = rainAmount * 2.0;
  ...
}
```

The converter injects these into an HLSL `cbuffer` at `register(b1)` automatically.

## Supported GLSL

Your shader is auto-converted to HLSL. Use these GLSL features freely — they all convert correctly:

**Types:**
`float`, `int`, `uint`, `bool`, `vec2/3/4`, `ivec2/3/4`, `uvec2/3/4`, `bvec2/3/4`, `mat2/3/4`

**Functions:**
`mix`, `fract`, `mod`, `atan` (1 or 2 args), `inversesqrt`, `dFdx`, `dFdy`, `clamp`, `smoothstep`, `step`, `pow`, `sin`, `cos`, `tan`, `exp`, `log`, `sqrt`, `abs`, `sign`, `floor`, `ceil`, `round`, `min`, `max`, `dot`, `cross`, `normalize`, `length`, `distance`, `reflect`, `refract`

**Texture sampling:**
`texture(iChannel0, uv)`, `textureLod(iChannel0, uv, lod)`, `texture(iChannel1, uv)`, `textureLod(iChannel1, uv, lod)`

**Matrix math:**
`mat2 * vec2`, `vec2 * mat2` (auto-converted to `mul()`)

**Other:**
`const` arrays, `#define` macros, helper functions, `for`/`while` loops, ternary `? :`, swizzles (`.xyz`, `.rg`, etc.)

## What to Avoid

These GLSL features do NOT convert and will break on Windows:

- `texelFetch`, `textureGrad`, `textureSize` — only `texture()` and `textureLod()` are supported
- `lessThan`, `greaterThan`, `equal`, `notEqual` — use component-wise comparison operators instead
- `matrixCompMult` — use component-wise multiply manually
- `struct` uniforms — use the `uniforms` array in `package.json` for custom inputs
- Multiple `out` variables — only `fragColor` is supported
- `discard` statements
- Geometry or vertex shader features

## Testing

**Both Linux and Windows tests MUST pass.** A shader that passes Linux but fails Windows will break the DX11 texture bridge on production Windows machines.

| Script | OS | What it tests |
|--------|----|---------------|
| `scripts/test_linux.sh` | Linux | GLSL compilation (glslang WASM → SPIR-V) + structural HLSL checks + custom uniform injection |
| `scripts/test_windows.ps1` | Windows | HLSL compilation with fxc.exe (Windows SDK) + custom uniform injection |

```bash
# Linux — run from repo root
npm test
```

```powershell
# Windows — run from repo root (PowerShell)
.\scripts\test_windows.ps1
```

If your shader compiles in the browser preview but fails the Windows test, you're using an unsupported GLSL feature — check the "What to Avoid" list above.

## License

MIT
