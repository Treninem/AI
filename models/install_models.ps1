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
        external_ai_required = $false
        model_managed_by_app = $true
        bundled_core_required = $true
        time = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
    [IO.File]::WriteAllText($StateFile, ($payload | ConvertTo-Json -Compress -Depth 6), (New-Object Text.UTF8Encoding($false)))
}

try {
    Set-Stage 'core' 5 'Preparing AuroraFox Core Engine. Ollama and external AI services are not required.'
    if (-not (Test-Path -LiteralPath $CoreInstaller)) {
        throw "AuroraFox Core installer not found: $CoreInstaller"
    }
    $coreState = if ($StateFile) { "$StateFile.core.json" } else { '' }
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$CoreInstaller)
    if ($coreState) { $args += @('-StateFile',$coreState) }
    if ($ForceEngine) { $args += '-Force' }
    & powershell @args
    if ($LASTEXITCODE -ne 0) { throw "AuroraFox Core Engine setup failed with code $LASTEXITCODE" }

    # This helper prepares the engine/bootstrap contract. Production Windows and
    # Android packages supply the pinned AuroraFox Core weights themselves; the
    # normal user is never asked to select, download or import a model.
    Set-Stage 'model' 92 'Core Engine is ready. AuroraFox application packages provide and manage the bundled AuroraFox Core weights automatically.' @{
        active_model = 'user://models/aurorafox-main.gguf'
        core_installer = $CoreInstaller
        model_source = 'bundled_aurorafox_core'
    }
    Set-Stage 'ready' 100 'AuroraFox Core bootstrap is ready without Ollama or external AI. Bundled Core weights are managed by the application.' @{
        active_model = 'user://models/aurorafox-main.gguf'
        model_source = 'bundled_aurorafox_core'
        ollama_required = $false
        external_ai_required = $false
    }
    Write-Host 'AuroraFox Core bootstrap completed. Ollama/external AI were not installed or started; application packages own the Core weights.' -ForegroundColor Green
} catch {
    Set-Stage 'error' 0 $_.Exception.Message
    throw
}