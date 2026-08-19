param(
    [string]$Alias = "aurorafox-release",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $OutputDir) { $OutputDir = Join-Path $root "build/private" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) { throw "keytool не найден. Установи JDK 17 и запусти скрипт снова." }

$keystore = Join-Path $OutputDir "aurorafox-release.keystore"
if (Test-Path $keystore) {
    throw "Ключ уже существует: $keystore`nНе перегенерируй его: Android-обновления должны всегда подписываться тем же ключом."
}

$passwordSecure = Read-Host "Придумай пароль для Android release key (сохрани его отдельно)" -AsSecureString
$confirmSecure = Read-Host "Повтори пароль" -AsSecureString

function Reveal-SecureString([Security.SecureString]$Value) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$password = Reveal-SecureString $passwordSecure
$confirm = Reveal-SecureString $confirmSecure
if ([string]::IsNullOrWhiteSpace($password)) { throw "Пароль не может быть пустым" }
if ($password -ne $confirm) { throw "Пароли не совпадают" }
if ($password.Length -lt 8) { throw "Используй пароль минимум из 8 символов" }

try {
    $env:AURORAFOX_KEYSTORE_PASSWORD_TEMP = $password
    & $keytool.Source -genkeypair `
        -keystore $keystore `
        -alias $Alias `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname "CN=AuroraFox, OU=Release, O=AuroraFox, C=RU" `
        -storepass:env AURORAFOX_KEYSTORE_PASSWORD_TEMP `
        -keypass:env AURORAFOX_KEYSTORE_PASSWORD_TEMP
    if ($LASTEXITCODE -ne 0) { throw "keytool завершился с кодом $LASTEXITCODE" }
} finally {
    Remove-Item Env:AURORAFOX_KEYSTORE_PASSWORD_TEMP -ErrorAction SilentlyContinue
    $password = $null
    $confirm = $null
}

$b64Path = Join-Path $OutputDir "AURORA_ANDROID_KEYSTORE_BASE64.txt"
$aliasPath = Join-Path $OutputDir "AURORA_ANDROID_KEYSTORE_USER.txt"
[Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore)) | Set-Content -Path $b64Path -Encoding ASCII -NoNewline
$Alias | Set-Content -Path $aliasPath -Encoding ASCII -NoNewline

Write-Host "" 
Write-Host "Android release key создан." -ForegroundColor Green
Write-Host "ВАЖНО: сделай резервную копию файла и пароля. Потеря ключа лишит старые APK возможности обновляться новой подписью." -ForegroundColor Yellow
Write-Host ""
Write-Host "GitHub Actions Secrets:" -ForegroundColor Cyan
Write-Host "AURORA_ANDROID_KEYSTORE_BASE64 = содержимое $b64Path"
Write-Host "AURORA_ANDROID_KEYSTORE_USER   = $Alias"
Write-Host "AURORA_ANDROID_KEYSTORE_PASSWORD = пароль, который ты только что ввёл"
Write-Host ""
Write-Host "Keystore: $keystore"
