# Packs the logs of the game and the Steam tunnel into CoopLogs-<date>.zip next to this script.
# The names of the computer and the Windows user, Steam IDs and IP addresses are masked. Collect-Logs.bat starts it.
$Root = $PSScriptRoot
$Stage = Join-Path $env:TEMP ("CoopLogs-" + [guid]::NewGuid())
$Archive = Join-Path $Root ("CoopLogs-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".zip")
New-Item -ItemType Directory -Force $Stage | Out-Null

$Files = @()
$Files += Get-ChildItem (Join-Path $Root "System") -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(CT|CT-previous|SWRepublicCommando|CoopHost|CoopClient\d*)(-Sounds)?\.log$' }
$Files += Get-ChildItem (Join-Path $Root "CoopTunnel") -Filter "*.log" -File -ErrorAction SilentlyContinue

$Addresses = @{}

foreach($File in $Files)
{
	$Text = [IO.File]::ReadAllText($File.FullName)
	# The lines end with CRLF, the engine writes these names in its own way (no hyphens)
	$Text = $Text -replace '(?m)^Init: (Computer|User):[^\r\n]*', 'Init: $1: (removed)'
	$Text = $Text -replace [regex]::Escape($env:COMPUTERNAME), 'COMPUTER' -replace [regex]::Escape($env:COMPUTERNAME.Replace('-', '')), 'COMPUTER' -replace [regex]::Escape($env:USERNAME), 'USER'
	$Text = $Text -replace '\b7656\d{13}\b', 'STEAMID'
	# Loopback addresses stay, the tests and the relay use them. Others get a number that stays the same, so players can be told apart.
	$Text = [regex]::Replace($Text, '(?<![\d.])(?!127\.|0\.)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![\d.])', [Text.RegularExpressions.MatchEvaluator]{
		param($Match)
		if(!$Addresses.ContainsKey($Match.Value)) { $Addresses[$Match.Value] = "IP" + ($Addresses.Count + 1) }
		$Addresses[$Match.Value]
	})
	[IO.File]::WriteAllText((Join-Path $Stage $File.Name), $Text)
	Write-Host ("  " + $File.Name + "  " + $File.LastWriteTime)
}

if($Files.Count -eq 0)
{
	Write-Host "No logs found."
	exit 1
}

Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $Archive
Remove-Item $Stage -Recurse -Force
Write-Host ""
Write-Host "Send this file: $Archive"
Start-Process explorer.exe "/select,`"$Archive`""
