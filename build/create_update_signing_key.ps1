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

function Find-OpenSsl {
    $cmd = Get-Command openssl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command openssl -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'),
        (Join-Path $env:ProgramFiles 'Git\mingw64\bin\openssl.exe'),
        'C:\Program Files\Git\usr\bin\openssl.exe',
        'C:\Program Files\Git\mingw64\bin\openssl.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'OpenSSL was not found. Install Git for Windows (including OpenSSL) and run this script again.'
}

function Invoke-OpenSsl([string]$OpenSsl, [string[]]$Arguments) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $OpenSsl
    $psi.Arguments = (($Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Could not start OpenSSL: $OpenSsl" }
    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        if ($process.ExitCode -ne 0) {
            throw "OpenSSL failed with exit code $($process.ExitCode): $stderr $stdout"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

$openssl = Find-OpenSsl
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("aurorafox-signing-{0}" -f [Guid]::NewGuid().ToString('N'))
$tempPrivate = Join-Path $tempDir 'update-private.pem'
$tempPublic = Join-Path $tempDir 'update-public.pem'
$tempPublicDer = Join-Path $tempDir 'update-public.der'
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    Invoke-OpenSsl $openssl @('genpkey','-algorithm','RSA','-pkeyopt',"rsa_keygen_bits:$Bits",'-out',$tempPrivate) | Out-Null
    Invoke-OpenSsl $openssl @('pkey','-in',$tempPrivate,'-check','-noout') | Out-Null
    Invoke-OpenSsl $openssl @('pkey','-in',$tempPrivate,'-pubout','-out',$tempPublic) | Out-Null
    Invoke-OpenSsl $openssl @('pkey','-pubin','-in',$tempPublic,'-outform','DER','-out',$tempPublicDer) | Out-Null

    if (-not (Test-Path -LiteralPath $tempPrivate) -or -not (Test-Path -LiteralPath $tempPublic)) {
        throw 'OpenSSL did not produce both update signing key files.'
    }

    Move-Item -LiteralPath $tempPrivate -Destination $privatePath
    Move-Item -LiteralPath $tempPublic -Destination $publicPath
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($privatePath)) | Set-Content -Path $privateBase64Path -Encoding ASCII -NoNewline

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($tempPublicDer)))).Replace('-', ':')
    } finally {
        $sha.Dispose()
    }
} catch {
    Remove-Item -LiteralPath $privatePath,$publicPath,$privateBase64Path -Force -ErrorAction SilentlyContinue
    throw
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
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
