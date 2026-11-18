#Requires -Version 5.1
<#
    Diagnoses the Preconditions abort "staged id 'context-choice' did not
    resolve while its surface (context-target right-click) was open" on one
    extracted bundle (agent-desktop-e2e-<label>).

    It repeats, step by step, what tests/e2e-windows/scenarios/Preconditions.ps1
    does for context-choice, but records every answer instead of swallowing
    it: the fixture's windows, context-target's bounds, focus-window, the
    headed right-click, the foreground window, every window of the fixture's
    process after the click (with its snapshot), a search for context-choice
    in each, and screenshots before and after the click.

    It starts its own fixture and stops only that process (by its PID). The
    engine's references go to a private HOME under -OutDir. The mouse moves
    and right-clicks once per attempt on the fixture's context-target; Escape
    closes the menu afterwards. Nothing else on the machine is changed.

    Usage, in the signed-in user's session:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File Diagnose-ContextMenu.ps1 -BundleRoot C:\e2e\candidate -OutDir C:\e2e\diag-candidate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$Attempts = 2
)
# Diagnostics: every answer is recorded, nothing stops the run early.
$ErrorActionPreference = 'Continue'

$BundleRoot = (Resolve-Path -LiteralPath $BundleRoot).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$exe = Join-Path $BundleRoot 'target\release\agent-desktop.exe'
$fixtureExe = Join-Path $BundleRoot 'tests\fixture-app-windows\build\AgentDeskFixture.exe'
$log = Join-Path $OutDir 'diag.log'
$engineHome = Join-Path $OutDir 'home'
New-Item -ItemType Directory -Force -Path $engineHome | Out-Null
$env:HOME = $engineHome

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DiagNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
    public static string Describe(IntPtr h) {
        var t = new StringBuilder(256); GetWindowText(h, t, 256);
        var c = new StringBuilder(256); GetClassName(h, c, 256);
        uint pid; GetWindowThreadProcessId(h, out pid);
        return "hwnd=" + h.ToInt64() + " pid=" + pid + " class='" + c + "' title='" + t + "'";
    }
}
'@

function Stamp { (Get-Date).ToUniversalTime().ToString('o') }
function Write-Diag([string]$Text) {
    Write-Host $Text
    Add-Content -LiteralPath $log -Value $Text -Encoding UTF8
}
function Invoke-Engine([string[]]$Arguments, [string]$SaveAs) {
    $out = & $exe @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($SaveAs) { Set-Content -LiteralPath (Join-Path $OutDir $SaveAs) -Value $out -Encoding UTF8 }
    $short = if ($out.Length -gt 1500) { $out.Substring(0, 1500) + ' ...(full text in ' + $SaveAs + ')' } else { $out.Trim() }
    Write-Diag "$(Stamp) agent-desktop $($Arguments -join ' ') -> exit $code`n$short"
    try { return ($out | ConvertFrom-Json) } catch { return $null }
}
function Save-Screen([string]$Name) {
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path $OutDir $Name), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    Write-Diag "$(Stamp) screenshot $Name"
}
function Get-Foreground { [DiagNative]::Describe([DiagNative]::GetForegroundWindow()) }

$os = Get-CimInstance Win32_OperatingSystem
Write-Diag "$(Stamp) $($os.Caption) $($os.Version) build $($os.BuildNumber); session $([System.Diagnostics.Process]::GetCurrentProcess().SessionId); system DPI $([DiagNative]::GetDpiForSystem())"
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
    Write-Diag "screen $($screen.DeviceName) bounds $($screen.Bounds) working area $($screen.WorkingArea) primary $($screen.Primary)"
}
Write-Diag "bundle: $((Get-Content -LiteralPath (Join-Path $BundleRoot 'BUNDLE.txt')) -join ' | ')"
Invoke-Engine @('version') | Out-Null

