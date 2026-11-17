#Requires -Version 5.1
<#
    Runs the exclusive Windows suite from one extracted bundle
    (agent-desktop-e2e-<label>, built by the workflow "Windows E2E bundle of
    a candidate" of Lazurio/agent-desktop) in the signed-in user's session:

      1. keeps the display and the system on for as long as this process
         lives (SetThreadExecutionState; no power setting is changed);
      2. checks the bundle's files against its SHA256SUMS.txt;
      3. Test-InteractiveInput.ps1: refuses to start in a locked session or
         one whose input is blocked;
      4. the U6 harness-core self-test tier, then Run-E2E.ps1, each with its
         log in -OutDir;
      5. the input check again, so a run that lost the session says so.

    Exit: 0 the suite's verdict passed, 1 it failed or aborted, 3 the
    session was not ready (nothing ran), 4 the bundle does not match its
    checksums (nothing ran).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [Parameter(Mandatory = $true)][string]$OutDir
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$BundleRoot = (Resolve-Path -LiteralPath $BundleRoot).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$check = Join-Path $PSScriptRoot 'Test-InteractiveInput.ps1'
$exe = Join-Path $BundleRoot 'target\release\agent-desktop.exe'
$fixture = Join-Path $BundleRoot 'tests\fixture-app-windows\build\AgentDeskFixture.exe'
$stamp = { (Get-Date).ToUniversalTime().ToString('o') }

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class BundleSuiteAwake {
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
'@
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED, until this process ends.
$awake = [BundleSuiteAwake]::SetThreadExecutionState([uint32]2147483651)
"$(& $stamp) keep awake: $(if ($awake -ne 0) { 'on' } else { 'refused' })" | Tee-Object -FilePath (Join-Path $OutDir 'run.log')

Get-ChildItem -LiteralPath $BundleRoot -Recurse -File | Unblock-File
$bad = @(Get-Content -LiteralPath (Join-Path $BundleRoot 'SHA256SUMS.txt') | ForEach-Object {
    $hash, $rel = $_ -split '  ', 2
    $path = Join-Path $BundleRoot $rel
    if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $hash) { $rel }
})
if ($bad.Count -gt 0) {
    "$(& $stamp) bundle does not match SHA256SUMS.txt: $($bad -join ', ')" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
    exit 4
}
"$(& $stamp) bundle: $((Get-Content -LiteralPath (Join-Path $BundleRoot 'BUNDLE.txt')) -join ' | ')" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check *>&1 | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
if ($LASTEXITCODE -ne 0) { exit 3 }

"$(& $stamp) U6 self-test tier" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'tests\e2e-windows\selftest\Invoke-U6SelfTests.ps1') -AgentDesktopBinary $exe *>&1 | Out-File -LiteralPath (Join-Path $OutDir 'u6.log') -Encoding utf8
$u6 = $LASTEXITCODE
"$(& $stamp) U6 exit=$u6" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
if ($u6 -ne 0) { exit 1 }

"$(& $stamp) live suite" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BundleRoot 'tests\e2e-windows\Run-E2E.ps1') -AgentDesktopBinary $exe -FixtureBinary $fixture *>&1 | Out-File -LiteralPath (Join-Path $OutDir 'suite.log') -Encoding utf8
$suite = $LASTEXITCODE
"$(& $stamp) suite exit=$suite" | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check *>&1 | Tee-Object -FilePath (Join-Path $OutDir 'run.log') -Append
if ($suite -eq 0) { exit 0 } else { exit 1 }
