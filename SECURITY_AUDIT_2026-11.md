# Security Audit — JunctionRelay_Shaders

- **Audit date:** 2026-11-17
- **Repository:** `catapultcase/JunctionRelay_Shaders`
- **Commit audited:** `dd199b859eb06442230df7fa786e8eecfa680b0b` (`dd199b8`, "Make the 'has no uniform declarations' shader test ignore comments (#3)") — this is `HEAD` in the working directory and equals `origin/main` (`git log --all` shows a single commit).
- **Type:** read-only source review. No existing file was changed; this report is the only artifact added. Nothing here claims a fix has been applied — every item is a *proposed* fix. Any finding that needs a code change becomes its own ticket.

## Severity scale

- **Critical** — a remote/unauthenticated attacker gets code execution on a user machine or the host, or reads protected material (captured screen, credentials) with no user action.
- **High** — code execution or a documented-but-absent control; the attacker needs attacker-supplied plugin content plus one ordinary developer/CI action, or the impact is disclosure of host-owned data.
- **Medium** — the attacker needs local access, control of the environment, or a developer-run dev script; impact is limited.
- **Low** — hardening; the attacker already needs substantial access.
- **Info** — observation with no exploitable defect found.

## Summary of findings

| Severity | Count |
|----------|-------|
| Critical | 0     |
| High     | 4     |
| Medium   | 4     |
| Low      | 4     |
| Info     | 2     |

| ID | Severity | Title | Location |
|----|----------|-------|----------|
| H1 | High | Shader-manifest values are interpolated into a `node -e` JavaScript source string — code execution in the Windows test script | `scripts/test_windows.ps1:39` (also `:25`) |
| H2 | High | Manifest uniform `name` is injected verbatim into generated shader source; the documented identifier rule is not enforced by the SDK validator | `packages/sdk/src/index.js:51`, `packages/sdk/src/glslToHlsl.js:57-60`, `test.html:494-497`, `packages/sdk/src/__tests__/shaders.test.js:45-48` |
| H3 | High | `passes[].entry` is not validated as a bare filename — every consumer reads/fetches/compiles a path outside the plugin directory | `packages/sdk/src/index.js:43-45`, `test.html:196`, `packages/sdk/src/__tests__/shaders.test.js:197,304`, `scripts/test_windows.ps1:32` |
| H4 | High | The manifest gate is dead code and shader identity is unauthenticated: `validateManifest` is never called, and any package may claim any `shaderName` | `packages/sdk/src/index.js:25,34-37,72`, `README.md:109` |
| M1 | Medium | `execSync` interpolates an attacker-influenced temp path into a shell string — command substitution runs (confirmed) | `packages/sdk/src/__tests__/shaders.test.js:98` |
| M2 | Medium | Predictable temp file names in a shared `$TMPDIR` while writing GLSL and a Node entry script | `packages/sdk/src/__tests__/shaders.test.js:80-81,83,85` |
| M3 | Medium | Dev server binds all interfaces and serves the whole repository (including `.git/`); the `?path=` parameter is unvalidated | `serve.py:59`, `test.html:157-159` |
| M4 | Medium | Untrusted GLSL is parsed by an unmaintained 0.0.x glslang WASM build inside an unsandboxed Node process with no resource limits | `packages/sdk/src/__tests__/shaders.test.js:85-102`, `package.json:11`, `package-lock.json:16-21` |
| L1 | Low | Preset and uniform values are not type- or range-checked before reaching `gl.uniform*` | `packages/sdk/src/index.js:49-67`, `test.html:354-359,326-327,680-684` |
| L2 | Low | Manifest-controlled strings reach logs/errors unsanitised; no size or count caps on manifest or shader source | `packages/sdk/src/index.js:36,57,64`, `test.html:196-197` |
| L3 | Low | Shader fetches are not checked (`res.ok`, content type) and the dev page ships no CSP/SRI | `test.html:171-198` |
| L4 | Low | `Remove-Item -Recurse -Force` on a path derived from the current directory | `scripts/test_windows.ps1:14-16` |
| I1 | Info | No secrets in the working tree or in git history | — (see Secrets) |
| I2 | Info | Dependency surface is one unmaintained 0.0.x dev package from an unofficial mirror, with a floating range in `package.json` | `package.json:10-12`, `package-lock.json:16-21` |

## Scope and method

Read-only review of every tracked file (46 files; `git ls-files`). The repo is an npm workspaces monorepo of GPU pixel-shader plugins:

- `packages/sdk` — `@junctionrelay/shader-sdk`: `src/index.js` (manifest validation), `src/glslToHlsl.js` (GLSL→HLSL string converter), `src/__tests__/shaders.test.js` (the whole `npm test` suite).
- `shaders/*` — 12 shader packages (19 passes, 102 distinct uniform names, 47 presets): `package.json` manifest + `.glsl` passes.
- `test.html`, `poc/*.html` — browser preview harnesses; `serve.py` — their dev server.
- `scripts/test_linux.sh`, `scripts/test_windows.ps1` — documented CI/dev test entry points.
- Root `package.json`, `package-lock.json`, `README.md`, `.gitignore`, `.gitattributes`.

