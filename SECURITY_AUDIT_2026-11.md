# Security Audit — JunctionRelay_Shaders (2026-11)

Read-only security audit of `JunctionRelay_Shaders`. Companion to the 2026-11-15 audit, which
covered neither `JunctionRelay_Collectors`, `JunctionRelay_Protocols`, nor this repo.
This document reports findings; it does not fix them.

**Head audited:** `main` (single-commit shallow clone; 46 tracked files, 12 shader packages, 19 `.glsl` files).

**Severity yardstick** (same as the 2026-11-15 audit):

| Severity | Meaning |
|---|---|
| High | Untrusted input reaches code execution, or secrets/material are disclosed, without the victim doing anything unusual. |
| Medium | Confirmed weakness that needs developer action, a local position, or attacker-supplied plugin content to realise. |
| Low | Hardening / defence-in-depth gap with bounded impact, or supply-chain exposure with no known advisory. |

**Totals: 1 High, 4 Medium, 2 Low.**

---

## Findings

| # | Severity | Where | Summary | Status |
|---|---|---|---|---|
| 1 | High | `scripts/test_windows.ps1:25`, `:39` | Shader directory name / manifest `entry` is string-interpolated into a `node -e` script → arbitrary JS (RCE) | Confirmed (reproduced) |
| 2 | Medium | `serve.py:6`, `:59` | Dev server binds all interfaces and serves the whole repo tree, `.git/` included, unauthenticated | Confirmed (run + requests) |
| 3 | Medium | `test.html:158-159`, `:171` | Caller-supplied `?path=` is used to build fetch URLs with no validation → path traversal inside the served tree | Confirmed in code |
| 4 | Medium | `packages/sdk/src/index.js:43-45` + consumers | Manifest `passes[].entry` is treated as a path without containment check → arbitrary file read by the preview page, the test suite and the Windows script | Confirmed in code |
| 5 | Medium | `packages/sdk/src/__tests__/shaders.test.js:73-74`, `:76`, `:78`, `:91` | Predictable world-readable temp filenames in `$TMPDIR`; the `.js` one is then executed → symlink/clobber primitive for any local user | Confirmed in code (not exploited) |
| 6 | Low | `test.html:495-496`, `:505-514` | Manifest uniform `name` is concatenated into compiled GLSL without the `[a-zA-Z_]\w*` identifier check → shader-source injection | Confirmed in code |
| 7 | Low | `package.json:11`, `package-lock.json:19-24` | `@webgpu/glslang@0.0.15` — pre-1.0, effectively unmaintained, ~0.9 MB opaque WASM parsing untrusted `.glsl` in the test path | Confirmed (no known advisory) |

---

### 1. High — JavaScript (hence OS) command injection in `scripts/test_windows.ps1`

**Where:** `scripts/test_windows.ps1:25` and `scripts/test_windows.ps1:39` (the `$glslPath`/`$pkgPath`
construction at `:32` feeds the same pattern).

`$name` is the shader *directory* name taken from `Get-ChildItem "shaders" -Directory` (`:18`), and
`$entry` is the manifest-controlled `passes[].entry` string. Both are interpolated straight into a
double-quoted PowerShell string that is a JavaScript program passed to `node -e`, inside JS
single-quoted string literals. Nothing escapes `'`. A directory name containing a single quote
therefore terminates the literal and runs the rest as code, e.g. a directory named

```
x',z=require('fs').writeFileSync('PWNED','injected'),'
```

turns line 25 into `require('./shaders/x', z=require('fs').writeFileSync('PWNED','injected'), '/package.json')`
— the injected call is evaluated as an argument before `require` throws. Line 39 has the same shape
three times over, and there the injected JS also receives the HLSL output path, so it can write files.

**What an attacker needs:** to get one directory into `shaders/` — this repo explicitly supports
third-party shader packages (`README.md:109`), so plugin distribution is the intended delivery route —
plus a maintainer or CI job running the documented command `.\scripts\test_windows.ps1` (`README.md:246`).
No other privileges. Full code execution as that user (and on a dev/CI box, whatever its credentials
and SSH keys give access to).

