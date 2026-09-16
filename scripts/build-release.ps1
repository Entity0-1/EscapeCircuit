$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'godot-command.ps1')
$buildRoot = Join-Path $projectRoot 'build\windows'
$webBuildRoot = Join-Path $projectRoot 'build\web'
$distRoot = Join-Path $projectRoot 'dist'
$windowsArchive = Join-Path $distRoot 'Escape-Circuit-windows-x86_64.zip'
$webArchive = Join-Path $distRoot 'Escape-Circuit-web.zip'
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA

Push-Location $projectRoot
try {
    & (Join-Path $PSScriptRoot 'check.ps1') -SkipPython

    $env:APPDATA = Join-Path $projectRoot '.godot-local\roaming'
    $env:LOCALAPPDATA = Join-Path $projectRoot '.godot-local\local'
    New-Item -ItemType Directory -Force -Path $buildRoot, $webBuildRoot, $distRoot | Out-Null
    $exitCode = Invoke-ProjectGodot -ProjectRoot $projectRoot -EngineArguments @('--headless', '--path', '.', '--export-release', 'Windows x86_64') -LogName 'export-windows'
    if ($exitCode -ne 0) {
        throw 'Godot export failed. Install the matching Godot 4.7.2 export templates and retry.'
    }

    $gameExecutable = Join-Path $buildRoot 'EscapeCircuit.exe'
    $exitCode = Invoke-CapturedProcess -Executable $gameExecutable -WorkingDirectory $projectRoot -Arguments @('--headless', '--', '--self-test') -LogName 'export-self-test'
    if ($exitCode -ne 0) { throw "Export self-test failed with exit code $exitCode" }

    $exitCode = Invoke-ProjectGodot -ProjectRoot $projectRoot -EngineArguments @('--headless', '--path', '.', '--export-release', 'Web') -LogName 'export-web'
    if ($exitCode -ne 0) {
        throw 'Godot Web export failed. Install the matching Godot 4.7.2 export templates and retry.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $webBuildRoot 'index.html'))) {
        throw 'Godot Web export did not create index.html.'
    }

    Copy-Item -LiteralPath 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md' -Destination $buildRoot -Force
    Copy-Item -LiteralPath 'LICENSE', 'THIRD_PARTY_NOTICES.md' -Destination $webBuildRoot -Force
    $webFiles = @(Get-ChildItem -LiteralPath $webBuildRoot -File -Recurse)
    $webTotalBytes = ($webFiles | Measure-Object -Property Length -Sum).Sum
    if ($webFiles.Count -gt 1000 -or $webTotalBytes -gt 500MB) {
        throw 'Web export exceeds itch.io HTML5 ZIP limits (1,000 files or 500 MB extracted).'
    }
    foreach ($webFile in $webFiles) {
        $relativeName = $webFile.FullName.Substring($webBuildRoot.Length + 1).Replace('\', '/')
        if ($webFile.Length -gt 200MB -or $relativeName.Length -gt 240) {
            throw "Web export exceeds itch.io HTML5 ZIP limits: $relativeName"
        }
    }
    Write-Host ('Web HTML5 limits verified: {0:N1} MiB extracted; largest file {1:N1} MiB' -f ($webTotalBytes / 1MB), (($webFiles | Measure-Object -Property Length -Maximum).Maximum / 1MB))
    if (Test-Path -LiteralPath $windowsArchive) {
        Remove-Item -LiteralPath $windowsArchive -Force
    }
    if (Test-Path -LiteralPath $webArchive) {
        Remove-Item -LiteralPath $webArchive -Force
    }
    Compress-Archive -Path (Join-Path $buildRoot '*') -DestinationPath $windowsArchive -CompressionLevel Optimal
    Compress-Archive -Path (Join-Path $webBuildRoot '*') -DestinationPath $webArchive -CompressionLevel Optimal
    Write-Host "Windows release created: $windowsArchive"
    Write-Host "Web release created: $webArchive"
}
finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    Pop-Location
}
