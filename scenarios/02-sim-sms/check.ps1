# Kiểm tra độc lập kịch bản: 02-sim-sms
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "02-sim-sms" -Action "check"
