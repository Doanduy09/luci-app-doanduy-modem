# Kiểm tra độc lập kịch bản: 03-rf-band-imei
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "03-rf-band-imei" -Action "check"
