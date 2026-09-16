$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$portable = Join-Path $projectRoot '.tools\Godot_v4.7.2-stable_win64.exe'
$godot = if (Test-Path -LiteralPath $portable) { $portable } else { 'godot' }

Push-Location $projectRoot
try {
    & $godot --path .
}
finally {
    Pop-Location
}

