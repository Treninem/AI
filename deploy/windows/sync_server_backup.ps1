[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $env:LOCALAPPDATA 'AuroraFox\ServerBackup\config.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "AuroraFox backup configuration is missing: $ConfigPath"
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$hostName = [string]$config.host_name
$port = [int]$config.port
$userName = [string]$config.user_name
$privateKey = [string]$config.private_key_path
$knownHosts = [string]$config.known_hosts_path
$destination = [string]$config.destination
$retention = [Math]::Max(1, [int]$config.retention)
foreach ($required in @($privateKey, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "AuroraFox SFTP trust file is missing: $required"
    }
}

$sftp = (Get-Command sftp.exe -ErrorAction SilentlyContinue)
if ($null -eq $sftp) { $sftp = Get-Command sftp -ErrorAction Stop }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$temporaryRoot = Join-Path $destination ('.download-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
$batchPath = Join-Path $temporaryRoot 'sftp.batch'
@(
    "lcd `"$temporaryRoot`"",
    'get /exports/latest.zip',
    'get /exports/latest.sha256'
) | Set-Content -LiteralPath $batchPath -Encoding ASCII

try {
    $arguments = @(
        '-b', $batchPath,
        '-P', [string]$port,
        '-i', $privateKey,
        '-o', 'BatchMode=yes',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', "UserKnownHostsFile=$knownHosts",
        "$userName@$hostName"
    )
    $sftpOutput = @(& $sftp.Source @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $details = ($sftpOutput -join "`n")
        if ($details -match 'Permission denied|Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED') {
            throw "AuroraFox SFTP identity verification failed. $details"
        }
        Write-Output 'AURORAFOX_BACKUP_OFFLINE retry=scheduled'
        return
    }

    $archivePath = Join-Path $temporaryRoot 'latest.zip'
    $hashPath = Join-Path $temporaryRoot 'latest.sha256'
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $hashPath -PathType Leaf)) {
        throw 'AuroraFox SFTP snapshot is incomplete.'
    }
    $hashLine = (Get-Content -LiteralPath $hashPath -Raw).Trim()
    if ($hashLine -notmatch '^([a-fA-F0-9]{64})\s+latest\.zip$') {
        throw 'AuroraFox detached backup hash is invalid.'
    }
    $expectedSha = $Matches[1].ToLowerInvariant()
    $actualSha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha -ne $expectedSha) {
        throw 'AuroraFox server backup transfer hash mismatch.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $manifestEntry = $archive.GetEntry('manifest.json')
        if ($null -eq $manifestEntry) { throw 'AuroraFox server backup manifest is missing.' }
        $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.Encoding]::UTF8)
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if ([string]$manifest.schema -ne 'aurorafox.backup.v1') {
            throw 'AuroraFox server backup schema is unsupported.'
        }
        if ([bool]$manifest.credential_files_included) {
            throw 'AuroraFox server backup unexpectedly contains credential files.'
        }
        $backupId = [string]$manifest.backup_id
        if ($backupId -notmatch '^[A-Za-z0-9T-]{10,80}$') {
            throw 'AuroraFox server backup manifest has an invalid id.'
        }
    }
    finally { $archive.Dispose() }

    $finalPath = Join-Path $destination ("AuroraFox-Server-Backup-$backupId.zip")
    Move-Item -LiteralPath $archivePath -Destination $finalPath -Force
    Get-ChildItem -LiteralPath $destination -File -Filter 'AuroraFox-Server-Backup-*.zip' |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -Skip $retention |
        Remove-Item -Force
    Write-Output "AURORAFOX_BACKUP_OK path=$finalPath sha256=$actualSha transport=sftp"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

