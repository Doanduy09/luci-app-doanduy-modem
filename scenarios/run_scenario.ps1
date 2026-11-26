# [VERIFIED-GOLDEN: modular-scenario-runner-ps1 | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
# Bộ Quản Lý Kịch Bản Độc Lập Trên Máy Tính Windows Cho Anh Duy
param(
    [string]$Group = "all",
    [ValidateSet("list", "check", "deploy")]
    [string]$Action = "check",
    [string]$Router = "192.168.1.1"
)
$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

$GroupDirs = if ($Group -eq "all") {
    Get-ChildItem -Path $PSScriptRoot -Directory | Where-Object { $_.Name -match '^0[1-9]-' } | Sort-Object Name
} else {
    $single = Join-Path $PSScriptRoot $Group
    if (-not (Test-Path $single)) { throw "Không tìm thấy nhóm kịch bản: $Group" }
    @(Get-Item $single)
}

if ($Action -eq "list") {
    foreach ($gd in $GroupDirs) {
        $m = Get-Content -Raw -Encoding UTF8 (Join-Path $gd.FullName "manifest.json") | ConvertFrom-Json
        Write-Host ("=== " + $m.id + " : " + $m.title + " (" + $m.files.Count + " tệp) ===") -ForegroundColor Cyan
        foreach ($f in $m.files) { Write-Host ("   - " + $f.repo + "  -->  " + $f.router) }
    }
    exit 0
}

foreach ($gd in $GroupDirs) {
    $m = Get-Content -Raw -Encoding UTF8 (Join-Path $gd.FullName "manifest.json") | ConvertFrom-Json
    Write-Host (">> [" + $Action.ToUpper() + "] " + $m.title) -ForegroundColor Green
    foreach ($f in $m.files) {
        $full = Join-Path $RepoRoot ($f.repo -replace '/', '\')
        if (-not (Test-Path $full)) { throw "Thiếu tệp: $($f.repo)" }
        $bytes = [System.IO.File]::ReadAllBytes($full)
        for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
            if ($bytes[$i] -eq 13 -and $bytes[$i + 1] -eq 10) {
                throw "Phát hiện xuống dòng CRLF trong tệp OpenWrt: $($f.repo)"
            }
        }
        if ($f.repo.EndsWith(".js")) {
            & node --check $full
            if ($LASTEXITCODE -ne 0) { throw "Lỗi cú pháp JS: $($f.repo)" }
        } elseif ($f.repo.EndsWith(".json")) {
            $null = Get-Content -Raw -Encoding UTF8 $full | ConvertFrom-Json
        }
        Write-Host ("   [OK] " + $f.repo)

        if ($Action -eq "deploy") {
            $remoteDir = ($f.router -replace '/[^/]+$', '')
            & ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=6 "root@$Router" "mkdir -p '$remoteDir'"
            & scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=6 $full "root@${Router}:$($f.router)"
            & ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=6 "root@$Router" "chmod $($f.mode) '$($f.router)'"
            Write-Host ("   [DEPLOYED] -> root@" + $Router + ":" + $f.router) -ForegroundColor Yellow
        }
    }
    if ($Action -eq "deploy") {
        & ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=6 "root@$Router" "rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache* && /etc/init.d/rpcd restart"
        Write-Host ("   [DONE] Đã làm mới RPCD & cache LuCI cho nhóm " + $m.id) -ForegroundColor Cyan
    }
}
# [/VERIFIED-GOLDEN]
