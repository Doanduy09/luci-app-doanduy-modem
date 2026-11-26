# Đẩy nóng độc lập kịch bản 04-sentinel-telegram-remote lên Router (không đụng các nhóm khác)
param([string]$Router = "192.168.1.1")
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
& (Join-Path $RepoRoot "scenarios\run_scenario.ps1") -Group "04-sentinel-telegram-remote" -Action "deploy" -Router $Router
