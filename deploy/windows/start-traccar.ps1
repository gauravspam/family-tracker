# Windows dev: run Traccar in foreground. Ctrl+C to stop.
# Must run from C:\tools\traccar — it writes to a relative .\logs dir.
$ErrorActionPreference = 'Stop'
Set-Location 'C:\tools\traccar'
if (-not (Test-Path -LiteralPath '.\logs')) {
  New-Item -ItemType Directory -Path '.\logs' | Out-Null
}
java -jar tracker-server.jar conf\traccar.xml
