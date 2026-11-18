# The start of the lantern binary on Windows (docs/reference/app.md), as tests/app/start.sh: a
# faulty option gives exit code 1 and its line; a network directory with no config.yaml gives
# exit code 2 and a "cannot read" line.
# Usage: tests/app/start.ps1 BINARY
param([string]$Binary)
$fail = 0
$out = (& $Binary --bogus 2>&1 | ForEach-Object { "$_" }) -join "`n"
$code = $LASTEXITCODE
Write-Output $out
if ($code -eq 1 -and $out -eq 'lantern: faulty option at argument 0') { Write-Output 'PASS a faulty option' } else { Write-Output "FAIL a faulty option: exit $code"; $fail = 1 }
$out = (& $Binary --network-dir C:\nonexistent 2>&1 | ForEach-Object { "$_" }) -join "`n"
$code = $LASTEXITCODE
Write-Output $out
if ($code -eq 2 -and $out.StartsWith('lantern: cannot read C:\nonexistent/config.yaml: error ')) { Write-Output 'PASS a missing network directory' } else { Write-Output "FAIL a missing network directory: exit $code"; $fail = 1 }
exit $fail