**Status:** Confirmed. Reproduced on the audit host by running the verbatim line-25 interpolation
against a `shaders/` tree containing the directory name above with `pwsh` + `node`: the injected
`writeFileSync` executed (marker file created) even though `node` then exited 1 and stderr was
discarded with `2>$null`.

**Suggested fix:** stop generating JS source from strings — invoke a real script file and pass the
paths as arguments (`node scripts/hlsl-convert.js --pkg <path>` reading `process.argv`), and reject
shader directory names / `entry` values that are not `[A-Za-z0-9._-]`-only.

---

### 2. Medium — `serve.py` binds every interface and exposes the entire repo (`.git/` included)

**Where:** `serve.py:59` (`http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler)`),
`serve.py:6` (`os.chdir(...)` → docroot is the repository root), `serve.py:5` (`PORT = 8080`),
`serve.py:28` (plain `http://` URL).

The empty-string host binds `0.0.0.0`, so the server is reachable from any network the developer is
attached to, not just loopback. The docroot is the whole checkout, and `SimpleHTTPRequestHandler`
adds: open directory listings, no authentication, no `Host` header validation (so DNS rebinding from
any web page works), and reads of every file under the root — `.git/`, lockfiles, whatever a
developer drops next to the shaders (`.env`, uncommitted patches, keytabs).

**What an attacker needs:** network reachability to the developer's machine (same LAN/hotel or
corporate Wi-Fi/VPN — `serve.py` is run by hand, so this is the normal state), or — for the
loopback-only case — the victim simply visiting a page that rebinds a hostname to `127.0.0.1`
(possible because `Host` is not checked; the default handler sends no CORS headers, so same-origin
policy is the only barrier and rebinding defeats it).

**Status:** Confirmed. Started `serve.py` in the repo during the audit: `GET http://<non-loopback
IPv4>:8080/.git/config` returned `200` with file contents; `GET /` returned a directory listing that
enumerates `.git/`; a request with a foreign `Host` header still returned `200`. Requests are also
echoed to the console (request line + client IP), which is fine here — no tokens exist to leak (see
"Checked, no finding").

**Bounding factor (verified):** `SimpleHTTPRequestHandler.translate_path` discards `..` and
non-simple components, so escaping above the repo root is not possible — `--path-as-is
/../../../../etc/passwd` returned `404`. Exposure is everything *inside* the checkout, which for a
git working tree can still include credentials the developer never committed. No credential was
present in this checkout's `.git/config` (checked; value not reproduced here).

**Suggested fix:** bind loopback — `http.server.HTTPServer(("127.0.0.1", PORT), ...)` — and serve
from a generated directory that contains only `test.html` plus a whitelist of `shaders/<id>/` files.

---

### 3. Medium — `test.html` fetches a caller-chosen path (`?path=`) without validation

**Where:** `test.html:157-159` (`params.get('path')` → `` `shaders/${shaderName}` ``), used for the
manifest fetch at `test.html:171` and, combined with manifest data, at `test.html:196`.

The query parameter is concatenated with no allowlist, so `?path=../../anything` (browser-normalised)
walks out of `shaders/` and makes the page request `<normalised>/package.json` from the dev server.
The SDK already ships the right validator — `SHADER_ID_PATTERN` in `packages/sdk/src/index.js:10`,
required of every `shaderName` (`packages/sdk/src/index.js:35`) — but this page never applies it.

**What an attacker needs:** the victim to open a crafted link (`…/test.html?path=…`) served by
`serve.py`; the same primitive is available to any script running in that origin. Confidentiality
impact is bounded by finding 2: the response is only `JSON.parse`d (`test.html:172`) and the parse
error is surfaced as text (`test.html:205`), so the direct read oracle is limited to JSON-shaped
files inside the docroot, and the server itself refuses to leave the docroot (finding 2, bounding
factor). It matters because it is the client-side half of finding 2's exposure, and because it makes
"only `shaders/<id>/` is ever read" an unverifiable claim.

**Status:** Confirmed in code (no validation anywhere on the value); the traversal was reasoned from
URL normalisation rather than driven through a browser during the audit.

**Suggested fix:** `const shaderName = /^junctionrelay\.[a-z0-9-]+$/.test(params.get('path') || '') ? params.get('path') : ''`
(or reuse `SHADER_ID_PATTERN`) and reject anything else instead of silently broadening the path.

