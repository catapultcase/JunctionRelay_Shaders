# test_windows.ps1 — HLSL compilation with fxc (Windows only)
$ErrorActionPreference = "Continue"
Set-Location "$PSScriptRoot\.."

# Find fxc.exe
$fxc = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\fxc.exe" -ErrorAction SilentlyContinue | Select-Object -Last 1
if (-not $fxc) { Write-Host "fxc.exe not found. Install Windows SDK."; exit 1 }

Write-Host "Using: $($fxc.FullName)"
Write-Host ""

$pass = 0
$fail = 0
$tempDir = Join-Path (Get-Location) "tmp"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item $tempDir -ItemType Directory | Out-Null

foreach ($shaderDir in Get-ChildItem "shaders" -Directory) {
    $pkgPath = Join-Path $shaderDir.FullName "package.json"
    if (-not (Test-Path $pkgPath)) { continue }

    $name = $shaderDir.Name

    # Read passes array from manifest
    $entries = node -e "const p=require('./shaders/$name/package.json');const passes=p.junctionrelay?.passes||[];passes.forEach(e=>console.log(e.entry))" 2>$null
    if (-not $entries) { continue }

    foreach ($entry in $entries -split "`n") {
        $entry = $entry.Trim()
        if (-not $entry) { continue }

        $glslPath = Join-Path $shaderDir.FullName $entry
        if (-not (Test-Path $glslPath)) { continue }

        $passName = [System.IO.Path]::GetFileNameWithoutExtension($entry)
        $hlslFile = Join-Path $tempDir "$name`_$passName.hlsl"

        # Convert GLSL to HLSL (pass custom uniforms from manifest)
        node -e "const fs=require('fs');const{convertGlslToHlsl}=require('./packages/sdk/src/glslToHlsl');const pkg=JSON.parse(fs.readFileSync('$($pkgPath -replace '\\','/')','utf8'));const u=pkg.junctionrelay&&pkg.junctionrelay.uniforms;fs.writeFileSync('$($hlslFile -replace '\\','/')',convertGlslToHlsl(fs.readFileSync('$($glslPath -replace '\\','/')','utf8'),u))"

        # Compile with fxc
        $errFile = Join-Path $tempDir "$name`_$passName.err"
        $outFile = Join-Path $tempDir "$name`_$passName.out"
        $proc = Start-Process -FilePath $fxc.FullName -ArgumentList "/nologo","/T","ps_5_0","/E","main",$hlslFile,"/Fo","NUL" -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile -RedirectStandardOutput $outFile
        if ($proc.ExitCode -eq 0) {
            Write-Host "  PASS  $name ($entry)"
            $pass++
        } else {
            Write-Host "  FAIL  $name ($entry)"
            Get-Content $errFile | ForEach-Object { Write-Host "        $_" }
            $fail++
        }
    }
}

Write-Host ""
Write-Host "Passed: $pass  Failed: $fail"
if ($fail -gt 0) {
    Write-Host "HLSL files: $tempDir"
    exit 1
} else {
    Remove-Item $tempDir -Recurse -Force
}
