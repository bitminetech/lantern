# Run the runners of one target over vector files: one process for each
# runner and file, as many at once as the machine has cores. PowerShell 7.
# Usage: tests/runner/run.ps1 RUNNER_DIR VECTOR_DIR [FILE ...]
#
# The same as tests/runner/run.sh, for Windows: RUNNER_DIR holds
# runner-<preset>-<fork>.exe and runner-<preset>-<fork>-bls-off.exe, JOBS is the
# number of processes at once, and the output and status are those of run.sh.
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
    # the longest processes start early. A file <preset>-<fork>-*.bin goes to the
    # two runners of its preset and fork; other files are left out.
    $forks = 'phase0', 'altair', 'bellatrix', 'capella', 'deneb', 'electra', 'fulu'
    $work = $Files | ForEach-Object { Get-Item (Join-Path $VectorDir $_) } | Sort-Object Length -Descending | ForEach-Object {
        $parts = $_.Name.Split('-')
        $runner = "runner-$($parts[0])-$($parts[1])"
        if (Test-Path (Join-Path $RunnerDir "$runner$exe")) {
            "$runner $($_.Name)"
            "$runner-bls-off $($_.Name)"
            # The same with asm-crypto's sha variant (README, Target profile).
            if (Test-Path (Join-Path $RunnerDir "$runner-sha$exe")) {
                "$runner-sha $($_.Name)"
                "$runner-bls-off-sha $($_.Name)"
            }
        }
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
    $runners = foreach ($preset in 'mainnet', 'minimal') { foreach ($fork in $forks) {
        "runner-$preset-$fork"; "runner-$preset-$fork-bls-off"; "runner-$preset-$fork-sha"; "runner-$preset-$fork-bls-off-sha" } }
    foreach ($runner in $runners) {
        $runnerLogs = Get-ChildItem $logs -Filter "$runner.*.log" | Where-Object { $_.Name.StartsWith("$runner.") } | Sort-Object Name
        if (-not $runnerLogs) { continue }
        "== $runner"
        $peak = [ordered]@{}
        $fault = @{}
        $bad = @{}
        $passed = 0
        $failed = 0
        foreach ($log in $runnerLogs) {
            $totals = $false
            $ok = $false
            $called = @()
            foreach ($line in Get-Content $log.FullName) {
                if ($line -match '^STACK (\S+) (\d+) bytes') {
                    $name = $Matches[1]
                    $bytes = [int64]$Matches[2]
                    if (-not $peak.Contains($name) -or $bytes -gt $peak[$name]) { $peak[$name] = $bytes }
                    if ($line.Contains('ABI FAULT')) { $fault[$name] = $true }
                    $called += $name
                } elseif ($line -match '^(PASS|FAIL): (\d+) passed, (\d+) failed$') {
                    $passed += [int]$Matches[2]
                    $failed += [int]$Matches[3]
                    $totals = $true
                    $ok = $Matches[1] -eq 'PASS' -and [int]$Matches[3] -eq 0
                } elseif ($line -match '^EXIT (-?\d+)$') {
                    if (-not $totals) {
                        "FAIL $($log.BaseName): the process ended with status $($Matches[1]) and no totals"
                        $failed++
                    }
                    if ([int]$Matches[1] -ne 0) { $ok = $false }
                } else {
                    $line
                }
            }
            # Each function this process called passes only when the process passed.
            foreach ($name in $called) { if (-not $ok) { $bad[$name] = $true } }
        }
        foreach ($name in $peak.Keys) {
            "STACK $name $($peak[$name]) bytes$(if ($fault[$name]) { ' ABI FAULT' })"
        }
        foreach ($name in $peak.Keys) {
            "FUNCTION $name $(if ($bad[$name]) { 'FAIL' } else { 'PASS' })"
        }
        "$(if ($failed) { 'FAIL' } else { 'PASS' }): $passed passed, $failed failed"
        if ($failed) { $status = 1 }
    }
} finally {
    Remove-Item -Recurse -Force $logs
}
exit $status