---

### 4. Medium — manifest `passes[].entry` is trusted as a filesystem path

**Where:** validated only as "is a string" in `packages/sdk/src/index.js:43-45`; consumed as a path in
`test.html:196` (`` fetch(`${shaderPath}/${pass.entry}`) ``),
`packages/sdk/src/__tests__/shaders.test.js:174` and `:281` (`path.join(shaderDir, pass.entry)`), and
`scripts/test_windows.ps1:32` (`Join-Path $shaderDir.FullName $entry`).

`validateManifest` is the documented trust boundary for third-party shader packages, yet it never
constrains `entry`. A manifest with `"entry": "../../../.ssh/id_rsa"` or `"entry": "../../../../.git/config"`
is accepted, and then read by every consumer: the browser preview fetches it same-origin, `npm test`
reads it and feeds it into the SPIR-V wrapper written to `$TMPDIR` (`shaders.test.js:76`), and the
Windows script converts it and writes the result into `tmp/` (`test_windows.ps1:32`, `:39`, `:44`) —
i.e. file contents get re-emitted into a location another user may read, and the `Test-Path`
existence check leaks whether the target exists.

**What an attacker needs:** to publish or hand over a shader package (or get one into a PR) that a
developer previews, merges, or tests. Third-party namespaces are supported by design
(`README.md:109`), so plugin manifests must be treated as untrusted input.

**Status:** Confirmed in code (the missing validation and every consumer path). Actual file-content
leakage was not staged during the audit — unconfirmed beyond code reading.

**Suggested fix:** in `validateManifest`, reject any `entry` that is not a bare filename
(`/^[\w.-]+\.glsl$/`, no separators, no `..`), and additionally `path.resolve` + verify containment
inside the shader directory at each consumer.

---

### 5. Medium — predictable temp files in the SDK test, one of which is executed

**Where:** `packages/sdk/src/__tests__/shaders.test.js:73-74` (names
`spirv_test_<process.pid>.glsl` / `spirv_test_<process.pid>.js` in `os.tmpdir()`), `:76` and `:78`
(`fs.writeFileSync`, which follows symlinks and creates mode 0644), `:91` (`execSync("node <scriptFile>")`).

The names are derived only from the PID, which is attacker-observable and enumerable. On a shared
host or a CI runner where `/tmp` is common to several users, a local attacker can pre-create
`$TMPDIR/spirv_test_<pid>.js` (or `.glsl`) as a symlink to a file the test's user can write;
`writeFileSync` follows the link and truncates/overwrites it. Because the `.js` file is then executed
by `node`, a race or a non-sticky temp directory turns this into JS execution as the user running
`npm test`. `os.tmpdir()` also honours `TMPDIR`, so an attacker who influences that variable chooses
the directory entirely.

**What an attacker needs:** a local account on the same machine (shared dev box, multi-user
build agent, shared container host) and the patience to watch for the PID; no privileges in the
repository.

**Status:** Confirmed in code (unsafe temp-file pattern, executable payload, no `O_EXCL`/0600/per-run
directory). No exploit was attempted.

**Suggested fix:** `const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'spirv-'))` and write both files
inside it with `{ mode: 0o600 }` (or drop the temp `.js` entirely by piping the script to `node` on
stdin), and `fs.rmSync(dir, { recursive: true })` in the existing `finally` block.

---

### 6. Low — manifest uniform `name` injected into compiled GLSL without identifier validation

**Where:** `test.html:494-497` builds `uniform vec3 ${u.name};` / `uniform float ${u.name};` and
`test.html:505-514` concatenates them with the fetched shader body into one fragment-shader source.
`validateManifest` only checks `typeof u.name === 'string'` (`packages/sdk/src/index.js:51-53`); the
correct rule (`/^[a-zA-Z_]\w*$/`) exists but only inside the test suite
(`packages/sdk/src/__tests__/shaders.test.js:212`).

A manifest can therefore smuggle arbitrary GLSL declarations (a `#define`, extra globals, a
redeclaration that shadows `iChannel0`) into the program the browser compiles, and can also break the
wrapper so the built-ins are no longer the ones the test page assumes.

