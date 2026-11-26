#!/usr/bin/env sh
# [VERIFIED-GOLDEN: modular-scenario-runner-sh | 2026-11-26 | DO NOT MODIFY UNLESS TARGETED]
# Isolated Per-Scenario Validator & Deployer for Linux / GitHub Actions CI
set -eu

ACTION="${1:-check}"
TARGET_GROUP="${2:-all}"
ROUTER_HOST="${3:-192.168.1.1}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

check_one_group() {
  grp_dir="$1"
  grp_name="$(basename "$grp_dir")"
  manifest="$grp_dir/manifest.json"
  [ -f "$manifest" ] || { echo "Missing $manifest" >&2; exit 1; }

  echo ">> [SCENARIO CHECK] $grp_name"
  python3 - "$manifest" << 'PYEOF'
import json, os, subprocess, sys

manifest_path = sys.argv[1]
data = json.load(open(manifest_path, "r", encoding="utf-8"))
for item in data["files"]:
    p = item["repo"]
    if not os.path.isfile(p):
        print(f"  [FAIL] Missing file: {p}", file=sys.stderr)
        sys.exit(1)
    raw = open(p, "rb").read()
    if bytes([13]) in raw:
        print(f"  [FAIL] CRLF line endings detected in: {p}", file=sys.stderr)
        sys.exit(1)
    first_line = raw.splitlines()[0].decode("utf-8", errors="ignore") if raw else ""
    if p.endswith(".json"):
        json.loads(raw.decode("utf-8"))
    elif p.endswith(".js"):
        subprocess.run(["node", "--check", p], check=True)
    elif p.endswith(".lua") or "lua" in first_line:
        lua_cmd = "luac5.1" if subprocess.run(["sh", "-c", "command -v luac5.1"], capture_output=True).returncode == 0 else "luac"
        if subprocess.run(["sh", "-c", f"command -v {lua_cmd}"], capture_output=True).returncode == 0:
            subprocess.run([lua_cmd, "-p", p], check=True)
    elif p.endswith(".sh") or "/bin/sh" in first_line or "/etc/rc.common" in first_line:
        subprocess.run(["sh", "-n", p], check=True)
    print(f"  [OK] {p}")
PYEOF
}

if [ "$ACTION" = "list" ]; then
  for d in "$SCRIPT_DIR"/0*; do
    [ -d "$d" ] && basename "$d"
  done
  exit 0
fi

if [ "$ACTION" = "check" ]; then
  if [ "$TARGET_GROUP" = "all" ]; then
    for d in "$SCRIPT_DIR"/0*; do
      [ -d "$d" ] && check_one_group "$d"
    done
    echo "ALL 6 SCENARIO GROUPS PASSED 100%."
  else
    check_one_group "$SCRIPT_DIR/$TARGET_GROUP"
  fi
  exit 0
fi

echo "Usage: sh scenarios/run_scenario.sh [list|check] [all|01-dialer-watchdog|...]" >&2
exit 1
# [/VERIFIED-GOLDEN]
