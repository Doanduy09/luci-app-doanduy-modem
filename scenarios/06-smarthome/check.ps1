# Kiểm tra độc lập kịch bản: 06-smarthome
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "06-smarthome" -Action "check"
