$ErrorActionPreference = 'Stop'

Write-Host 'AuroraFox: checking Ollama...'
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    throw 'Ollama not found. Install Ollama first.'
}

$models = @(
    'qwen3:8b',
    'qwen3-vl:8b',
    'qwen3-coder:30b'
)

foreach ($model in $models) {
    Write-Host "Pulling $model..."
    ollama pull $model
    if ($LASTEXITCODE -ne 0) { throw "Failed to pull $model" }
}

Write-Host 'AuroraFox models are ready.'
Write-Host 'General: qwen3:8b'
Write-Host 'Vision/GUI: qwen3-vl:8b'
Write-Host 'Coding: qwen3-coder:30b'
