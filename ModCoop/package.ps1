# Builds the release archive of the coop mod.
# The archive is meant to be extracted into the game's GameData directory.
# Usage (after 'build.bat release' and 'ucc make'):  powershell -ExecutionPolicy Bypass -File ModCoop\package.ps1
param([string]$Version = "1.3")

$ErrorActionPreference = "Stop"

$Code     = Split-Path -Parent $PSScriptRoot
$GameData = Join-Path (Split-Path -Parent $Code) "GameData"
$System   = Join-Path $GameData "System"
$Dist     = Join-Path $PSScriptRoot "Dist"
$Stage    = Join-Path $env:TEMP "ModCoopPackage"
$Archive  = Join-Path (Split-Path -Parent $Code) "SWRC-Coop-$Version.zip"

# Files from GameData\System that make up the mod
$SystemFiles = @(
	"CT.exe",
	"Mod.dll", "Mod.u", "Mod.int",
	"ModCoop.dll", "ModCoop.u"
)

if(Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $Stage "System") | Out-Null

foreach($File in $SystemFiles)
{
	$Source = Join-Path $System $File

	if(!(Test-Path $Source))
	{
		throw "Missing build artifact: $Source"
	}

	Copy-Item $Source (Join-Path $Stage "System")
}

# Property overrides used by Mod.dll
Copy-Item (Join-Path $System "PropertyOverrides") (Join-Path $Stage "System\PropertyOverrides") -Recurse

# Batch files and documentation go to the root of GameData
Get-ChildItem $Dist -File | Where-Object { $_.Extension -in ".bat", ".md" } | ForEach-Object { Copy-Item $_.FullName $Stage }

if(Test-Path $Archive) { Remove-Item $Archive -Force }

# Windows PowerShell 5.1 (Compress-Archive and ZipFile.CreateFromDirectory) stores paths with backslashes which some tools
# extract incorrectly, so the entries are added one by one with forward slashes and UTF-8 names (Cyrillic batch file names).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$Zip = [System.IO.Compression.ZipFile]::Open($Archive, [System.IO.Compression.ZipArchiveMode]::Create, [System.Text.Encoding]::UTF8)

try
{
	Get-ChildItem $Stage -Recurse -File | ForEach-Object {
		$EntryName = $_.FullName.Substring($Stage.Length + 1).Replace("\", "/")
		[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Zip, $_.FullName, $EntryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
	}
}
finally
{
	$Zip.Dispose()
}

Remove-Item $Stage -Recurse -Force
Write-Host "Created $Archive"