$fixture = $null
try {
    $env:AGENT_DESKTOP_FIXTURE_NO_ACTIVATE = '1'
    $fixture = Start-Process -FilePath $fixtureExe -PassThru
    Remove-Item Env:\AGENT_DESKTOP_FIXTURE_NO_ACTIVATE
    Write-Diag "$(Stamp) fixture started, pid $($fixture.Id)"

    $mainId = $null
    for ($i = 0; $i -lt 50 -and -not $mainId; $i++) {
        Start-Sleep -Milliseconds 300
        $windows = $null
        try { $windows = (& $exe list-windows 2>$null | Out-String | ConvertFrom-Json) } catch { }
        if ($windows -and $windows.ok) {
            $hit = @($windows.data | Where-Object { $_.title -eq 'AgentDeskFixture' })
            if ($hit.Count -ge 1) { $mainId = [string]$hit[0].id }
        }
    }
    if (-not $mainId) { Write-Diag "$(Stamp) the main fixture window never appeared in list-windows"; Invoke-Engine @('list-windows') 'list-windows-start.json' | Out-Null; exit 2 }
    Write-Diag "$(Stamp) main fixture window id $mainId; foreground: $(Get-Foreground)"
    Invoke-Engine @('list-windows') 'list-windows-before.json' | Out-Null
    Invoke-Engine @('snapshot', '--window-id', $mainId, '--include-bounds') 'snapshot-main.json' | Out-Null

    $found = Invoke-Engine @('find', '--first', '--window-id', $mainId, '--native-id', 'context-target') 'find-context-target.json'
    if (-not $found -or -not $found.ok -or -not $found.data.match) { Write-Diag "$(Stamp) context-target not found"; exit 2 }
    $ref = [string]$found.data.match.ref_id
    Invoke-Engine @('scroll-to', $ref) 'scroll-to.json' | Out-Null

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-Diag "`n$(Stamp) ===== attempt $attempt ====="
        Invoke-Engine @('focus-window', '--window-id', $mainId) "focus-window-$attempt.json" | Out-Null
        Write-Diag "$(Stamp) foreground after focus-window: $(Get-Foreground)"
        Save-Screen "screen-$attempt-before-right-click.png"
        Invoke-Engine @('--headed', 'right-click', $ref) "right-click-$attempt.json" | Out-Null
        Start-Sleep -Milliseconds 400
        Write-Diag "$(Stamp) foreground after right-click: $(Get-Foreground)"
        Save-Screen "screen-$attempt-after-right-click.png"
        $after = Invoke-Engine @('list-windows') "list-windows-$attempt-after.json"
        $own = @()
        if ($after -and $after.ok) {
            $own = @($after.data | Where-Object { $_.app_name -like 'AgentDeskFixture*' -or $_.pid -eq $fixture.Id })
            foreach ($w in $own) { Write-Diag "fixture window: $($w | ConvertTo-Json -Compress -Depth 4)" }
            $blank = @($own | Where-Object { $_.title -eq '' -and $_.visible -eq $true })
            Write-Diag "$(Stamp) windows the harness would take as the popup (app_name AgentDeskFixture.exe, blank title, visible): $(@($blank | Where-Object { $_.app_name -eq 'AgentDeskFixture.exe' }).Count)"
        }
        foreach ($w in $own) {
            if ([string]$w.id -eq $mainId) { continue }
            Invoke-Engine @('snapshot', '--window-id', [string]$w.id, '--include-bounds') "snapshot-$attempt-window-$($w.id).json" | Out-Null
            Invoke-Engine @('find', '--first', '--window-id', [string]$w.id, '--native-id', 'context-choice') "find-context-choice-$attempt-window-$($w.id).json" | Out-Null
        }
        Invoke-Engine @('find', '--first', '--app', 'AgentDeskFixture.exe', '--native-id', 'context-choice') "find-context-choice-$attempt-app.json" | Out-Null
        Invoke-Engine @('--headed', 'press', 'escape', '--app', 'AgentDeskFixture.exe') "escape-$attempt.json" | Out-Null
        Start-Sleep -Milliseconds 500
    }
} finally {
    if ($fixture -and -not $fixture.HasExited) {
        Stop-Process -Id $fixture.Id -Force
        Write-Diag "$(Stamp) fixture pid $($fixture.Id) stopped"
    }
}
Write-Diag "$(Stamp) done; results in $OutDir"
exit 0
