param(
    [switch]$SkipPython
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'godot-command.ps1')

$localGodot = Join-Path $projectRoot '.godot-local'
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$env:APPDATA = Join-Path $localGodot 'roaming'
$env:LOCALAPPDATA = Join-Path $localGodot 'local'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

Push-Location $projectRoot
try {
    $exitCode = Invoke-ProjectGodot -ProjectRoot $projectRoot -EngineArguments @('--headless', '--editor', '--path', '.', '--quit') -LogName 'import'
    if ($exitCode -ne 0) { throw "Godot import failed with exit code $exitCode" }
    $exitCode = Invoke-ProjectGodot -ProjectRoot $projectRoot -EngineArguments @('--headless', '--path', '.', '--script', 'tests/test_runner.gd') -LogName 'controller-tests'
    if ($exitCode -ne 0) { throw "Godot tests failed with exit code $exitCode" }
    $exitCode = Invoke-ProjectGodot -ProjectRoot $projectRoot -EngineArguments @('--headless', '--path', '.', '--script', 'tests/gameplay_test_runner.gd') -LogName 'gameplay-tests'
    if ($exitCode -ne 0) { throw "Godot gameplay tests failed with exit code $exitCode" }

    if (-not $SkipPython) {
        $env:APPDATA = $previousAppData
        $env:LOCALAPPDATA = $previousLocalAppData
        $env:UV_CACHE_DIR = Join-Path $projectRoot '.uv-cache'
        uv run --project brain ruff check brain
        if ($LASTEXITCODE -ne 0) { throw "Ruff failed with exit code $LASTEXITCODE" }
        uv run --project brain mypy --config-file brain/pyproject.toml brain/src
        if ($LASTEXITCODE -ne 0) { throw "mypy failed with exit code $LASTEXITCODE" }
        uv run --project brain pytest
        if ($LASTEXITCODE -ne 0) { throw "pytest failed with exit code $LASTEXITCODE" }
    }
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    Pop-Location
}
