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
| `passthrough` | Identity shader — outputs the GPU texture unchanged. Baseline for custom effects. |

## License

Copyright (C) 2024-present Jonathan Mills, CatapultCase. All rights reserved.
