[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HostName,
    [ValidateRange(1, 65535)][int]$Port = 22,
    [string]$UserName = 'aurorafox-backup',
    [Parameter(Mandatory)][string]$ServerHostKey,
    [string]$Destination = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'AuroraFox Backups'),
    [ValidateRange(1, 365)][int]$Retention = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$stateRoot = Join-Path $env:LOCALAPPDATA 'AuroraFox\ServerBackup'
$privateKey = Join-Path $stateRoot 'id_ed25519'
$knownHosts = Join-Path $stateRoot 'known_hosts'
$configPath = Join-Path $stateRoot 'config.json'
$sourceSyncScript = Join-Path $PSScriptRoot 'sync_server_backup.ps1'
$syncScript = Join-Path $stateRoot 'sync_server_backup.ps1'
if (-not (Test-Path -LiteralPath $sourceSyncScript -PathType Leaf)) {
    throw "AuroraFox backup synchronizer is missing: $sourceSyncScript"
}
if ($ServerHostKey -notmatch '\s(ssh-ed25519|ecdsa-sha2-nistp256|rsa-sha2-512|ssh-rsa)\s') {
    throw 'ServerHostKey must be a complete trusted known_hosts line copied from the REG.RU server console.'
}

New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceSyncScript -Destination $syncScript -Force
$sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)
if ($null -eq $sshKeygen) { $sshKeygen = Get-Command ssh-keygen -ErrorAction Stop }
if (-not (Test-Path -LiteralPath $privateKey -PathType Leaf)) {
    & $sshKeygen.Source -q -t ed25519 -N '' -C 'AuroraFox owner PC backup' -f $privateKey
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the AuroraFox PC backup SSH key.' }
}
$ServerHostKey.Trim() + "`n" | Set-Content -LiteralPath $knownHosts -Encoding ASCII -NoNewline
@{
    host_name = $HostName
    port = $Port
    user_name = $UserName
    private_key_path = $privateKey
    known_hosts_path = $knownHosts
    destination = $Destination
    retention = $Retention
} | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $stateRoot /inheritance:r /grant:r "$currentUser`:(OI)(CI)F" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to restrict AuroraFox backup credentials to the current Windows user.' }

$engine = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if ([string]::IsNullOrWhiteSpace($engine)) {
    $engine = (Get-Command powershell -ErrorAction Stop).Source
}
$arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$syncScript`" -ConfigPath `"$configPath`""
$action = New-ScheduledTaskAction -Execute $engine -Argument $arguments
$triggers = @(
    New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$task = New-ScheduledTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal
Register-ScheduledTask -TaskName 'AuroraFox Server Backup' -InputObject $task -Force | Out-Null

$publicKey = (Get-Content -LiteralPath ($privateKey + '.pub') -Raw).Trim()
Write-Output "AURORAFOX_BACKUP_CLIENT_KEY public_key=$publicKey"
& $engine -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $syncScript -ConfigPath $configPath
Write-Output "AURORAFOX_BACKUP_SCHEDULE_OK interval_minutes=5 destination=$Destination transport=sftp"

