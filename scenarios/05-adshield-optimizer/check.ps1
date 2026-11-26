# Kiểm tra độc lập kịch bản: 05-adshield-optimizer
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "05-adshield-optimizer" -Action "check"
