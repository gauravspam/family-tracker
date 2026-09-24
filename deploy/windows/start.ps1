# Windows dev start: portable Postgres + Go relay. Ctrl+C stops the relay.
# Ubuntu flow (deploy/setup.sh, .env.relay, relay.txt) is untouched.
$ErrorActionPreference = 'Stop'
$PGBin = 'C:\tools\pgsql\bin'
$DataDir = 'C:\tools\pgsql\data'
$RepoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
$env:PATH = "C:\tools\go\bin;$env:PATH"

& "$PGBin\pg_ctl.exe" -D $DataDir status 2>$null
if ($LASTEXITCODE -ne 0) {
  & "$PGBin\pg_ctl.exe" -D $DataDir -l C:\tools\pgsql\logfile start
}

try {
  (New-Object Net.Sockets.TcpClient).Connect('127.0.0.1', 8082)
} catch {
  'NOTE: nothing on localhost:8082 — start Traccar first, e.g.:'
  '  java -jar C:\tools\traccar\tracker-server.jar C:\tools\traccar\conf\traccar.xml'
  '  (copy deploy\traccar\traccar.windows.xml to C:\tools\traccar\conf\traccar.xml)'
}

Get-Content "$RepoRoot\.env.relay.windows" | ForEach-Object {
  if ($_ -match '^\s*([^#\s][^=]*)=(.*)$') {
    [Environment]::SetEnvironmentVariable(
      $Matches[1].Trim(), $Matches[2].Trim().Trim("'").Trim('"'), 'Process')
  }
}
Set-Location "$RepoRoot\services\notify_relay"
go run ./cmd/server
