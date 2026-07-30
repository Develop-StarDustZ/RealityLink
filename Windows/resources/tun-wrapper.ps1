param(
    [Parameter(Mandatory=$true)][string]$CorePath,
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [Parameter(Mandatory=$true)][string]$StdoutPath,
    [Parameter(Mandatory=$true)][string]$StderrPath,
    [Parameter(Mandatory=$true)][string]$PIDPath,
    [Parameter(Mandatory=$true)][string]$StopPath,
    [Parameter(Mandatory=$true)][string]$ReloadPath
)

$ErrorActionPreference = 'Stop'
$secureDirectory = Join-Path $env:ProgramData ("RealityLink\runtime-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $secureDirectory -Force | Out-Null
& icacls.exe $secureDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot secure the temporary sing-box directory' }
$secureCore = Join-Path $secureDirectory 'sing-box.exe'
Copy-Item -LiteralPath $CorePath -Destination $secureCore
$child = $null
$logChecks = 0

function Start-Core {
    Remove-Item -LiteralPath $StdoutPath, $StderrPath -Force -ErrorAction SilentlyContinue
    $script:child = Start-Process -FilePath $secureCore `
        -ArgumentList @('run', '-c', ('"{0}"' -f $ConfigPath)) `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath `
        -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $PIDPath -Value $script:child.Id -Encoding Ascii
}

function Stop-Core {
    if ($null -ne $script:child -and -not $script:child.HasExited) {
        Stop-Process -Id $script:child.Id -ErrorAction SilentlyContinue
        $script:child.WaitForExit(5000) | Out-Null
    }
}

try {
    Remove-Item -LiteralPath $StopPath, $ReloadPath -Force -ErrorAction SilentlyContinue
    Start-Core
    while ($true) {
        if (Test-Path -LiteralPath $StopPath) { Stop-Core; exit 0 }
        if (Test-Path -LiteralPath $ReloadPath) {
            Remove-Item -LiteralPath $ReloadPath -Force
            Stop-Core
            Start-Core
        }
        if ($script:child.HasExited) { exit $script:child.ExitCode }
        $logChecks++
        if ($logChecks -ge 20) {
            $logChecks = 0
            $logSize = 0
            foreach ($logPath in @($StdoutPath, $StderrPath)) {
                if (Test-Path -LiteralPath $logPath) { $logSize += (Get-Item -LiteralPath $logPath).Length }
            }
            if ($logSize -gt 5MB) {
                Stop-Core
                Start-Core
            }
        }
        Start-Sleep -Milliseconds 250
    }
} finally {
    Stop-Core
    Remove-Item -LiteralPath $secureDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