Areas covered, as required by the ticket:

1. **Plugin/shader code loading and running** — `packages/sdk/src/index.js`, `packages/sdk/src/glslToHlsl.js`, the 12 packages under `shaders/`.
2. **Host input from the server / network** — manifests, presets, uniform values and shader source as consumed by `test.html` (and, where relevant, by the out-of-repo host).
3. **Process spawn / file write** — the child-process SPIR-V compile in `shaders.test.js`, `serve.py`, `scripts/test_linux.sh`, `scripts/test_windows.ps1`, `test.html`, `poc/`.
4. **Dependencies and install scripts** — `package.json`, `package-lock.json`, `@webgpu/glslang`.
5. **Secrets in the repo and in git history** — read-only `git log -p --all`, `gitleaks` v8.24.0, manual keyword sweep.

Method: full read of all source, plus targeted sweeps for `eval` / `new Function` / `innerHTML` / `document.write` / `postMessage` / `WebSocket` / `localStorage` / `fetch` / dynamic `import()`, `child_process` / `exec` / `spawn`, `fs` writes and `path.join`, and secret material. Behaviour was confirmed by executing code: `validateManifest` and `convertGlslToHlsl` were called with hostile manifests; `set -e; npm ci; npm test` was run; `npm audit` and `npm audit signatures` were run; `gitleaks` was run over history and the working tree. One proof-of-concept shader package was built in a **throwaway copy of the repo outside the working directory** (`/tmp/clanker-job-R2NDxZ/tmp/opencode/`, since deleted) to test manifest handling without touching the audited tree; no file inside the repository was added, changed or deleted.

**Out of scope / out of repo.** The JunctionRelay host that actually loads a shader package at runtime, the Windows DX11 texture-bridge sidecar that compiles the HLSL, the code that receives manifests/presets/uniform values from the JunctionRelay server, and the presenter that feeds `iChannel0` (the desktop capture) are all in other repositories. Statements about that code are marked **unconfirmed**; the in-repo code that produces or validates what it receives is in scope and findings there are **confirmed**.

## Trust model

A shader package is data plus GPU code: a `package.json` manifest and one or more `.glsl` files. Nothing in this repo `require`s or `import()`s plugin code, and the test suite only `JSON.parse`es manifests — so a plugin cannot execute JavaScript through the paths in this repo. What a plugin *does* control:

- **Shader source text**, which is compiled and run by the host (WebGL/DX11) and parsed by the glslang WASM build in tests.
- **Manifest strings** — `shaderName`, `passes[].entry`, `uniforms[].name`, `displayName`, `description`, preset names/values — which the SDK, the tests and `test.html` splice into shader source, filesystem paths, URLs, shell command lines and PowerShell command lines.

The rule the audit applies: **every manifest field is attacker-controlled** (`README.md:109` explicitly invites third-party namespaces). Fields that are only displayed are low risk; fields that reach a compiler, a path, a URL or a command line are the interesting ones — and that is exactly where the findings are. In this design the GPU program receives the **desktop capture** on `iChannel0` and the **previous frame output** on `iChannel1`, so shader-source injection is also a screen-content disclosure path.

---

## Findings

### H1 — Manifest values interpolated into a `node -e` source string: code execution in the Windows test script (High, confirmed)

- **Where:** `scripts/test_windows.ps1:39`. The line builds a JavaScript program by PowerShell string interpolation and hands it to `node -e`:

  ```powershell
  node -e "…fs.writeFileSync('$($hlslFile -replace '\\','/')',convertGlslToHlsl(fs.readFileSync('$($glslPath -replace '\\','/')','utf8'),u))"
  ```

  `$glslPath` is `Join-Path $shaderDir.FullName $entry` (`:32`), i.e. the manifest's `passes[].entry` string, and `$hlslFile` is derived from it (`:36`). `:25` has the same shape with the on-disk directory name: `node -e "…require('./shaders/$name/package.json')…"`.
- **What goes wrong:** the values are wrapped in JavaScript **single quotes** with no escaping. Any `'` in the value closes the string literal and the rest of the line becomes attacker-authored JavaScript, executed by the developer's/CI's `node` with full user rights — e.g. an `entry` of `a.glsl',require('child_process').execSync('calc');//` turns the convert step into arbitrary code execution. `-replace '\\','/'` only rewrites backslashes; it does not neutralise quotes. The same line also writes the converted HLSL to a path the manifest chooses (`fs.writeFileSync` at `:39`, and `:44` feeds that path to `fxc.exe`).
- **What an attacker needs:** the ability to place a shader package under `shaders/` (or to publish one that a maintainer drops in — the documented workflow in `README.md:239-247`) plus one run of the documented `.\scripts\test_windows.ps1`. That is attacker content + one routine CI/dev action, which is why this is High and not Critical.
- **Confirmed / unconfirmed:** **confirmed** by reading the string construction; no exploit was run against a Windows host here. `scripts/test_linux.sh` has no equivalent pattern (it is `set -euo pipefail; cd; npm test`).
- **Proposed fix:** stop generating JavaScript by string concatenation. Convert in-process with a small `--eval`-free helper script that takes the paths as **argv** (`node scripts/convert-hlsl.mjs --pkg … --out …`), or pass them via environment variables / a JSON manifest-of-work file, and validate `entry` per H3 before it is used. If `node -e` must stay, apply the identifier/filename allowlist from H2/H3 and reject anything containing a quote, backslash or `..`.

