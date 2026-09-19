$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows_bounded_process.ps1')
$fixtureDir = Join-Path $env:RUNNER_TEMP ('AuroraFox process fixture ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null
$hostExe = Join-Path $PSHOME 'pwsh.exe'
$exitScript = Join-Path $fixtureDir 'exit fixture.ps1'
$hangScript = Join-Path $fixtureDir 'hang fixture.ps1'
$spawnScript = Join-Path $fixtureDir 'spawn fixture.ps1'
$childPidFile = Join-Path $fixtureDir 'child.pid'
Set-Content $exitScript 'param([int]$Code); exit $Code' -Encoding UTF8
Set-Content $hangScript 'Start-Sleep -Seconds 30' -Encoding UTF8
Set-Content $spawnScript @'
param([string]$HangScript, [string]$PidFile)
$child = Start-Process (Join-Path $PSHOME 'pwsh.exe') -ArgumentList @('-NoProfile','-File', ('"' + $HangScript + '"')) -PassThru
Set-Content $PidFile $child.Id
exit 0
'@ -Encoding UTF8
try {
    $code = Invoke-AuroraBoundedProcess -FilePath $hostExe -ArgumentList @('-NoProfile','-File',"`"$exitScript`"",'17') -Phase 'regression-exit-code' -TimeoutSeconds 20
    if ($code -ne 17) { throw "Exit code lost: $code" }
    $code = Invoke-AuroraBoundedProcess -FilePath $hostExe -ArgumentList @('-NoProfile','-File',"`"$spawnScript`"","`"$hangScript`"","`"$childPidFile`"") -Phase 'regression-parent-exit' -TimeoutSeconds 20
    if ($code -ne 0) { throw 'Parent process did not exit successfully' }
    $childProcessId = [int](Get-Content $childPidFile)
    $child = Get-Process -Id $childProcessId -ErrorAction SilentlyContinue
    if ($child -and -not $child.WaitForExit(5000)) { throw 'Owned child survived parent completion cleanup' }
    $refused = $false
    try {
        Invoke-AuroraBoundedProcess -FilePath $hostExe -ArgumentList @('-NoProfile','-File',"`"$hangScript`"") -Phase 'regression-timeout' -TimeoutSeconds 1 | Out-Null
    } catch {
        if ($_.Exception.Message -notmatch 'timed out: regression-timeout pid=([0-9]+)') { throw }
        $timedOutProcessId = [int]$Matches[1]
        $refused = $true
        if (Get-Process -Id $timedOutProcessId -ErrorAction SilentlyContinue) { throw 'Timed-out process survived cleanup' }
    }
    if (-not $refused) { throw 'Timeout was silently accepted' }
    Write-Host 'AURORA_WINDOWS_BOUNDED_PROCESS_SMOKE_OK'
} finally {
    if (Test-Path $childPidFile) {
        Stop-Process -Id ([int](Get-Content $childPidFile)) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $fixtureDir -Recurse -Force -ErrorAction SilentlyContinue
}
