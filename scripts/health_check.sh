#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# health_check.sh - one-screen health report: CPU load, memory, disk, services, processes.
# Writes the latest report to $LOG_DIR/health-report.txt
# Exit codes: 0 = healthy, 1 = at least one problem found
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
load_config
setup_error_trap
acquire_lock

PROBLEMS=0
REPORT="$LOG_DIR/health-report.txt"
if [[ ! -w "$LOG_DIR" ]]; then
    # Not running as root: keep the report in the temporary folder instead
    REPORT="${TMPDIR:-/tmp}/linuxops-health-report-$EUID.txt"
fi

# result CHECK STATUS DETAILS : print one aligned line and count problems
result() {
    local check="$1" status="$2" details="$3"
    printf "%-10s %-8s %s\n" "$check" "$status" "$details"
    if [[ "$status" == "WARNING" || "$status" == "CRITICAL" ]]; then
        PROBLEMS=$((PROBLEMS + 1))
        log WARN "$check: $details" >&2    # to the log and the screen, not into the report
    fi
}

check_cpu() {
    local cores load load_int
    cores="$(nproc)"
    load="$(cut -d ' ' -f1 /proc/loadavg)"
    load_int="${load%.*}"
    if [[ "$load_int" -ge "$cores" ]]; then
        result "CPU" "WARNING" "load $load on $cores cores"
    else
        result "CPU" "OK" "load $load on $cores cores"
    fi
}

check_memory() {
    local avail_pct
    avail_pct="$(free | awk '/^Mem:/ {printf "%d", $7 / $2 * 100}')"
    if [[ "$avail_pct" -lt "$MEM_MIN_AVAILABLE_PCT" ]]; then
        result "Memory" "WARNING" "only ${avail_pct}% available"
    else
        result "Memory" "OK" "${avail_pct}% available"
    fi
}

check_disk() {
    local used
    used="$(df -P / | awk 'NR == 2 {print $5}' | tr -d '%')"
    if [[ "$used" -ge "$DISK_WARN_PCT" ]]; then
        result "Disk" "WARNING" "/ is ${used}% full"
    else
        result "Disk" "OK" "/ is ${used}% full"
    fi
}

check_services() {
    local service failed
    if ! command -v systemctl > /dev/null 2>&1; then
        result "Services" "SKIPPED" "systemctl not available"
        return 0
    fi
    for service in $HEALTH_SERVICES; do
        if systemctl is-active --quiet "$service"; then
            result "Service" "OK" "$service is running"
        else
            result "Service" "CRITICAL" "$service is NOT running"
        fi
    done
    failed="$(systemctl --failed --no-legend --plain 2> /dev/null | wc -l)" || failed=0
    if [[ "$failed" -gt 0 ]]; then
        result "Units" "WARNING" "$failed systemd unit(s) failed: run systemctl --failed"
    else
        result "Units" "OK" "no failed systemd units"
    fi
}

check_processes() {
    local zombies
    zombies="$(ps -eo stat= | awk '$1 ~ /^Z/' | wc -l)"
    if [[ "$zombies" -gt 0 ]]; then
        result "Zombies" "WARNING" "$zombies zombie process(es)"
    else
        result "Zombies" "OK" "no zombie processes"
    fi
}

top_processes() {
    echo
    echo "Top 3 processes by CPU:"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 4
}

main() {
    {
        echo "===== Health check: $(hostname) at $(date '+%F %T') ====="
        echo "Uptime: $(uptime -p 2> /dev/null || uptime)"
        printf "%-10s %-8s %s\n" "CHECK" "STATUS" "DETAILS"
        check_cpu
        check_memory
        check_disk
        check_services
        check_processes
        top_processes
        echo
        if [[ "$PROBLEMS" -eq 0 ]]; then
            echo "Result: HEALTHY"
        else
            echo "Result: $PROBLEMS problem(s) found"
        fi
    } > "$REPORT.tmp"

    # The { } block ran in this shell, so PROBLEMS is up to date here
    mv "$REPORT.tmp" "$REPORT"
    cat "$REPORT"
    log INFO "Health check finished: $PROBLEMS problem(s). Report: $REPORT"
    if [[ "$PROBLEMS" -eq 0 ]]; then
        exit 0
    fi
    exit 1
}

main "$@"
