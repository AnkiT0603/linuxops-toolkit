#!/usr/bin/env bash
# tests/check.sh - quick automated checks for the LinuxOps toolkit.
# Runs without root and without changing the system: it uses a temporary log folder.
# Usage: ./tests/check.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }

# A test configuration that writes logs to the temporary folder
sed -e "s|^LOG_DIR=.*|LOG_DIR=\"$TMP/logs\"|" \
    -e "s|^LOG_CLEAN_DIRS=.*|LOG_CLEAN_DIRS=\"$TMP/oldlogs\"|" \
    config/linuxops.conf > "$TMP/test.conf"
export LINUXOPS_CONFIG="$TMP/test.conf"

echo "1. Syntax and permissions"
for f in lib/common.sh install.sh scripts/*.sh; do
    if bash -n "$f"; then pass "syntax: $f"; else fail "syntax: $f"; fi
done
for f in install.sh scripts/*.sh tests/check.sh; do
    if [[ -x "$f" ]]; then pass "executable: $f"; else fail "not executable: $f (run chmod +x $f)"; fi
done

echo "2. ShellCheck"
if command -v shellcheck > /dev/null; then
    if shellcheck -x lib/common.sh install.sh scripts/*.sh tests/check.sh; then
        pass "shellcheck found no problems"
    else
        fail "shellcheck reported problems (see above)"
    fi
else
    echo "  SKIP  shellcheck not installed (sudo apt install shellcheck)"
fi

echo "3. Scripts run correctly"
./scripts/disk_monitor.sh > /dev/null 2>&1
rc=$?
if [[ $rc -le 2 && -s "$TMP/logs/disk_monitor.log" ]]; then
    pass "disk_monitor ran (exit $rc) and wrote its log"
else
    fail "disk_monitor exit $rc or no log written"
fi

./scripts/health_check.sh > /dev/null 2>&1
rc=$?
if [[ $rc -le 1 && -s "$TMP/logs/health-report.txt" ]]; then
    pass "health_check ran (exit $rc) and wrote its report"
else
    fail "health_check exit $rc or no report written"
fi

mkdir -p "$TMP/oldlogs"
echo "old entry" > "$TMP/oldlogs/app.log"
touch -d "10 days ago" "$TMP/oldlogs/app.log"
./scripts/log_cleanup.sh --dry-run > "$TMP/cleanup.out" 2>&1
if grep -q "would compress" "$TMP/cleanup.out" && [[ -f "$TMP/oldlogs/app.log" ]]; then
    pass "log_cleanup --dry-run reports old files and changes nothing"
else
    fail "log_cleanup --dry-run did not behave as expected"
fi

if ./scripts/user_manager.sh > /dev/null 2>&1; then
    fail "user_manager without arguments should exit non-zero"
else
    pass "user_manager shows usage and exits non-zero without arguments"
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
