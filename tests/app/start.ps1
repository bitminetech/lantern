# The start of the lantern binary on Windows (docs/reference/app.md), as tests/app/start.sh: a
# faulty option gives exit code 1 and its line, with today's UTC date; a network directory with no config.yaml gives
# exit code 2 and a "cannot read" line.
# With NETWORK, the binary runs on that network directory with --http-max-connections 2, and
# tests/app/api.py checks its Beacon API's connections.
# Usage: tests/app/start.ps1 BINARY [NETWORK]
param([string]$Binary, [string]$Network = '')
$fail = 0
$out = (& $Binary --bogus 2>&1 | ForEach-Object { "$_" }) -join "`n"
$code = $LASTEXITCODE
Write-Output $out
if ($code -eq 1 -and $out -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ERROR faulty option at argument 0$' -and $out.StartsWith((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))) { Write-Output 'PASS a faulty option' } else { Write-Output "FAIL a faulty option: exit $code"; $fail = 1 }
$out = (& $Binary --network-dir C:\nonexistent 2>&1 | ForEach-Object { "$_" }) -join "`n"
$code = $LASTEXITCODE
Write-Output $out
if ($code -eq 2 -and $out -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ERROR cannot read C:\\nonexistent/config\.yaml: error ') { Write-Output 'PASS a missing network directory' } else { Write-Output "FAIL a missing network directory: exit $code"; $fail = 1 }
if ($Network -ne '') {
    $log = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $Binary -ArgumentList @('--network-dir', $Network, '--port', '19100', '--http-port', '15052', '--http-max-connections', '2') -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    python (Join-Path $PSScriptRoot 'api.py') 15052 (Join-Path $Network 'genesis.ssz')
    if ($LASTEXITCODE -ne 0) { $fail = 1 }
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Get-Content $log -TotalCount 5
    Get-Content "$log.err" -TotalCount 5
}
exit $fail
