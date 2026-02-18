# JunctionRelay_Shaders

Shader plugins for the JunctionRelay XSD GPU-accelerated rendering pipeline.

## Structure

Each shader lives in its own subdirectory under `shaders/` and is described by a `package.json` manifest:

```
shaders/
  <shader-name>/
    package.json   ← manifest (name, version, junctionrelay metadata)
    shader.hlsl    ← DX11 pixel shader entry point
```

## Manifest Format

```json
{
  "name": "@junctionrelay/shader-<name>",
  "version": "1.0.0",
  "junctionrelay": {
    "type": "shader",
    "shaderName": "<name>",
    "displayName": "Human Readable Name",
    "description": "What this shader does.",
    "entry": "shader.hlsl"
  }
}
```

## Bundled Shaders

| Shader | Description |
|--------|-------------|
| `hologram` | Cyan tint + scanlines + time-based flicker + edge glow. Ported from XSD-VR Bridge V4 POC. |

## "None" (bypass)

When no shader is selected (`activeShader = ''`), the bridge bypasses the DX11 shader stage entirely and copies the captured frame to the shared texture directly. No GPU shader overhead.

Shaders in this repo are **effects only** — the "None" bypass is always available in the XSD UI.

## License

Copyright (C) 2024-present Jonathan Mills, CatapultCase. All rights reserved.
