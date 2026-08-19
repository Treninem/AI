param(
    [int]$Bits = 4096
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$privateDir = Join-Path $root 'build/private'
$privatePath = Join-Path $privateDir 'aurora_update_signing_private.pem'
$privateBase64Path = Join-Path $privateDir 'AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64.txt'
$publicPath = Join-Path $root 'update/release_public.pub'

if ($Bits -lt 3072) { throw 'Use at least a 3072-bit RSA key' }
if (Test-Path $privatePath) {
    throw "Update signing private key already exists: $privatePath`nDo not regenerate it unless you intentionally rotate the update trust key."
}
if (Test-Path $publicPath) {
    throw "Pinned update public key already exists: $publicPath`nDo not overwrite it accidentally."
}

New-Item -ItemType Directory -Force -Path $privateDir,(Split-Path -Parent $publicPath) | Out-Null

function Write-Pem([string]$Label, [byte[]]$Bytes, [string]$Path) {
    $body = [Convert]::ToBase64String($Bytes, [Base64FormattingOptions]::InsertLineBreaks)
    $pem = "-----BEGIN $Label-----`n$body`n-----END $Label-----`n"
    [IO.File]::WriteAllText($Path, $pem, [Text.Encoding]::ASCII)
}

$rsa = [Security.Cryptography.RSA]::Create($Bits)
try {
    $private = $rsa.ExportPkcs8PrivateKey()
    $public = $rsa.ExportSubjectPublicKeyInfo()
    Write-Pem -Label 'PRIVATE KEY' -Bytes $private -Path $privatePath
    Write-Pem -Label 'PUBLIC KEY' -Bytes $public -Path $publicPath
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($privatePath)) | Set-Content -Path $privateBase64Path -Encoding ASCII -NoNewline

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([BitConverter]::ToString($sha.ComputeHash($public))).Replace('-', ':')
    } finally {
        $sha.Dispose()
    }
} finally {
    $rsa.Dispose()
}

Write-Host ''
Write-Host 'AuroraFox update signing key created.' -ForegroundColor Green
Write-Host "Pinned PUBLIC key (commit this file): $publicPath" -ForegroundColor Cyan
Write-Host "PRIVATE key (never commit): $privatePath" -ForegroundColor Yellow
Write-Host "Public key SHA-256 fingerprint: $fingerprint"
Write-Host ''
Write-Host 'Add this GitHub Actions repository secret:' -ForegroundColor Cyan
Write-Host "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64 = contents of $privateBase64Path"
Write-Host ''
Write-Host 'Back up the private key outside the repository. AuroraFox rejects update manifests that are not signed by the pinned public key.' -ForegroundColor Yellow
