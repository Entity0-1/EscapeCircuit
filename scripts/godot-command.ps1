function ConvertTo-NativeArgumentLine {
    param([Parameter(Mandatory)][string[]]$Values)

    $quoted = foreach ($value in $Values) {
        if ($value -match '[\s"]') {
            '"' + ($value -replace '"', '\"') + '"'
        }
        else {
            $value
        }
    }
    return $quoted -join ' '
}


function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$LogName
    )

    $logRoot = Join-Path $WorkingDirectory 'logs\automation'
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $stdoutPath = Join-Path $logRoot ($LogName + '.out.log')
    $stderrPath = Join-Path $logRoot ($LogName + '.err.log')
    $argumentLine = ConvertTo-NativeArgumentLine -Values $Arguments
    $process = Start-Process `
        -FilePath $Executable `
        -WorkingDirectory $WorkingDirectory `
        -ArgumentList $argumentLine `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if (Test-Path -LiteralPath $stdoutPath) {
        Get-Content -LiteralPath $stdoutPath | ForEach-Object { Write-Host $_ }
    }
    if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath | ForEach-Object { Write-Host $_ }
    }
    return $process.ExitCode
}


function Invoke-ProjectGodot {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string[]]$EngineArguments,
        [Parameter(Mandatory)][string]$LogName
    )

    $portable = Join-Path $ProjectRoot '.tools\Godot_v4.7.2-stable_win64.exe'
    if (Test-Path -LiteralPath $portable) {
        $godot = $portable
    }
    else {
        $command = Get-Command 'godot', 'godot4' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) {
            throw 'Godot 4.7.2 or a compatible Godot 4 executable was not found.'
        }
        $godot = $command.Source
    }
    return Invoke-CapturedProcess `
        -Executable $godot `
        -WorkingDirectory $ProjectRoot `
        -Arguments $EngineArguments `
        -LogName $LogName
}
