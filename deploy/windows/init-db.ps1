# Fresh Windows DB setup (portable Postgres). Run once.
# Ubuntu uses Docker volumes — untouched by this script.
$ErrorActionPreference = 'Stop'
$PGBin = 'C:\tools\pgsql\bin'
$DataDir = 'C:\tools\pgsql\data'
$RepoRoot = (Get-Item "$PSScriptRoot\..\..").FullName

if (-not (Test-Path "$DataDir\PG_VERSION")) {
  & "$PGBin\initdb.exe" -D $DataDir -U postgres -A trust
}
& "$PGBin\pg_ctl.exe" -D $DataDir -l C:\tools\pgsql\logfile start
& "$PGBin\psql.exe" -U postgres -d postgres -f "$RepoRoot\deploy\docker\postgres-init\01_schemas.sql"
& "$PGBin\psql.exe" -U postgres -d postgres -f "$RepoRoot\deploy\docker\postgres-init\02_relay_schema.sql"
$env:PGOPTIONS = '-c search_path=relay'
try {
  & "$PGBin\psql.exe" -U postgres -d postgres -f "$RepoRoot\services\notify_relay\migrations\001_geofence_events.sql"
} finally {
  $env:PGOPTIONS = ''
}
'DB ready. Server left running.'
