#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# lib/common.sh - shared functions for every LinuxOps script.
# Load it with:  source "$(dirname "$0")/../lib/common.sh"

LINUXOPS_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE=""

# Load settings from $LINUXOPS_CONFIG, else the installed copy, else the repository copy
load_config() {
    local cfg="${LINUXOPS_CONFIG:-/etc/linuxops/linuxops.conf}"
    [[ -f "$cfg" ]] || cfg="$LINUXOPS_HOME/config/linuxops.conf"
    if [[ ! -f "$cfg" ]]; then
        echo "ERROR: configuration file not found" >&2
        exit 2
    fi
    # shellcheck source=../config/linuxops.conf
    source "$cfg"
    mkdir -p "$LOG_DIR" 2> /dev/null || true
    LOG_FILE="$LOG_DIR/$SCRIPT_NAME.log"
}

# log LEVEL message... : a timestamped line on screen and in the script's log file
log() {
    local level="$1"
    shift
    local line
    line="$(date '+%F %T') [$level] [$SCRIPT_NAME] $*"
    if [[ "$level" == "ERROR" ]]; then
        echo "$line" >&2
    else
        echo "$line"
    fi
    if [[ -n "$LOG_FILE" ]] && touch "$LOG_FILE" 2> /dev/null; then
        echo "$line" >> "$LOG_FILE"
    fi
}

# die message... : log an error and stop with exit code 1
die() {
    log ERROR "$*"
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root. Try: sudo $0"
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" > /dev/null 2>&1 || die "Required command not found: $cmd"
    done
}

# Report the failing line whenever a command fails (works with set -e)
setup_error_trap() {
    set -o errtrace    # also apply the trap inside functions
    trap 'log ERROR "Command failed (exit $?) at line $LINENO: $BASH_COMMAND"' ERR
}

# Allow only one copy of a script to run at a time (important for scheduled jobs)
acquire_lock() {
    local lock_file="${TMPDIR:-/tmp}/linuxops-$SCRIPT_NAME-$EUID.lock"
    exec 9> "$lock_file"
    flock -n 9 || die "Another copy of $SCRIPT_NAME is already running."
}
