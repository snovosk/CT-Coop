<#
 * Build
 * Purpose: builds ModCoop.dll and ModCoop.u in the right order, and survives UCC not exiting after a compile error.
 * Entry points: run by hand, see TESTING.md. -SkipDll, -SkipScript, -Tunnel, -TimeoutSeconds.
 * Logging: prints each step. UCC writes GameData\System\UCC.log.
 * State: the old ModCoop.u is kept as ModCoop.u.previous during the compile and put back if it fails.
 * Known limitations: Mod.u isn't rebuilt. Every compile changes the package GUID, so players need the same build.
#>
param(
	[switch]$SkipDll,
	[switch]$SkipScript,
	[switch]$Tunnel,
	[int]$TimeoutSeconds = 240
)

$ErrorActionPreference = "Stop"

# The user may be testing, a build would replace the files under the running game
if(@(Get-Process CT -ErrorAction SilentlyContinue).Count -gt 0) { throw "A game window is open, close it first." }

$ModCoop = Split-Path -Parent $PSScriptRoot
$Code    = Split-Path -Parent $ModCoop
$System  = Join-Path (Split-Path -Parent $Code) "GameData\System"

function Find-MSBuild
{
	$Vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if(!(Test-Path $Vswhere)) { throw "vswhere.exe not found, is Visual Studio installed?" }

	$Found = & $Vswhere -latest -version "[18.0," -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
	if(!$Found) { throw "MSBuild of Visual Studio 2026 not found" }
	return $Found
}

function Invoke-MSBuild($Project, $Platform)
{
	# The doubled backslash survives the quoting of a path with spaces
	& (Find-MSBuild) $Project "-p:Configuration=Release" "-p:Platform=$Platform" "-p:SolutionDir=$Code\\" -v:minimal -nologo
	if($LASTEXITCODE -ne 0) { throw "MSBuild failed: $Project" }
}

if(!$SkipDll)
{
	Write-Host "== ModCoop.dll"
	Invoke-MSBuild (Join-Path $ModCoop "ModCoop.vcxproj") "Win32"
}

if($Tunnel)
{
	Write-Host "== CoopTunnel"
	Invoke-MSBuild (Join-Path $ModCoop "CoopTunnel\CoopTunnel.vcxproj") "x64"
}

if(!$SkipScript)
{
	Write-Host "== ModCoop.u"

	$Package  = Join-Path $System "ModCoop.u"
	$Previous = "$Package.previous"
	$UccLog   = Join-Path $System "UCC.log"

	if(Test-Path $Package) { Move-Item $Package $Previous -Force }

	$Ucc = Start-Process -FilePath (Join-Path $System "UCC.exe") -ArgumentList "make", "-silent", "-ini=..\..\Code\UCC\UCC.ini" -WorkingDirectory $System -PassThru -WindowStyle Hidden
	$bExited = $Ucc.WaitForExit($TimeoutSeconds * 1000)

	if(!$bExited) { Stop-Process -Id $Ucc.Id -Force }

	$Errors = @(Select-String -LiteralPath $UccLog -Pattern '^Error|: Error' -ErrorAction SilentlyContinue | ForEach-Object Line)

	if(!(Test-Path $Package) -or $Errors.Count -gt 0)
	{
		$Errors | ForEach-Object { Write-Host $_ }
		if(Test-Path $Previous) { Move-Item $Previous $Package -Force }
		throw "UCC make failed (exited: $bExited), the previous ModCoop.u is back. See $UccLog"
	}

	if(Test-Path $Previous) { Remove-Item $Previous -Force }
	Write-Host "ModCoop.u built. If native fields or functions changed, run this again to build the DLL with the new header."
}

Write-Host "Done. This build has a new package GUID: every player needs these files."
