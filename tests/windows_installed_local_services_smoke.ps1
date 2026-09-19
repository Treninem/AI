param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$ReportDir = 'artifacts/windows-offline-services'
)

$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path $InstallDir).Path
$computerRoot = Join-Path $installRoot 'computer'
$filesRoot = Join-Path $installRoot 'file_intelligence'
$computerPython = Join-Path $computerRoot 'python\python.exe'
$filesPython = Join-Path $filesRoot 'python\python.exe'
$computerService = Join-Path $computerRoot 'computer_service.py'
$filesService = Join-Path $filesRoot 'file_service.py'
foreach ($required in @(
    $computerPython,
    (Join-Path $computerRoot 'vendor\fastapi'),
    $computerService,
    $filesPython,
    (Join-Path $filesRoot 'vendor\fastapi'),
    $filesService,
    (Join-Path $filesRoot 'ocr_runtime\tesseract.exe')
)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Installed offline service asset is missing: $required" }
}

New-Item -ItemType Directory -Force $ReportDir | Out-Null
$reportRoot = (Resolve-Path $ReportDir).Path
$stateRoot = Join-Path $reportRoot 'user'
$sandboxRoot = Join-Path $reportRoot 'sandbox'
$localServicesPort = '18867'
New-Item -ItemType Directory -Force $stateRoot,$sandboxRoot | Out-Null
$token = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$previous = @{}
$keys = @(
    'PYTHONPATH','AURORAFOX_USER_DIR','AURORAFOX_LOCAL_SERVICES_PORT',
    'AURORAFOX_FILES_PORT','AURORAFOX_API_PORT',
    'AURORAFOX_COMPUTER_PORT','AURORAFOX_COMPUTER_TOKEN',
    'AURORAFOX_SANDBOX_ROOT','AURORAFOX_PARENT_PID',
    'AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX'
)
foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }

$externalIpv4 = @('0.0.0.0-126.255.255.255','128.0.0.0-255.255.255.255')
$externalIpv6 = @('::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
$rulePrefix = 'AuroraFoxInstalledServices-' + [Guid]::NewGuid().ToString('N')
$rules = @()
$computerProcess = $null
$filesProcess = $null
$computerStdout = Join-Path $reportRoot 'computer.stdout.log'
$computerStderr = Join-Path $reportRoot 'computer.stderr.log'
$filesStdout = Join-Path $reportRoot 'files.stdout.log'
$filesStderr = Join-Path $reportRoot 'files.stderr.log'

function Wait-ServiceHealth([string]$Url, [int]$ExpectedPort, [Diagnostics.Process]$Process, [string]$Stdout, [string]$Stderr) {
    $lastRequestError = ''
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $out = if (Test-Path $Stdout) { Get-Content $Stdout -Raw } else { '' }
            $err = if (Test-Path $Stderr) { Get-Content $Stderr -Raw } else { '' }
            throw "Installed service exited with $($Process.ExitCode).`nstdout:`n$out`nstderr:`n$err"
        }
        $expectedListener = Get-NetTCPConnection -LocalPort $ExpectedPort -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::1','::') }
        if ($expectedListener) {
            try {
                $health = Invoke-RestMethod $Url -TimeoutSec 10
                if ($health.ok) { return $health }
            } catch { $lastRequestError = $_.Exception.Message }
        }
        Start-Sleep -Seconds 1
    }
    $Process.Refresh()
    $expectedListener = Get-NetTCPConnection -LocalPort $ExpectedPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object LocalAddress,LocalPort,OwningProcess
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::1','::') } |
        Select-Object LocalAddress,LocalPort,OwningProcess
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($Process.Id)" -ErrorAction SilentlyContinue |
        Select-Object ProcessId,ParentProcessId,ExecutablePath,CommandLine
    $out = if (Test-Path $Stdout) { Get-Content $Stdout -Raw } else { '' }
    $err = if (Test-Path $Stderr) { Get-Content $Stderr -Raw } else { '' }
    $exitCode = if ($Process.HasExited) { $Process.ExitCode } else { '<running>' }
    throw @"
Installed service did not become healthy: $Url
ExpectedPort: $ExpectedPort
ProcessId: $($Process.Id)
ProcessExited: $($Process.HasExited)
ExitCode: $exitCode
LastRequestError: $lastRequestError
Process:
$($processInfo | Out-String)
Expected-port listeners:
$($expectedListener | Out-String)
Loopback/all-interface listening sockets:
$($listening | Out-String)
stdout:
$out
stderr:
$err
"@
}

