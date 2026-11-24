#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# disk_monitor.sh - check every real filesystem against warning and critical limits.
# Exit codes: 0 = all OK, 1 = at least one WARNING, 2 = at least one CRITICAL
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
load_config
setup_error_trap
acquire_lock

# Optional argument overrides the warning threshold, e.g. ./disk_monitor.sh 5 for testing
WARN="${1:-$DISK_WARN_PCT}"
CRIT="$DISK_CRIT_PCT"
[[ "$WARN" =~ ^[0-9]+$ ]] || die "Threshold must be a whole number, got: $WARN"

worst=0

show_largest_dirs() {
    local mount="$1"
    log INFO "Largest folders under $mount:"
    du -xh --max-depth=1 "$mount" 2> /dev/null | sort -h | tail -n 5 |
        while read -r size path; do log INFO "    $size  $path"; done || true
}

# -P: one line per filesystem, -h: readable sizes; skip in-memory and snapshot filesystems
while read -r fs _size _used avail pct mount; do
    use="${pct%\%}"
    if [[ "$use" -ge "$CRIT" ]]; then
        log CRITICAL "$mount is ${use}% full (critical limit ${CRIT}%) on $fs, $avail free"
        show_largest_dirs "$mount"
        worst=2
    elif [[ "$use" -ge "$WARN" ]]; then
        log WARN "$mount is ${use}% full (warning limit ${WARN}%) on $fs, $avail free"
        if [[ "$worst" -lt 1 ]]; then worst=1; fi
    else
        log INFO "$mount is ${use}% full: OK"
    fi
done < <(df -Ph -x tmpfs -x devtmpfs -x squashfs -x overlay 2> /dev/null | tail -n +2)

log INFO "Disk check finished with status $worst"
exit "$worst"
