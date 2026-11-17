#Requires -Version 5.1
<#
    Before the exclusive Windows suite: is this process in an unlocked,
    signed-in session whose input reaches the desktop? Run it in the same
    context as the suite (the scheduled task in the user's session).

    - The input desktop must be "Default". A locked session shows the
      Winlogon desktop, which a user process cannot open, and SendInput
      then returns 0.
    - SendInput of a 1-pixel mouse move there and back must return 2
      (both events injected), and the last-input time must move.

    Exit 0 ready, 3 not ready. Changes nothing on the machine; the mouse
    moves one pixel and back.
#>
[CmdletBinding()]
param()

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class InteractiveInputCheck {
    [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformationW(IntPtr handle, int index, StringBuilder buffer, int length, out int needed);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr handle);
    public static string InputDesktop() {
        IntPtr handle = OpenInputDesktop(0, false, 0x0001);
        if (handle == IntPtr.Zero) return "unavailable (error " + Marshal.GetLastWin32Error() + ")";
        try {
            var name = new StringBuilder(256);
            int needed;
            return GetUserObjectInformationW(handle, 2, name, name.Capacity * 2, out needed) ? name.ToString() : "unnamed";
        } finally { CloseDesktop(handle); }
    }
    public static uint LastInput() {
        var info = new LASTINPUTINFO();
        info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        GetLastInputInfo(ref info);
        return info.dwTime;
    }
    public static uint NudgeMouse() {
        var inputs = new INPUT[2];
        inputs[0].type = 0; inputs[0].mi.dx = 1; inputs[0].mi.dwFlags = 0x0001;
        inputs[1].type = 0; inputs[1].mi.dx = -1; inputs[1].mi.dwFlags = 0x0001;
        return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }
}
'@

$session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
$desktop = [InteractiveInputCheck]::InputDesktop()
$before = [InteractiveInputCheck]::LastInput()
Start-Sleep -Milliseconds 100
$sent = [InteractiveInputCheck]::NudgeMouse()
Start-Sleep -Milliseconds 300
$after = [InteractiveInputCheck]::LastInput()
"session $session; input desktop: $desktop; SendInput injected: $sent of 2; last input moved: $($after -ne $before)"

if ($desktop -ne 'Default' -or $sent -ne 2 -or $after -eq $before) {
    'NOT READY: the session is locked or its input is blocked. Do not start the suite; someone has to unlock the session first.'
    exit 3
}
'READY'
exit 0
