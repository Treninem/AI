# Test-only process lifecycle: bounded parent wait, then own-descendant cleanup.
function Invoke-AuroraBoundedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Phase,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
    )
    $ErrorActionPreference = 'Stop'
    Write-Host "AURORA_WINDOWS_PHASE_START $Phase timeout=$TimeoutSeconds"
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
    $startedUtc = $process.StartTime.ToUniversalTime()
    try {
        # Start-Process -Wait also waits on descendants. A headless app may exit
        # while its owned runtime remains alive; wait for this parent explicitly.
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            throw "Windows phase timed out: $Phase pid=$($process.Id) after $TimeoutSeconds seconds"
        }
        $process.Refresh()
        $exitCode = $process.ExitCode
        Write-Host "AURORA_WINDOWS_PHASE_END $Phase exit=$exitCode"
        return $exitCode
    } finally {
        # Snapshot only this process's descendants, never all AuroraFox/Python
        # processes. Creation times protect against reused process IDs.
        try {
            $snapshot = @(Get-CimInstance Win32_Process)
            $parents = @($process.Id)
            $owned = @()
            for ($depth = 0; $depth -lt 32 -and $parents.Count -gt 0; $depth++) {
                $children = @($snapshot | Where-Object {
                    $_.ParentProcessId -in $parents -and $_.CreationDate.ToUniversalTime() -ge $startedUtc
                })
                $owned += $children
                $parents = @($children | ForEach-Object { $_.ProcessId })
            }
            foreach ($child in $owned) {
                $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($child.ProcessId)"
                if ($current -and $current.CreationDate -eq $child.CreationDate) {
                    Write-Host "AURORA_WINDOWS_CHILD_CLEANUP $Phase pid=$($child.ProcessId) name=$($child.Name)"
                    Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
                }
            }
        } finally {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) { throw "Cannot stop timed-out phase $Phase" }
                }
            } finally {
                $process.Dispose()
            }
        }
    }
}
