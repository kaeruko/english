$ErrorActionPreference = 'Stop'

$previewRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvRoot = Join-Path $previewRoot '.venv'
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'

Set-Location -LiteralPath $previewRoot

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host '初回セットアップ: Python仮想環境を作成しています…' -ForegroundColor Cyan
    python -m venv $venvRoot
}

$dependenciesReady = $false
try {
    & $venvPython -c 'import fastapi, uvicorn, faster_whisper' 2>$null
    $dependenciesReady = ($LASTEXITCODE -eq 0)
} catch {
    $dependenciesReady = $false
}

if (-not $dependenciesReady) {
    Write-Host '初回セットアップ: 必要なライブラリをインストールしています…' -ForegroundColor Cyan
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
            throw 'ローカルサーバーを起動できませんでした。'
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
        throw 'ローカルサーバーの起動がタイムアウトしました。'
    }

    Start-Process $url
    Write-Host ''
    Write-Host "English Replayを開きました: $url" -ForegroundColor Green
    Write-Host '終了するまでこのウィンドウは開いたままにしてください。' -ForegroundColor Yellow
    [void](Read-Host 'アプリを終了するにはEnterキーを押してください')
} finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id
    }
}
