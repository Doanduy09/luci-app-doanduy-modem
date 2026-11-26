# Kiểm tra độc lập kịch bản: 01-dialer-watchdog
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "01-dialer-watchdog" -Action "check"