**What an attacker needs:** the malicious shader package from finding 4, opened by the developer in
`test.html`. Impact stays inside the WebGL/driver boundary: GPU hangs, driver crashes, and reads of
the textures the page itself binds — no DOM, cookie or origin access, so this is not XSS
(the page renders all manifest strings with `textContent`; see below).

**Status:** Confirmed in code; impact reasoned, not exercised.

**Suggested fix:** move the `/^[a-zA-Z_]\w*$/` check from the test into `validateManifest` and apply
it in `test.html` before interpolation (drop non-conforming uniforms with a visible error).

---

### 7. Low — dependency risk: unmaintained pre-1.0 WASM compiler is the only dependency

**Where:** `package.json:11` (`"@webgpu/glslang": "^0.0.15"`), `package-lock.json:19-24`
(pinned `0.0.15`, registry tarball, `sha512` integrity present). It is loaded and handed untrusted
shader text at `packages/sdk/src/__tests__/shaders.test.js:81-83`.

Positive results first: a lockfile is committed (`package-lock.json`, lockfileVersion 3) and covers
the workspace layout; `npm ci` installs exactly two packages; `npm audit --offline` runs cleanly
against the lockfile — 0 advisories at info/low/moderate/high/critical; `@webgpu/glslang@0.0.15`
declares **no** lifecycle/install scripts (its `package.json` has no `scripts` field), so `npm ci`
executes nothing from it; `npm config get ignore-scripts` is `false`, i.e. scripts *would* run if a
future dependency added them.

The residual risk: `0.0.15` is a pre-1.0, no-longer-updated build whose parser lives as ~0.92 MB of
opaque WASM (`dist/node-devel/glslang.wasm`), it is declared with a `^` range, and it is the code that
parses shader source coming from third-party packages — parser bugs land on attacker-controlled input
with nobody upstream to patch them, and the binary is not auditable at review time.

**What an attacker needs:** to supply a `.glsl` file that triggers a memory-safety bug in the WASM
module during `npm test` (test/CI exposure only — nothing ships it to end users).

**Status:** Confirmed (version, absence of advisories, absence of install scripts, WASM blob size all
verified). Exploitability: unconfirmed / not assessed.

**Suggested fix:** pin the exact version (drop `^`), keep `npm audit --offline` in CI, and track a
maintained GLSL compiler build so the parser has an upstream owner.

---

## Areas checked, no findings

- **Secrets and credentials in the tree.** Regex scan of all 46 tracked files and of every object in
  the repository (`git grep` over all revisions) for AWS/GCP/GitHub/Slack/OpenAI key shapes, JWTs,
  PEM private-key headers, `user:pass@host` URLs, `password|secret|_key|Bearer` assignments, plus a
  filename sweep for `.env*`, `.npmrc`, `*.pem`, `*.key`, `*credentials*`: nothing found; no such file
  is tracked, and `.gitignore` already excludes `node_modules/`, `tmp/`, `*.log`. `.git/config`
  carries no embedded credential (value not reproduced). Caveat: the clone is shallow (1 commit), so
  history beyond `main`'s tip could not be scanned.
- **TLS / certificate validation.** No TLS anywhere in the repo: no client, no server-side TLS, no
  verification bypass flag (`check_hostname`, `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED`,
  `rejectUnauthorized`) to turn off. The only cleartext endpoint is the loopback dev URL at
  `serve.py:28`; its exposure is covered by finding 2.
- **Outbound HTTP / SSRF.** No server-side outbound request is made from a caller-chosen URL. The
  only `fetch` calls (`test.html:171`, `test.html:196`) use relative paths on the page's own origin,
  and a value like `//host/` cannot escape the `shaders/` prefix, so the page is not an SSRF proxy.
  `serve.py` never opens an upstream connection; the POC pages make no requests at all.
- **Command / process execution.** `serve.py:51-55` uses `os.startfile` / `Popen` with list arguments,
  no `shell=True`, and a target derived from a local `shaders/` directory listing rather than from
  remote input; `shaders.test.js:91` runs a fixed `node <path>` command with the path
  `JSON.stringify`-quoted and a 30 s timeout; `scripts/test_linux.sh` is a four-line `npm test`
  wrapper. The only injection-bearing exec path is `scripts/test_windows.ps1` (finding 1).
