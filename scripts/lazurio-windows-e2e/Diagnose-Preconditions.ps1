#Requires -Version 5.1
<#
    Runs the exclusive Windows suite from a copy of one extracted bundle in
    which only the context-choice leg of tests/e2e-windows/scenarios/
    Preconditions.ps1 reports what it otherwise swallows: each attempt's
    exception (which step failed and with which error code), the popup
    window id it picked, and every window of the fixture's process after a
    failed attempt. The original bundle is not touched.

    The suite then runs as usual: if Preconditions aborts, it ends after
    about 2 minutes; if Preconditions passes on this machine, the whole
    suite runs on (15 to 25 minutes, the same desktop effects as
    Invoke-BundleSuite.ps1). The display and the system are kept on for the
    run, and the input check runs first.

    Usage, in the signed-in user's session:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File Diagnose-Preconditions.ps1 -BundleRoot C:\e2e\candidate -OutDir C:\e2e\diag-preconditions
    Exit: the suite's own exit code; 3 the session was not ready; 4 the
    leg to instrument was not found in this bundle.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [Parameter(Mandatory = $true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'

$BundleRoot = (Resolve-Path -LiteralPath $BundleRoot).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$log = Join-Path $OutDir 'run.log'
function Write-RunLog([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $log -Value $Text -Encoding UTF8
}
function Stamp { (Get-Date).ToUniversalTime().ToString('o') }

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class DiagPreconditionsAwake {
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
'@
$awake = [DiagPreconditionsAwake]::SetThreadExecutionState([uint32]2147483651)
Write-RunLog "$(Stamp) keep awake: $(if ($awake -ne 0) { 'on' } else { 'refused' })"

$check = Join-Path $BundleRoot 'Test-InteractiveInput.ps1'
$text = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check 2>&1 | Out-String
$ready = $LASTEXITCODE
Write-RunLog $text.TrimEnd()
if ($ready -ne 0) { exit 3 }

$copy = Join-Path $OutDir 'bundle'
if (Test-Path -LiteralPath $copy) { throw "$copy exists already; choose a new -OutDir" }
Copy-Item -Recurse -LiteralPath $BundleRoot -Destination $copy
Get-ChildItem -LiteralPath $copy -Recurse -File | Unblock-File

$scenario = Join-Path $copy 'tests\e2e-windows\scenarios\Preconditions.ps1'
$source = [IO.File]::ReadAllText($scenario)
$loopHead = "for (`$attempt = 1; `$attempt -le 3 -and -not `$choice; `$attempt++) {`r`n                try {"
$loopHeadLf = $loopHead -replace "`r`n", "`n"
$swallow = "} catch { }`r`n                if (-not `$choice) { Start-Sleep -Milliseconds 500 }"
$swallowLf = $swallow -replace "`r`n", "`n"
$nl = if ($source.Contains($loopHead)) { "`r`n" } elseif ($source.Contains($loopHeadLf)) { "`n" } else { $null }
if ($null -eq $nl -or -not ($source.Contains($swallow) -or $source.Contains($swallowLf))) {
    Write-RunLog "$(Stamp) the context-choice leg was not found as expected in $scenario; nothing ran"
    exit 4
}
$head = if ($nl -eq "`r`n") { $loopHead } else { $loopHeadLf }
$tail = if ($nl -eq "`r`n") { $swallow } else { $swallowLf }
$newHead = $head.Replace('try {', "`$popupWindowId = `$null$nl                try {")
$newTail = (@(
    "} catch { Write-Host (""DIAG context-choice attempt `${attempt}: "" + `$_.Exception.Message) }",
    "                if (-not `$choice) {",
    "                    Write-Host (""DIAG context-choice attempt `${attempt}: popupWindowId='"" + `$popupWindowId + ""'"")",
    "                    try {",
    "                        `$lw = Invoke-AgentDesktop -Arguments @('list-windows')",
    "                        foreach (`$w in @(`$lw['data'])) {",
    "                            if ([string]`$w['app_name'] -like 'AgentDeskFixture*') {",
    "                                Write-Host (""DIAG window id="" + `$w['id'] + "" title='"" + `$w['title'] + ""' visible="" + `$w['visible'] + "" focused="" + `$w['is_focused'] + "" bounds="" + (`$w['bounds'] | ConvertTo-Json -Compress))",
    "                            }",
    "                        }",
    "                    } catch { Write-Host (""DIAG list-windows failed: "" + `$_.Exception.Message) }",
    "                    Start-Sleep -Milliseconds 500",
    "                }"
) -join $nl)
$patched = $source.Replace($head, $newHead).Replace($tail, $newTail)
[IO.File]::WriteAllText($scenario, $patched, (New-Object System.Text.UTF8Encoding $true))
Write-RunLog "$(Stamp) instrumented the context-choice leg in the copy at $copy"

$exe = Join-Path $copy 'target\release\agent-desktop.exe'
$fixture = Join-Path $copy 'tests\fixture-app-windows\build\AgentDeskFixture.exe'
Write-RunLog "$(Stamp) live suite from the copy"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $copy 'tests\e2e-windows\Run-E2E.ps1') -AgentDesktopBinary $exe -FixtureBinary $fixture *>&1 | Out-File -LiteralPath (Join-Path $OutDir 'suite.log') -Encoding utf8
$suite = $LASTEXITCODE
Write-RunLog "$(Stamp) suite exit=$suite"
$diag = @(Select-String -LiteralPath (Join-Path $OutDir 'suite.log') -Pattern '^DIAG|aborting|running scenario' | ForEach-Object { $_.Line })
Set-Content -LiteralPath (Join-Path $OutDir 'diag-lines.txt') -Value $diag -Encoding UTF8
Write-RunLog "$(Stamp) $($diag.Count) DIAG and scenario lines in diag-lines.txt"
exit $suite