### H2 — Manifest `uniforms[].name` is spliced into shader source; the documented identifier rule is not enforced (High, confirmed)

- **Where:** `packages/sdk/src/index.js:51` — the only check is `if (!u.name || typeof u.name !== 'string')`. `README.md:180` documents the rule (`name` … "must match `[a-zA-Z_]\w*`"), and the test suite enforces it (`packages/sdk/src/__tests__/shaders.test.js:235`), but the SDK validator never applies it. The unchecked value is then concatenated into source in three places:
  - `packages/sdk/src/glslToHlsl.js:57-60` — `` `  ${uniformHlslType(u.type)} ${u.name};` `` inside `cbuffer CustomUniforms : register(b1) { … }`, which is prepended to the HLSL at `:63` and compiled by `fxc` on Windows (`scripts/test_windows.ps1:44`) and by the DX11 sidecar at runtime (**unconfirmed**, out of repo).
  - `test.html:494-497` — `` `uniform float ${u.name};` `` / `uniform vec3 …` spliced into the fragment-shader string compiled at `test.html:559`.
  - `packages/sdk/src/__tests__/shaders.test.js:45-48` — the same pattern in the SPIR-V test wrapper.
- **What goes wrong:** a manifest author injects arbitrary GLSL/HLSL into the host's program, not just a uniform name. Observed output for `name = "x; float4 stolen : register(t9); //"` with `validateManifest` returning `{ valid: true }`:

  ```hlsl
  cbuffer CustomUniforms : register(b1) {
    float x; float4 stolen : register(t9); //;
  ```

  The injected text can declare additional resource bindings (`register(t9)` — any texture the host happens to have bound, including the desktop capture on `iChannel0` and the previous-frame texture on `iChannel1`), redefine the runtime's own identifiers (`time`, `iFrame`, `resolution`, `tex0`, `sampler0`, `uv`, `_flipV`; a name of `resolution` is accepted and is emitted alongside the built-in `float2 resolution` in the same header), or comment out the rest of the generated body. Because the shader's output is drawn to screen, code that samples an extra bound texture and encodes it into pixel colours is a screen-content disclosure channel that no log or error message would show. In the browser path (`test.html`) the same injection produces arbitrary GLSL in the host page's WebGL context.
- **What an attacker needs:** ship a shader package (the normal plugin flow) — no build script has to run, the host loads it. Hence High rather than Medium.
- **Confirmed / unconfirmed:** the validator gap and the source injection are **confirmed** (reproduced against `packages/sdk/src/index.js` and `packages/sdk/src/glslToHlsl.js`). What the DX11 sidecar does with the injected HLSL is **unconfirmed** (out of repo).
- **Proposed fix:** enforce the documented rule where it is documented — add `if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(u.name)) errors.push(...)` to `validateManifest`, cap the name length, and reject names that collide with converter-emitted identifiers (`time`, `iFrame`, `resolution`, `tex0`, `tex1`, `sampler0`, `sampler1`, `uv`, `fragCoord`, `_flipV`, `main`, the `i*` builtins). Apply the same check in `glslToHlsl.js` and throw rather than emit, so no caller can reach the concatenation with an unsafe name, and drop the duplicated regex in the test file in favour of the SDK's.

### H3 — `passes[].entry` is not constrained to a bare filename (High, confirmed)