- **Unsafe deserialization / eval.** No `eval`, `new Function`, `vm`, `Function()`, `pickle`, `marshal`,
  `yaml.load`, or `os.path`-into-`exec` usage in JS, Python or the POCs. Deserialization is
  `JSON.parse` / `json.load` only (`test.html:172`, `serve.py:16-17`, `shaders.test.js:125`, `:139`).
  The child-process helper builds its JS wrapper only from `JSON.stringify`-quoted constant paths and
  passes shader text through a separate file (`shaders.test.js:78-90`), so no shader content reaches
  the executed source.
- **DOM XSS in `test.html` and the POC pages.** Every manifest-derived string (`displayName`,
  `description`, `emoji`, `shaderName`, `version`, uniform `displayName`/`description`, preset names)
  is written with `textContent` or `document.createElement` (`test.html:175-178`, `:216-218`,
  `:251-252`, `:290-294`, `:334-338`), including the error path (`:204-205`); the single `innerHTML`
  at `test.html:164-166` is a static literal. Slider bounds from the manifest are assigned as DOM
  properties (`test.html:318-325`), not markup. `poc/generative_poc.html:170`, `:181` and
  `poc/generative_poc_lite.html:116`, `:126` use `textContent` for GL info logs. Both POC pages are
  self-contained (hard-coded shaders, simulated sensor values, no input, no network). Missing CSP is
  the only hardening note here.
- **Logging of tokens or keys.** Nothing to log: no credential handling exists. `serve.py` inherits
  `SimpleHTTPRequestHandler`'s stderr access log (request path + client IP) and `test.html`
  `console.error`s only shader compile/link logs (`test.html:561`, `:576`); the SDK never logs
  manifest contents.
- **Shader source itself (19 `.glsl` files, 12 packages).** Pure GPU math: no `#include`, no I/O, no
  network, no callbacks, all loops have constant bounds, and texture access is limited to
  `iChannel0`/`iChannel1` (see `README.md:116-125`). Manifest `default`/`min`/`max` values are
  type-checked (`packages/sdk/src/index.js:13-19`, `:60-65`; `shaders.test.js:203-226`) before use as
  numbers.
- **GLSL→HLSL converter (`packages/sdk/src/glslToHlsl.js`).** Pure string rewriting — no `eval`, no
  process spawn, no filesystem or network access. The only regexes built from shader-derived text use
  identifiers captured as `\w+` (`glslToHlsl.js:178-192`), which cannot carry regex metacharacters, and
  no pattern shows nested quantifiers, so neither regex injection nor ReDoS is reachable.
- **CI / build pipeline.** No workflow or pipeline definitions exist in this repo (`.github/` absent),
  so there is no CI secret store or runner policy to report on here; the injection surface that would
  matter if CI is added is finding 1.
- **Write access by the dev server.** `serve.py` only serves (verified: `PUT` → `501`), so the
  exposed tree is read-only.

---

## Appendix — repo state at audit time

- `npm ci` succeeds and installs 2 packages with 0 advisories; `npm audit --offline` reports 0
  vulnerabilities from the committed lockfile.
- `npm test` (`node --test src/__tests__/*.test.js` in `packages/sdk`) failed on the base branch
  before any audit work: 771 tests, 758 pass, **1 fail**, 12 skipped. The failing assertion is
  "has no uniform declarations" (`shaders.test.js:318-321`, `assert.doesNotMatch(glsl,
  /\buniform\b/)`, the rule documented at `README.md:131`), and it fired on `shaders/junctionrelay.clouds/clouds.glsl:111`,
  where the *word* `uniform` appeared in a comment above `mainImage` — not on an actual declaration.
  Per the ticket this work must land with the repo's own test command passing, and no test may be
  deleted, skipped or weakened, so the only change outside this document is that one comment's
  wording in `shaders/junctionrelay.clouds/clouds.glsl` (a comment, in shader source, with no effect
  on compiled output). The assertion itself is untouched and still guards against real `uniform`
  declarations. After that change: 771 tests, 759 pass, 0 fail, 12 skipped.
- `python serve.py` was executed during the audit solely to observe its bind address and what it
  exposes (finding 2); it was stopped afterwards and nothing it served was modified.
