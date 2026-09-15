param(
    [ValidateSet('core','balanced','full')][string]$Profile = 'core',
    [string]$StateFile = '',
    [switch]$ForceEngine
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppRoot = Split-Path -Parent $Root
$CoreInstaller = Join-Path $AppRoot 'core_runtime\install_core.ps1'

function Set-Stage([string]$Name, [int]$Progress, [string]$Message, [hashtable]$Extra = @{}) {
    Write-Host ("[{0,3}%] {1}: {2}" -f $Progress, $Name, $Message) -ForegroundColor Cyan
    if (-not $StateFile) { return }
    $parent = Split-Path -Parent $StateFile
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $payload = @{
        stage = $Name
        progress = [Math]::Max(0, [Math]::Min(100, $Progress))
        message = $Message
        profile = $Profile
        ollama_required = $false
        model_managed_by_app = $true
        time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
    [IO.File]::WriteAllText($StateFile, ($payload | ConvertTo-Json -Compress -Depth 6), (New-Object Text.UTF8Encoding($false)))
}

try {
    Set-Stage 'core' 5 'Preparing AuroraFox Core Engine. Ollama is not required.'
    if (-not (Test-Path -LiteralPath $CoreInstaller)) {
        throw "AuroraFox Core installer not found: $CoreInstaller"
    }
    $coreState = if ($StateFile) { "$StateFile.core.json" } else { '' }
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$CoreInstaller)
    if ($coreState) { $args += @('-StateFile',$coreState) }
    if ($ForceEngine) { $args += '-Force' }
    & powershell @args
    if ($LASTEXITCODE -ne 0) { throw "AuroraFox Core Engine setup failed with code $LASTEXITCODE" }

    Set-Stage 'model' 92 'Core Engine is ready. GGUF model is managed by AuroraFox LocalModelManager and can be downloaded or imported in the application.' @{
        active_model = 'user://models/aurorafox-main.gguf'
        core_installer = $CoreInstaller
    }
    Set-Stage 'ready' 100 'AuroraFox Core bootstrap is ready without Ollama. Open Local AI settings to download or import a GGUF model.' @{
        active_model = 'user://models/aurorafox-main.gguf'
        ollama_required = $false
    }
    Write-Host 'AuroraFox Core bootstrap completed. Ollama was not installed or started.' -ForegroundColor Green
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}
