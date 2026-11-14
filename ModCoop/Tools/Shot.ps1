<#
 * Shot
 * Purpose: bursts of screenshots of every game window, for reports about what players see. A frame has to show the cause before a visual fix.
 * Entry points: run by hand while a test runs, see TESTING.md. -WaitLog with -WaitFor starts the burst when a marker appears in a log.
 * Logging: prints the folder it wrote to.
 * State: none. Files go to -OutDir, by default a folder in %TEMP%, never into the repository.
 * Known limitations: copies the screen, so a window that something else covers is skipped with a warning, otherwise the frame would show the other window.
 *   Only the center of the window is checked. RunTest doesn't arrange the windows, CoopTest.bat does.
#>
param(
	[int]$Count = 1,
	[double]$Interval = 0.5,
	[string]$WaitLog = "",
	[string]$WaitFor = "",
	[switch]$Front,     # Bring each game window to the front first; one still covered is drawn by itself (PrintWindow). Without it a covered window is skipped
	[int]$WaitSeconds = 120,
	[string]$OutDir = (Join-Path $env:TEMP ("CoopShots-" + (Get-Date -Format "yyyyMMdd-HHmmss")))
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public struct CoopRect { public int Left, Top, Right, Bottom; }
public struct CoopPoint { public int X, Y; }
public class CoopShotWin
{
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr Window, out CoopRect Rect);
	[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(CoopPoint Point);
	[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr Window, uint Flags);
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr Window);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr Window, IntPtr Dc, uint Flags);
}
"@
[CoopShotWin]::SetProcessDPIAware() | Out-Null

if($WaitLog -ne "")
{
	$Log   = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "GameData\System\$WaitLog"
	$Start = Get-Date

	while(!((Test-Path -LiteralPath $Log) -and (Select-String -LiteralPath $Log -Pattern $WaitFor -Quiet)))
	{
		if(((Get-Date) - $Start).TotalSeconds -gt $WaitSeconds) { throw "'$WaitFor' didn't appear in $WaitLog" }
		Start-Sleep -Milliseconds 100
	}
}

New-Item -ItemType Directory -Force $OutDir | Out-Null

# A game that is still loading has no window yet, even when the marker is in its log
$Start = Get-Date
while(@(Get-Process CT -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -eq 0 -and ((Get-Date) - $Start).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 100 }

for($Frame = 1; $Frame -le $Count; ++$Frame)
{
	$Window = 0

	foreach($Proc in Get-Process CT -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Sort-Object StartTime)
	{
		++$Window

		if($Front)
		{
			[CoopShotWin]::SetForegroundWindow($Proc.MainWindowHandle) | Out-Null
			Start-Sleep -Milliseconds 300
		}

		$Rect = New-Object CoopRect
		[CoopShotWin]::GetWindowRect($Proc.MainWindowHandle, [ref]$Rect) | Out-Null

		$Center = New-Object CoopPoint
		$Center.X = [int](($Rect.Left + $Rect.Right) / 2)
		$Center.Y = [int](($Rect.Top + $Rect.Bottom) / 2)
		$Covered = [CoopShotWin]::GetAncestor([CoopShotWin]::WindowFromPoint($Center), 2) -ne $Proc.MainWindowHandle # 2: GA_ROOT

		if($Covered -and !$Front)
		{
			Write-Warning "Window $Window is covered by another window, skipped"
			continue
		}

		$Bitmap   = New-Object Drawing.Bitmap ($Rect.Right - $Rect.Left), ($Rect.Bottom - $Rect.Top)
		$Graphics = [Drawing.Graphics]::FromImage($Bitmap)

		# Still covered with -Front (Windows only lets the foreground process change it): the window draws itself (PW_RENDERFULLCONTENT)
		if($Covered)
		{
			$Dc = $Graphics.GetHdc()
			[CoopShotWin]::PrintWindow($Proc.MainWindowHandle, $Dc, 2) | Out-Null
			$Graphics.ReleaseHdc($Dc)
		}
		else
		{
			$Graphics.CopyFromScreen($Rect.Left, $Rect.Top, 0, 0, $Bitmap.Size)
		}
		$Bitmap.Save((Join-Path $OutDir ("window{0}-frame{1:00}.png" -f $Window, $Frame)), [Drawing.Imaging.ImageFormat]::Png)
		$Graphics.Dispose()
		$Bitmap.Dispose()
	}

	if($Window -eq 0) { throw "No game window found" }
	if($Frame -lt $Count) { Start-Sleep -Milliseconds ([int]($Interval * 1000)) }
}

Write-Host "Saved to $OutDir"