- **Where:** `packages/sdk/src/index.js:43-45` (only `typeof pass.entry === 'string'`), and every consumer: `test.html:196` (`` fetch(`${shaderPath}/${pass.entry}`) ``), `packages/sdk/src/__tests__/shaders.test.js:197` (`path.join(shaderDir, pass.entry)`) and `:304` (`fs.readFileSync(path.join(shaderDir, pass.entry))`), `scripts/test_windows.ps1:32` (`Join-Path $shaderDir.FullName $entry`).
- **What goes wrong:** `entry` is a path, not a name. Nothing rejects `..`, `/`, `\` or an absolute path, so a plugin manifest makes every tool read a file outside the plugin directory. Verified in a throwaway copy of the repo: a package whose only pass was `"entry": "../../leak.glsl"` (a file placed **outside** `shaders/`) passed the entire suite — the pass-entry existence test, the glslang/SPIR-V compile and the HLSL conversion all followed the path and processed the out-of-package file. An `entry` of `../../../../../../etc/hostname` was likewise resolved to `/tmp/etc/hostname`, i.e. straight out of the plugin tree. The consequences per consumer: the Node tooling reads arbitrary files the build user can read (contents can surface in glslang error text, and per H1 can execute); the PowerShell script also writes and compiles attacker-chosen paths; `test.html` issues a `fetch()` for an attacker-shaped URL, which the browser normalises so it can reach any path under the served root — the whole repository, including `.git/`, when served by `serve.py` (M3).
- **What an attacker needs:** ship a shader package.
- **Confirmed / unconfirmed:** **confirmed** for the SDK, the test suite and `test.html`; whether the production host loader resolves `entry` from disk the same way is **unconfirmed** (out of repo) — treat it as the same bug until checked.
- **Proposed fix:** in `validateManifest` require `/^[A-Za-z0-9._-]+\.glsl$/` and reject any `entry` containing `/`, `\`, `..` or `:`; in each consumer resolve the path and assert the result is inside the plugin directory (`path.resolve(dir, entry).startsWith(path.resolve(dir) + path.sep)`, same for the browser URL with a per-segment allowlist), before read/fetch/compile. Also cap the number of passes.

### H4 — The manifest gate is never invoked, and shader identity is unauthenticated (High, confirmed)

- **Where:** `packages/sdk/src/index.js:25` (`validateManifest`), `:72` (its only appearance besides the definition) — `grep -rn validateManifest` finds no caller anywhere in the repo, including the tests, which re-implement the rules inline at `packages/sdk/src/__tests__/shaders.test.js:158-294`. Identity handling at `packages/sdk/src/index.js:34-37`: `const shaderId = jr.shaderName || pkg.name;` and a pattern check only.
- **What goes wrong:** two related problems. (a) The SDK's validator is the documented plugin gate but is **dead code** in this repo, and the two rule sets have already drifted: the tests enforce `displayName`, `feedback`, `opaque`, `usesTexture`, uniform `pass` indices, the uniform-name identifier rule and preset shapes (`shaders.test.js:182-294`), while `validateManifest` enforces none of those and instead checks `default` shapes; each manifest is parsed **twice** in the tests (`:148` and again per-`it`, e.g. `:162,166`) so the "validates the manifest the host will see" property is only accidental. A package that satisfies the host's gate can therefore still break the harness, and — more seriously — nothing in the shipping path applies even the weak gate. (b) `shaderName` is a self-declared string with no binding to the publisher or the npm package name, so a third-party package can declare `shaderName: "junctionrelay.rain-window"` (which `validateManifest` happily returns as valid) and impersonate a first-party shader in any host registry keyed by that ID — preset/`displayName`/pass spoofing and shadowing of the real effect.
- **What an attacker needs:** publish a shader package under their own npm name.
- **Confirmed / unconfirmed:** in-repo facts **confirmed**; how the host keys its shader registry (and whether first-party IDs are protected there) is **unconfirmed**.
- **Proposed fix:** make the host call `validateManifest` before a package is used and make the test suite call it too (single source of truth), require `junctionrelay.shaderName` (no `|| pkg.name` fallback), and bind identity to provenance — e.g. require the npm scope to match the `shaderName` namespace, reserve the `junctionrelay.*` namespace for packages published by the org, and record a content hash per release so the host can refuse a package whose manifest/source pair does not match a signed record (see the provenance note under Dependencies).

### M1 — Shell command substitution through the temp path in `execSync` (Medium, confirmed)

- **Where:** `packages/sdk/src/__tests__/shaders.test.js:98` — `execSync(\`node ${JSON.stringify(scriptFile)}\`, { cwd, timeout: 30000, encoding: 'utf8' })`, with `scriptFile` built from `os.tmpdir()` at `:81`.
- **What goes wrong:** `JSON.stringify` adds double quotes, which is JavaScript-safe but not shell-safe: inside POSIX double quotes `$(`, backticks and `$var` still expand. `os.tmpdir()` honours `TMPDIR`, so a TMPDIR containing `$(…)` executes arbitrary commands when `npm test` runs. Confirmed on this machine: with `TMPDIR=/tmp/…/x$(touch /tmp/…/PWNED)` the same expression created the `PWNED` marker file (the node run then failed with ENOENT, as expected for that directory). On Windows `cmd.exe` has the same weakness with `%VAR%` expansion, and `execSync` there runs through a shell too.
- **What an attacker needs:** the ability to set the environment of the test/CI process (a CI variable, a committed `.npmrc`/env file, a shell profile) — i.e. local/CI access, so Medium.
- **Confirmed / unconfirmed:** **confirmed**.
- **Proposed fix:** no shell: `execFileSync(process.execPath, [scriptFile], { cwd, timeout: 30000, encoding: 'utf8' })`, and validate the temp root (reject paths containing shell metacharacters) rather than trusting `TMPDIR`.

### M2 — Predictable temp file names in a shared `$TMPDIR` (Medium, confirmed)

- **Where:** `packages/sdk/src/__tests__/shaders.test.js:80-81` — `path.join(os.tmpdir(), \`spirv_test_${process.pid}.glsl\`)` and `…\`spirv_test_${process.pid}.js\``; written with `fs.writeFileSync` at `:83` and `:85`, the `.js` one then executed at `:98` and deleted at `:107-108`.
- **What goes wrong:** the names are fully predictable (PID only) and `fs.writeFileSync` follows symlinks and uses default `0666 & ~umask` modes. On a shared/multi-user machine (or a runner where several users share a world-writable `TMPDIR`) a local attacker can pre-create `spirv_test_<pid>.glsl`/`.js`, or a symlink from that name to a file the build user owns, and the test suite will overwrite the target — arbitrary file write as the build user, with a short, repeatable PID-guessing window. `finally`-block `unlinkSync` then removes whatever is there.
- **What an attacker needs:** a local account able to write in the same `TMPDIR`.
- **Confirmed / unconfirmed:** **confirmed** in code (CWE-377); not demonstrated against another user's session here.
- **Proposed fix:** create a private directory per run — `fs.mkdtempSync(path.join(os.tmpdir(), 'spirv-'))` with mode `0700`, write inside it with mode `0600`, and remove it recursively at the end.

### M3 — Dev server binds all interfaces and serves the whole repository; `?path=` is unvalidated (Medium, confirmed)

- **Where:** `serve.py:59` — `http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler)` on port 8080 (`:5`), rooted at the repository root (`:6` `os.chdir(...)`); `test.html:157-159` — `params.get('path')` is interpolated straight into `` `shaders/${shaderName}` `` and used for the manifest fetch (`:171`) and pass fetches (`:196`).
- **What goes wrong:** `""` binds every interface, so on a developer workstation or a CI laptop the entire repository — source, `.git/` objects and refs, and anything else that lives in the working tree — is readable by any host on the LAN, with directory listing on and no authentication, TLS or `Host`/origin check. `SimpleHTTPRequestHandler` also logs the request line to the console, and the page it serves takes an arbitrary `path` segment from the URL, so a link as simple as `http://<dev-host>:8080/test.html?path=../packages/sdk` makes a victim's browser read out-of-plugin paths through the app itself (URL normalisation clamps at the served root, so this reads "anything under the root" rather than the filesystem above it). Combined with H3, a manifest fetched from such a server also controls the second request.
- **What an attacker needs:** network reachability to the developer's machine, or a user clicking a link to a running instance.
- **Confirmed / unconfirmed:** **confirmed** for the code shown; how often the server is reachable is deployment-dependent.
- **Proposed fix:** bind to `127.0.0.1`, refuse `path` values that do not match `/^[a-z0-9][a-z0-9.-]*$/` (or match a directory actually found under `shaders/`, which `serve.py` already enumerates at `:9-22`), and pass the chosen shader via a server-side allowlist rather than a client-supplied path.

### M4 — Untrusted GLSL parsed by an unmaintained glslang WASM build in an unsandboxed Node process (Medium, confirmed)

- **Where:** `packages/sdk/src/__tests__/shaders.test.js:85-102` (`require('@webgpu/glslang')().then(g => g.compileGLSL(glsl, 'fragment'))` in a child `node` process), `package.json:11` and `package-lock.json:16-21` (`@webgpu/glslang` `0.0.15`).
- **What goes wrong:** the only thing standing between plugin-supplied GLSL and a memory-unsafe C++ parser is a WASM compilation published as `0.0.15` from an unofficial mirror (`repository.url` in the installed `package.json` points at `github.com/kainino0x/-webgpu-glslang`), last touched upstream in the WebGPU pre-1.0 era and no longer maintained. A memory-safety bug in that build is code execution *inside* the child process, which runs with the developer's/CI's normal file rights and with no resource limits beyond `timeout: 30000` on the parent (no CPU/memory cap, no filesystem or network restriction, no `--experimental-permission`). `README.md:216` explicitly advertises support for arbitrary `for`/`while` loops, so pathological sources are expected input. The same parser family is used by the out-of-repo host toolchain (**unconfirmed**).
- **What an attacker needs:** ship a shader package; the parse happens on every `npm test` and on every CI run of `scripts/test_linux.sh`.
- **Confirmed / unconfirmed:** the dependency, its provenance and the absence of any sandbox/limits are **confirmed**; there is no known advisory for this package in the current npm advisory feed (`npm audit` → 0 vulnerabilities), and no exploit was attempted.
- **Proposed fix:** move to a maintained glslang binding (or DXC) pinned by hash and vendored, drop `^` in favour of an exact version, and run the compile with constraints: `execFileSync` (see M1) inside `mkdtemp` (see M2) with `--max-old-space-size`, a `killSignal`/`timeout`, `uid`/`gid` drop where available, and `node --experimental-permission --allow-fs-read=<repo>/node_modules/@webgpu/glslang,=<the temp file>` so the parser process cannot read the developer's home directory.

### L1 — Preset and uniform values are not type- or range-checked (Low, confirmed)

- **Where:** `packages/sdk/src/index.js:49-67` (only `u.default` shapes are checked; `presets` are not examined at all), `test.html:354-359` (`applyValues` only checks the key exists: `if (uniformState[k] !== undefined) uniformState[k] = …`), `test.html:326-327` (`parseFloat(num.value) || 0` bypasses the slider's `min`/`max`), `test.html:680-684` (`gl.uniform3f(…, v[0], v[1], v[2])` and `gl.uniform1f(…, v)`).
- **What goes wrong:** a manifest's `presets[].values` (or a preset/uniform value arriving from the server) can carry a string, an object, `null`, `NaN`, `Infinity`, or a colour array shorter than three entries. The test suite checks preset value *kinds* (`shaders.test.js:279-289`) but the runtime path performs no equivalent check, so `undefined`/`NaN` reach `gl.uniform*`, sliders are driven out of their declared range, and `rgbToHex` (`:349-352`) produces `#NaNNaNNaN`-style strings in the UI. Impact is confined to the render and the UI of the page that loaded the manifest, so Low.
- **Proposed fix:** validate preset values against the declared uniform type and range in `validateManifest` (mirror `shaders.test.js:271-289`), and coerce/clamp centrally in `test.html` before assignment (`Number.isFinite`, array length and element checks, clamp to `min`/`max`).

### L2 — Manifest-controlled strings reach logs and errors unsanitised; no size or count caps (Low, confirmed)

- **Where:** `packages/sdk/src/index.js:36` (`` `Invalid shaderName "${shaderId}"…` ``), `:57`, `:64` (uniform name embedded), and the fetches at `test.html:196-197` / `shaders.test.js:304`.
- **What goes wrong:** validation messages embed attacker-chosen text verbatim. A `shaderName` or uniform name containing a newline or an ANSI escape writes over the developer's terminal/log line (spoofed lines, terminal control sequences), and if such a message is ever rendered as HTML by a UI it becomes markup injection. Separately, nothing caps manifest or source size or entry counts: a 1.2 MB GLSL file converts in ~42 ms and 200 000 uniform entries validate in ~9 ms (measured), so this is not a CPU issue, but the host then builds one program plus N uniform lookups per pass and one slider per uniform, i.e. memory/handle exhaustion at a ratio of the attacker's choosing.
- **Proposed fix:** print manifest-supplied strings with a printable-whitelist filter (strip control characters, cap at e.g. 120 chars, `JSON.stringify`-quote them), and bound the manifest: e.g. ≤ 16 passes, ≤ 128 uniforms, ≤ 64 presets, ≤ 64 KiB per pass source, refusing the package otherwise.

### L3 — Shader fetches unchecked; no CSP or SRI on the preview pages (Low, confirmed)

- **Where:** `test.html:171-172` (`await res.json()` with no `res.ok` or content-type check) and `:196-197` (`await glslRes.text()` likewise); no `Content-Security-Policy`, `X-Content-Type-Options`, `Referrer-Policy` or `Cross-Origin-Opener-Policy` anywhere, since the only server is `serve.py:59`.
- **What goes wrong:** a 404 page or an HTML error body is parsed as JSON/GLSL and fed to the shader compiler, which produces confusing failures rather than a stop; and with no CSP the page will execute whatever a mis-served or attacker-influenced response contains in a same-origin context that has access to the rendered desktop capture. `test.html:164-166` does use `innerHTML`, but only with a fixed literal string, and all other manifest-driven DOM writes use `textContent` (`:175-177,252,292,304,337`) — that part is not exploitable.
- **Proposed fix:** check `res.ok` and `content-type` before parsing, and have `serve.py` add `Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src blob:; connect-src 'self'; base-uri 'none'; form-action 'none'` plus `X-Content-Type-Options: nosniff` (the inline `<script>` in `test.html` needs `unsafe-inline` or a nonce unless it is moved to a file).

### L4 — `Remove-Item -Recurse -Force` on a directory derived from the current directory (Low, confirmed)

- **Where:** `scripts/test_windows.ps1:14-16` (`$tempDir = Join-Path (Get-Location) "tmp"`; `if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }`) and `:62`.
- **What goes wrong:** the script deletes `.\tmp` before and after a run with no check that it is a real directory rather than a junction/symlink/reparse point, so an attacker who can pre-create that link in a repo checkout (or a CI workspace that is reused) can aim a recursive forced delete at a target of their choice; the converted HLSL is also left in the repo tree on failure (`:59`).
- **What an attacker needs:** write access to the checkout before a maintainer runs the script.
- **Proposed fix:** use the OS temp directory (`Join-Path ([System.IO.Path]::GetTempPath()) …` or `New-Item -ItemType Directory` under `$env:TEMP`), check `Get-Item … | Select-Object LinkType` and refuse reparse points, and scope the delete to files matching `*_*.hlsl|err|out`. (`tmp/` is already gitignored at `.gitignore:2`.)

### I1 — No secrets in the repository or its history (Info)

Nothing to report as a secret: see the Secrets section for the commands run. There are no `.env`, key, token or credential files, no hardcoded keys in source/README/scripts, and `.git/config` holds an HTTPS remote URL with no embedded credential.

### I2 — Dependency notes (Info)

One external dependency, no install scripts, signature verified — but it is an unmaintained `0.0.x` release from an unofficial repository, `package.json:11` carries a floating `^0.0.15` range, and the installed package ships five WASM bundles (`dist/node-devel`, `web-devel`, `web-devel-nocompute`, `web-devel-onefile`, `web-min-nocompute`) of which only `dist/node-devel` is used. See M4 for the parser-trust issue and Dependencies below.

---

## Areas checked with no findings

- **`poc/` (`generative_poc.html`, `generative_poc_lite.html`): No findings.** Checked for: network I/O (`fetch`, `XMLHttpRequest`, `WebSocket` — only mentioned in comments at `generative_poc.html:30,216`), dynamic code (`eval`, `new Function`, template-interpolated shader source from a variable), DOM sinks (`innerHTML`, `document.write`, `location` writes), storage (`localStorage`, `sessionStorage`, `indexedDB`, cookies), message handlers (`postMessage`), `fs`/process access (none available in a page). The GLSL is a hardcoded literal in each file; sensor values are simulated locally (`fakeSensor`, `:204-206` / `:146-148`); compile/link errors go to `console.error` and `textContent`. All loops in the embedded shaders are bounded (`for (int i = 0; i < 5|3|64 …)`).
- **`scripts/test_linux.sh`: No findings.** Five lines: `set -euo pipefail`, `cd "$(dirname "$0")/.."`, `npm test`. No interpolation into a shell string beyond the quoted `cd`, no network, no writes, no privilege change.
- **Shipped shader packages under `shaders/` (12 packages, 19 passes, 102 distinct uniform names, 47 presets): No findings** in the content itself. Checked: every `passes[].entry` is a bare `*.glsl` filename with no `/`, `\` or `..`; every `uniforms[].name` matches `[A-Za-z_]\w*` and collides with none of the converter-injected identifiers (`time`, `iFrame`, `resolution`, `tex0`, `sampler0`, `uv`, `fragCoord`, `_flipV`); no `#version`, `precision`, `uniform` or `out vec4` declarations, no `gl_FragCoord`, no `void main()`, no `#include`, `#define`, `discard`, `texelFetch`, `while` loops or unbounded loops (all `for` bounds are literals; the widest is 48 iterations in `shaders/junctionrelay.tunnel/tunnel.glsl:53`); no hardcoded `1920.0`/`1080.0`; no URLs, IPs, emails, identifiers or secret-shaped strings in any `.glsl` or manifest. The *enforcement* gap around these facts is H2/H3, not the content.
- **Dynamic JavaScript loading of plugin code: No findings.** No `require(` of a plugin path, no dynamic `import()`, no `eval`, no `new Function` anywhere in `packages/sdk/src`, `test.html`, `poc/` or `serve.py`; the only `require()` in shipped code is the static `require('./glslToHlsl')` at `packages/sdk/src/index.js:72`. Manifests are `JSON.parse`d (`shaders.test.js:148,162`), never evaluated; `serve.py` reads them with `json.load` (`:16-17`).
- **Browser-side message/trust boundaries: No findings** beyond L3 — no `postMessage`, `WebSocket`, `BroadcastChannel`, `serviceWorker`, storage or credential use in `test.html` or `poc/`.
- **Shader-source conversion correctness as a safety property (`packages/sdk/src/glslToHlsl.js`): No findings** other than H2. Checked every rewrite stage for unbounded work and for re-entrancy on hostile input: the scanners at `:143-173`, `:198-229`, `:235-262`, `:267-311`, `:327-366` all advance `lastIndex`/`i` past the current match and terminate on unbalanced parentheses (`pos` is clamped by `pos < text.length`), and `replaceMatrixMultiply` (`:178-192`) builds its `RegExp`s only from identifiers captured by `/[a-zA-Z0-9_]/` names, so no attacker string reaches a `RegExp` constructor — regex injection is not possible. A 1.2 MB hostile source converted in ~42 ms with no pathological blow-up (measured). No `RegExp` on manifest data, no ReDoS-shaped pattern in `SHADER_ID_PATTERN` (`index.js:10`, anchored, linear).
- **SSRF / outbound connections from tooling: No findings.** `serve.py` never acts as a client (the only subprocesses are `xdg-open`/`open`/`os.startfile` on a `http://localhost:8080/…` URL it built itself, `:48-57`); no `http.client`, `urllib.request`, `requests`, `socket`, `subprocess.run(..., shell=True)` or PowerShell `Invoke-WebRequest` anywhere; `test.html` only fetches same-origin relative paths (see M3/H3 for the path-validation part). No TLS code, so no disabled certificate checks to report.
- **Test-suite integrity: No findings.** `npm test` runs `node --test src/__tests__/*.test.js` (`packages/sdk/package.json:7`) with no `--test-only`, no `.only`, no `--test-skip`, no `todo`, no `try/catch` swallowing assertions, and no assertion weakening; the 12 skips are the pre-existing conditional `skip:` options at `shaders.test.js:464` (`skip: !usesTexture`) and `:471` (`skip: !customUniforms || customUniforms.length === 0`) and apply only to passes that genuinely lack those features. This audit added, changed and skipped nothing.

## Dependencies and install scripts

- **Lockfile:** `package-lock.json` at the root, lockfileVersion 3. External resolution is a single registry tarball: `node_modules/@webgpu/glslang` → `https://registry.npmjs.org/@webgpu/glslang/-/glslang-0.0.15.tgz` with an `integrity` sha512 pin and `dev: true` (`package-lock.json:16-21`). The only other entries are the local workspace links (`@junctionrelay/shader-sdk` → `packages/sdk`). No git, `file:`, http or tarball dependencies; no `overrides`/`resolutions`; no `.npmrc`/`.yarnrc`/`packageManager` pinning an alternate registry.
- **`npm audit` (from the committed lockfile, run on the audited commit):** `found 0 vulnerabilities` — no advisories for `@webgpu/glslang@0.0.15`. `npm audit signatures` → "1 package has a verified registry signature". No provenance attestations are recorded for it, and it is not a scoped/verified publisher: the package's own `repository.url` is the unofficial mirror `github.com/kainino0x/-webgpu-glslang`.
- **Install-time lifecycle scripts:** none. Root `package.json` defines only `test`; `packages/sdk/package.json` defines only `test`; `@webgpu/glslang@0.0.15` declares no `scripts` at all (checked in the installed manifest), so `npm ci` executes no third-party install script. Transitive graph is empty (`npm ls --all` → 2 entries, one a workspace link).
- **`@webgpu/glslang` review:** loads `dist/node-devel/glslang.js` (13 KB) + `glslang.wasm` (943 KB); the JS shim requires only `fs` and `path` — no network, no `child_process`, no `eval`/`new Function` — so it is a WASM loader, not a code-execution risk by itself. Risk is the parser itself and its age/provenance: see M4, I2. `package.json:11` requests `^0.0.15` — for a `0.0.x` package npm treats that as effectively exact, but the range plus a floating `^` on a `0.x` package is still worth pinning exactly.
- **Supply-chain observation for the plugin ecosystem (no in-repo code to fix):** a shader package is unsigned, unhashed content that the host turns into GPU code, and this repo provides neither a signing step nor a hash allowlist (H4). A per-release `shaderName` + content-hash manifest signed by the publisher would close both H4's spoofing half and the tamper case.

## Secrets

**No secret values were found, so none are described by value here.** Commands and coverage:

- `gitleaks detect --source . --redact --no-banner --report-format json --report-path <path outside the repo> --exit-code 0` (v8.24.0): **1 commit scanned, ~260 KB, "no leaks found"** — covers working tree and history (`git log --all` shows exactly one commit, `dd199b8`).
- Read-only `git log -p --all` (7 693 lines, whole history) grepped for `api[_-]?key`, `secret`, `token=`, `password`, `BEGIN … PRIVATE KEY`, `AKIA`, `ghp_`, `_authToken`, `npm auth`: no matches.
- Manual keyword sweep over all tracked files (excluding `.git/`, `node_modules/`): no matches for `api[_-]?key`, `secret`, `token`, `password`, `passwd`, `credential`, `private key`, `BEGIN … PRIVATE KEY`, `AKIA…`, `ghp_`, `xox[baprs]-`.
- `.git/config`: `[remote "origin"] url = https://github.com/catapultcase/JunctionRelay_Shaders` — HTTPS remote, **no embedded credential or token**; no `insteadOf` rewrites. `.git/hooks` contains only the default `*.sample` templates, so **no active local hooks** (nothing that could exfiltrate on commit/push).
- No `.env`, `*.pem`, `*.key`, `*.p12`, `.npmrc`, `.netrc`, `id_rsa`, or CI credential file is tracked or present; `.gitignore` covers `node_modules/`, `tmp/`, `*.log`, `.DS_Store`. There is therefore no file/line/kind of secret to report.

## Test status

Test command exactly as specified: `set -e; npm ci; npm test`, run in the working directory (the repository root) on the audited commit. **Result: PASS (exit code 0).**

- Environment: `node v22.23.4`, `npm 10.9.9`, Python 3.12.3, Linux.
- `npm ci`: `added 2 packages, and audited 4 packages in 269ms` — `found 0 vulnerabilities`.
- `npm test` → `npm test --workspaces --if-present` → `node --test src/__tests__/shaders.test.js` (`packages/sdk/package.json:7`).
- TAP totals: `# tests 774`, `# suites 99`, `# pass 762`, **`# fail 0`**, `# cancelled 0`, `# skipped 12`, `# todo 0`, `# duration_ms 2560.34`.
- The 12 skips are `# SKIP` lines on `iChannel0 sampling replaced with tex0.Sample/SampleLevel` and `custom uniforms declared in cbuffer` — the pre-existing conditional skips described above (`shaders.test.js:464,471`), which fire for passes whose manifest says `usesTexture: false` or declares no uniforms. Nothing failed, nothing was marked `todo`, and no test was added, removed, edited or skipped by this audit; the suite ran exactly as committed.
- `git status --porcelain` after the run and after writing this report shows only `SECURITY_AUDIT_2026-11.md` as new (`node_modules/` from `npm ci` is gitignored and uncommitted).
- Not run (platform/toolchain unavailable in this container, and not part of the ticket's test command): `scripts/test_windows.ps1` (needs `fxc.exe` from the Windows SDK) and `python serve.py` / `test.html` / `poc/` in a browser. Findings about those files come from reading them plus, where noted, reproducing the equivalent code path directly.

---

*Read-only audit. No existing file was modified and no branch was created, switched or pushed; only this report was added. Every "Proposed fix" is a recommendation for a follow-up ticket — no code in this repository was changed.*
