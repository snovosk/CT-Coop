<#
 * RunTest
 * Purpose: an automated co-op run on one PC: a host and clients in windows, a summary of their logs, and no test settings left behind.
 * Entry points: run by hand, see TESTING.md. GameData\System\CoopTest.bat is the interactive version for playing.
 * Logging: CoopHost.log and CoopClient<n>.log in GameData\System. Exit code 1 when a client didn't join or a log has a crash.
 * State: writes SquadAssignmentList in Save\ModCoop.ini and always clears it at the end.
 * Known limitations: all clients share 127.0.0.1. Refuses to start while another game window is open. Don't press Alt+Enter in the windows.
#>
param(
	[string]$Map = "GEO_01A",
	[ValidateRange(0, 3)][int]$Clients = 1,
	[string]$Test = "",
	[int]$Delay = 10,
	[string]$Options = "",       # More URL options of the host, e.g. "?CoopTestCause=ActivateShield"
	[string[]]$Members = @(),    # Bind clients to members in order, e.g. Commando62Delta, Commando40Delta
	[int]$Seconds = 90
)

$ErrorActionPreference = "Stop"

$GameData = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "GameData"
$System   = Join-Path $GameData "System"
$Ini      = Join-Path $GameData "Save\ModCoop.ini"
$Exe      = Join-Path $System "CT.exe"

function Set-Assignments($Value)
{
	if(!(Test-Path -LiteralPath $Ini)) { return }

	$Lines = @(Get-Content -LiteralPath $Ini)
	for($i = 0; $i -lt $Lines.Count; ++$i)
	{
		if($Lines[$i] -like "SquadAssignmentList=*") { $Lines[$i] = "SquadAssignmentList=$Value" }
	}
	[IO.File]::WriteAllText($Ini, (($Lines -join "`r`n") + "`r`n"))
}

function Test-LogHas($Name, $Pattern)
{
	$File = Join-Path $System $Name
	return (Test-Path -LiteralPath $File) -and (Select-String -LiteralPath $File -Pattern $Pattern -Quiet)
}

if(@(Get-Process CT -ErrorAction SilentlyContinue).Count -gt 0) { throw "A game window is already open, close it first." }

$Assign = ""
for($i = 0; $i -lt $Members.Count; ++$i) { $Assign += "127.0.0.1/Client$($i + 1)=CTCharacters.$($Members[$i])|" }

$Url = "${Map}?game=ModCoop.CoopGame?listen"
if($Options -notmatch '\?MaxPlayers=') { $Url += "?MaxPlayers=4" } # The first value of an option counts
if($Members.Count -gt 0) { $Url += "?CoopFixedSquad=1" }
if($Test -ne "") { $Url += "?CoopTest=${Test}?CoopTestDelay=${Delay}" } # Braces: PowerShell takes ? as a part of a variable name
$Url += $Options

$Common = "-windowed -forcelogflush -CoopNoSetup"
$Procs  = @()

# The logs of the last run may be the user's, keep them
$OldLogs = @(Get-ChildItem -LiteralPath $System -File | Where-Object { $_.Name -match '^(CT|SWRepublicCommando|Coop(Host|Client\d*))\.log$' })
if($OldLogs.Count -gt 0)
{
	$Backup = Join-Path $GameData ("Save\CoopTestLogs-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
	New-Item -ItemType Directory -Force $Backup | Out-Null
	$OldLogs | Copy-Item -Destination $Backup
	Write-Host "Previous logs saved to $Backup"
}
$OldLogs | Where-Object { $_.Name -like "Coop*" } | Remove-Item

try
{
	Set-Assignments $Assign

	$Procs += Start-Process -FilePath $Exe -ArgumentList "$Url $Common LOG=CoopHost.log" -WorkingDirectory $System -PassThru
	Write-Host "Host: $Url"

	$Start = Get-Date
	while(!(Test-LogHas "CoopHost.log" "Exiting LoadMap") -and ((Get-Date) - $Start).TotalSeconds -lt 90) { Start-Sleep -Milliseconds 500 }
	Start-Sleep 2

	for($i = 1; $i -le $Clients; ++$i)
	{
		# Each client has its own user settings, so the test names stay out of the player's User.ini
		Copy-Item (Join-Path $System "User.ini") (Join-Path $System "CoopTestUser$i.ini") -Force
		$Procs += Start-Process -FilePath $Exe -ArgumentList "127.0.0.1?Name=Client$i $Common USERINI=CoopTestUser$i.ini LOG=CoopClient$i.log" -WorkingDirectory $System -PassThru
		Start-Sleep 2
	}

	$Start = Get-Date
	while(((Get-Date) - $Start).TotalSeconds -lt $Seconds -and @($Procs | Where-Object { !$_.HasExited }).Count -eq $Procs.Count) { Start-Sleep 1 }
}
finally
{
	$Procs | Where-Object { !$_.HasExited } | Stop-Process -Force
	Start-Sleep 1
	Set-Assignments ""
	Get-ChildItem -LiteralPath $System -File -Filter "CoopTestUser*.ini" | Remove-Item
}

$bFailed = $false

foreach($Name in @("CoopHost.log") + @(1..$Clients | Where-Object { $_ -gt 0 } | ForEach-Object { "CoopClient$_.log" }))
{
	$File    = Join-Path $System $Name
	$Crashes = @(Select-String -LiteralPath $File -Pattern 'General protection|Assertion failed|Caught a crash|appError called' -ErrorAction SilentlyContinue)
	Write-Host "== $Name, crash lines: $($Crashes.Count)"
	$Crashes | Select-Object -First 5 | ForEach-Object { Write-Host $_.Line }
	if($Crashes.Count -gt 0) { $bFailed = $true }

	if($Name -like "CoopClient*" -and !(Test-LogHas $Name "Joined coop host"))
	{
		Write-Host "This client didn't join."
		$bFailed = $true
	}

	Select-String -LiteralPath $File -Pattern 'CoopTest:' -ErrorAction SilentlyContinue | Select-Object -Last 12 | ForEach-Object { Write-Host $_.Line }
}

if($bFailed) { Write-Host "RESULT: FAILED"; exit 1 }
Write-Host "RESULT: no crash, everybody joined. This says nothing about the scenario itself: read the CoopTest lines."
