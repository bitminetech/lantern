# Run the four runners of one target over vector files: one process for each
# runner and file, as many at once as the machine has cores. PowerShell 7.
# Usage: tests/runner/run.ps1 RUNNER_DIR VECTOR_DIR [FILE ...]
#
# The same as tests/runner/run.sh, for Windows: RUNNER_DIR holds
# runner-<preset>.exe and runner-<preset>-bls-off.exe, JOBS is the number of
# processes at once, and the output and status are those of run.sh.
param(
    [Parameter(Mandatory)] [string] $RunnerDir,
    [Parameter(Mandatory)] [string] $VectorDir,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Files
)
$ErrorActionPreference = 'Stop'
$RunnerDir = (Resolve-Path $RunnerDir).Path
$VectorDir = (Resolve-Path $VectorDir).Path
if (-not $Files) { $Files = Get-ChildItem $VectorDir -Filter *.bin | ForEach-Object Name }
$jobs = if ($env:JOBS) { [int]$env:JOBS } else { [Environment]::ProcessorCount }
$exe = if ($IsWindows) { '.exe' } else { '' }
$logs = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))).FullName

try {
    # One work item for each runner and file, the largest files first, so that
    # the longest processes start early. A file goes to the runners of its preset.
    $work = $Files | ForEach-Object { Get-Item (Join-Path $VectorDir $_) } | Sort-Object Length -Descending | ForEach-Object {
        $preset = $_.Name.Split('-')[0]
        "runner-$preset $($_.Name)"
        "runner-$preset-bls-off $($_.Name)"
    }

    # Each process writes runner.file.log, and its exit status as the last line.
    $work | ForEach-Object -ThrottleLimit $jobs -Parallel {
        $runner, $file = $_ -split ' '
        $program = Join-Path $using:RunnerDir ($runner + $using:exe)
        $log = Join-Path $using:logs "$runner.$file.log"
        & $program $using:VectorDir $file *> $log
        Add-Content $log "EXIT $LASTEXITCODE"
    }

    $status = 0
    foreach ($runner in 'runner-mainnet', 'runner-mainnet-bls-off', 'runner-minimal', 'runner-minimal-bls-off') {
        $runnerLogs = Get-ChildItem $logs -Filter "$runner.*.log" | Where-Object { $_.Name.StartsWith("$runner.") } | Sort-Object Name
        if (-not $runnerLogs) { continue }
        "== $runner"
        $peak = [ordered]@{}
        $fault = @{}
        $passed = 0
        $failed = 0
        foreach ($log in $runnerLogs) {
            $totals = $false
            foreach ($line in Get-Content $log.FullName) {
                if ($line -match '^STACK (\S+) (\d+) bytes') {
                    $name = $Matches[1]
                    $bytes = [int64]$Matches[2]
                    if (-not $peak.Contains($name) -or $bytes -gt $peak[$name]) { $peak[$name] = $bytes }
                    if ($line.Contains('ABI FAULT')) { $fault[$name] = $true }
                } elseif ($line -match '^(PASS|FAIL): (\d+) passed, (\d+) failed$') {
                    $passed += [int]$Matches[2]
                    $failed += [int]$Matches[3]
                    $totals = $true
                } elseif ($line -match '^EXIT (-?\d+)$') {
                    if (-not $totals) {
                        "FAIL $($log.BaseName): the process ended with status $($Matches[1]) and no totals"
                        $failed++
                    }
                } else {
                    $line
                }
            }
        }
        foreach ($name in $peak.Keys) {
            "STACK $name $($peak[$name]) bytes$(if ($fault[$name]) { ' ABI FAULT' })"
        }
        "$(if ($failed) { 'FAIL' } else { 'PASS' }): $passed passed, $failed failed"
        if ($failed) { $status = 1 }
    }
} finally {
    Remove-Item -Recurse -Force $logs
}
exit $status
