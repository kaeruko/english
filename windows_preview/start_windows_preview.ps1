$ErrorActionPreference = 'Stop'

$previewRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvRoot = Join-Path $previewRoot '.venv'
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'

Set-Location -LiteralPath $previewRoot

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host 'First-time setup: creating a Python virtual environment...' -ForegroundColor Cyan
    python -m venv $venvRoot
}

$dependenciesReady = $false
try {
    & $venvPython -c 'import av, fastapi, uvicorn, faster_whisper' 2>$null
    $dependenciesReady = ($LASTEXITCODE -eq 0)
} catch {
    $dependenciesReady = $false
}

if (-not $dependenciesReady) {
    Write-Host 'First-time setup: installing required packages...' -ForegroundColor Cyan
    & $venvPython -m pip install --upgrade pip
    & $venvPython -m pip install -r (Join-Path $previewRoot 'requirements.txt')
}

$port = 8765
$serverArguments = @(
    '-m', 'uvicorn', 'app:app',
    '--host', '127.0.0.1',
    '--port', $port.ToString()
)

$processParameters = @{
    FilePath = $venvPython
    ArgumentList = $serverArguments
    WorkingDirectory = $previewRoot
    WindowStyle = 'Hidden'
    PassThru = $true
}
$server = Start-Process @processParameters

try {
    $url = "http://127.0.0.1:$port"
    $started = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ($server.HasExited) {
            throw 'The local server failed to start.'
        }
        try {
            $health = Invoke-RestMethod -Uri "$url/api/health" -TimeoutSec 1
            if ($health.ok) {
                $started = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }

    if (-not $started) {
        throw 'Timed out while starting the local server.'
    }

    Start-Process $url
    Write-Host ''
    Write-Host "English Replay is open: $url" -ForegroundColor Green
    Write-Host 'Keep this window open while using the app.' -ForegroundColor Yellow
    [void](Read-Host 'Press Enter to stop the app')
} finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}
