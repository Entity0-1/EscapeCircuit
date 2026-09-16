$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$portable = Join-Path $projectRoot '.tools\Godot_v4.7.2-stable_win64.exe'
$godot = if (Test-Path -LiteralPath $portable) { $portable } else { 'godot' }
$brainLog = Join-Path $projectRoot 'logs\brain-service.log'
$brainErrorLog = Join-Path $projectRoot 'logs\brain-service.error.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $brainLog) | Out-Null

Push-Location $projectRoot
try {
    $brainProcess = Start-Process `
        -FilePath 'uv' `
        -ArgumentList @('run', '--project', 'brain', 'escape-circuit-brain') `
        -RedirectStandardOutput $brainLog `
        -RedirectStandardError $brainErrorLog `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Milliseconds 800
    & $godot --path .
}
finally {
    if ($brainProcess -and -not $brainProcess.HasExited) {
        Stop-Process -Id $brainProcess.Id
    }
    Pop-Location
}