try {
    foreach ($program in @($computerPython,$filesPython)) {
        $name = $rulePrefix + '-' + $rules.Count
        New-NetFirewallRule -DisplayName $name -Direction Outbound -Program $program -Action Block -Profile Any -RemoteAddress ($externalIpv4 + $externalIpv6) | Out-Null
        $rules += $name
    }

    [Environment]::SetEnvironmentVariable('PYTHONPATH', (Join-Path $computerRoot 'vendor'), 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_COMPUTER_PORT', '18866', 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_COMPUTER_TOKEN', $token, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_SANDBOX_ROOT', $sandboxRoot, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_PARENT_PID', "$PID", 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_ALLOW_DEGRADED_LOCAL_SANDBOX', $null, 'Process')
    $computerProcess = Start-Process -FilePath $computerPython -ArgumentList @($computerService) -WorkingDirectory $computerRoot -RedirectStandardOutput $computerStdout -RedirectStandardError $computerStderr -PassThru
    $computerHealth = Wait-ServiceHealth 'http://127.0.0.1:18866/health' 18866 $computerProcess $computerStdout $computerStderr
    if (-not $computerHealth.computer_supported -or $computerHealth.planning_owner -ne 'aurorafox_core' -or $computerHealth.network_required) {
        throw 'Installed Computer Agent health contract failed'
    }
    $headers = @{
        'X-AuroraFox-Computer-Token' = $token
        'X-AuroraFox-Autonomy-Allowed' = '1'
    }
    $capabilities = Invoke-RestMethod 'http://127.0.0.1:18866/capabilities' -Headers $headers -TimeoutSec 10
    if (-not $capabilities.ok -or -not $capabilities.sandbox -or -not $capabilities.local_core_planning_required) {
        throw 'Installed Computer Agent capabilities contract failed'
    }
    $computerText = 'AuroraFox installed offline computer sandbox'
    $writeBody = @{path='installed-proof.txt';content=$computerText} | ConvertTo-Json
    $computerWrite = Invoke-RestMethod 'http://127.0.0.1:18866/sandbox/write' -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($writeBody)) -TimeoutSec 10
    $computerRead = Invoke-RestMethod 'http://127.0.0.1:18866/sandbox/read?path=installed-proof.txt' -Headers $headers -TimeoutSec 10
    if (-not $computerWrite.ok -or -not $computerRead.ok -or $computerRead.text -ne $computerText) {
        throw 'Installed Computer Agent sandbox write/read failed'
    }

    [Environment]::SetEnvironmentVariable('PYTHONPATH', (Join-Path $filesRoot 'vendor'), 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_USER_DIR', $stateRoot, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_LOCAL_SERVICES_PORT', $localServicesPort, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_FILES_PORT', $localServicesPort, 'Process')
    [Environment]::SetEnvironmentVariable('AURORAFOX_API_PORT', $localServicesPort, 'Process')
    $filesProcess = Start-Process -FilePath $filesPython -ArgumentList @(
        '-m','uvicorn','file_service:app','--host','127.0.0.1','--port',$localServicesPort,'--log-level','info'
    ) -WorkingDirectory $filesRoot -RedirectStandardOutput $filesStdout -RedirectStandardError $filesStderr -PassThru
    $filesHealthUrl = "http://127.0.0.1:$localServicesPort/health"
    $filesHealth = Wait-ServiceHealth $filesHealthUrl ([int]$localServicesPort) $filesProcess $filesStdout $filesStderr
    if (-not $filesHealth.ocr_available -or -not ($filesHealth.ocr_languages -contains 'eng') -or -not ($filesHealth.ocr_languages -contains 'rus')) {
        throw 'Installed File Intelligence offline OCR health contract failed'
    }
    $samplePath = Join-Path $reportRoot 'installed-file-sample.txt'
    $fileText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('QXVyb3JhRm94INC70L7QutCw0LvRjNC90YvQuSDRgNCw0LfQsdC+0YAg0YTQsNC50LvQvtCy'))
    [IO.File]::WriteAllText($samplePath, $fileText, (New-Object Text.UTF8Encoding($false)))
    $analyzeBody = @{path=$samplePath;question='';visual=$false;max_chars=10000} | ConvertTo-Json
    $fileAnalysis = Invoke-RestMethod 'http://127.0.0.1:18867/analyze' -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($analyzeBody)) -TimeoutSec 60
    if (-not $fileAnalysis.ok -or $fileAnalysis.kind -ne 'text' -or $fileAnalysis.content -ne $fileText) {
        throw 'Installed File Intelligence TXT analysis failed'
    }

    @{
        passed = $true
        installed = $true
        outbound_firewall_block = $true
        loopback_allowed = $true
        computer = @{health=$computerHealth;capabilities=$capabilities;write=$computerWrite;read=$computerRead}
        files = @{health=$filesHealth;analysis=$fileAnalysis}
    } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $reportRoot 'report.json') -Encoding UTF8
    Write-Host 'AURORA_WINDOWS_INSTALLED_OFFLINE_FILES_COMPUTER_OK'
} finally {
    foreach ($process in @($filesProcess,$computerProcess)) {
        if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
    foreach ($name in $rules) { Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue }
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
