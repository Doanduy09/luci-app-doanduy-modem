# Kiểm tra độc lập kịch bản: 04-sentinel-telegram-remote
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "04-sentinel-telegram-remote" -Action "check"
