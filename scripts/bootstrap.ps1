param(
    [switch]$WithExportTemplates
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $projectRoot '.tools'
$godotArchive = Join-Path $toolsRoot 'Godot_v4.7.2-stable_win64.exe.zip'
$godotExecutable = Join-Path $toolsRoot 'Godot_v4.7.2-stable_win64.exe'
$templateArchive = Join-Path $toolsRoot 'Godot_v4.7.2-stable_export_templates.tpz'
$templateRoot = Join-Path $projectRoot '.godot-local\roaming\Godot\export_templates\4.7.2.stable'

$godotUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip'
$godotSha256 = '731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953'
$templateUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'
$templateSha256 = 'F298490B8D44D934BE425A5A65A51BF15F422428B229A06A6E11D9FFEA248011'

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        $partial = $Destination + '.partial'
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force
        }
        Write-Host "Downloading $Uri"
        Invoke-WebRequest -Uri $Uri -OutFile $partial
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $partial).Hash
        if ($actual -ne $ExpectedSha256) {
            Remove-Item -LiteralPath $partial -Force
            throw "Downloaded archive failed SHA-256 verification: $actual"
        }
        Move-Item -LiteralPath $partial -Destination $Destination
    }

    $existingHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash
    if ($existingHash -ne $ExpectedSha256) {
        throw "Refusing to use unverified archive $Destination. Expected $ExpectedSha256, found $existingHash."
    }
}

New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
Get-VerifiedArchive -Uri $godotUrl -Destination $godotArchive -ExpectedSha256 $godotSha256
if (-not (Test-Path -LiteralPath $godotExecutable)) {
    Expand-Archive -LiteralPath $godotArchive -DestinationPath $toolsRoot
}
Write-Host "Godot ready: $godotExecutable"

if ($WithExportTemplates) {
    Get-VerifiedArchive -Uri $templateUrl -Destination $templateArchive -ExpectedSha256 $templateSha256
    New-Item -ItemType Directory -Force -Path $templateRoot | Out-Null
    tar -xf $templateArchive -C $templateRoot --strip-components=1 `
        templates/windows_debug_x86_64.exe `
        templates/windows_release_x86_64.exe `
        templates/web_nothreads_debug.zip `
        templates/web_nothreads_release.zip
    Write-Host "Windows and Web export templates ready: $templateRoot"
}
