#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# log_cleanup.sh - compress old .log files and delete very old compressed logs.
# Usage: sudo ./scripts/log_cleanup.sh [--dry-run]
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
load_config
setup_error_trap
acquire_lock

DRY_RUN="no"
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="yes"

size_kb() {
    du -sk "$1" 2> /dev/null | cut -f1
}

clean_dir() {
    local dir="$1" before after file compressed=0 deleted=0
    if [[ ! -d "$dir" ]]; then
        log WARN "Skipping $dir: folder does not exist"
        return 0
    fi
    before="$(size_kb "$dir")"

    # 1. Compress .log files not modified for more than LOG_COMPRESS_AFTER_DAYS days
    while IFS= read -r -d '' file; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            log INFO "[dry-run] would compress $file"
        else
            gzip -f "$file"
            log INFO "Compressed $file"
        fi
        compressed=$((compressed + 1))
    done < <(find "$dir" -type f -name "*.log" -mtime +"$LOG_COMPRESS_AFTER_DAYS" -print0)

    # 2. Delete compressed logs older than LOG_DELETE_AFTER_DAYS days
    while IFS= read -r -d '' file; do
        if [[ "$DRY_RUN" == "yes" ]]; then
            log INFO "[dry-run] would delete $file"
        else
            rm -f "$file"
            log INFO "Deleted $file"
        fi
        deleted=$((deleted + 1))
    done < <(find "$dir" -type f -name "*.gz" -mtime +"$LOG_DELETE_AFTER_DAYS" -print0)

    after="$(size_kb "$dir")"
    log INFO "$dir: $compressed compressed, $deleted deleted, size ${before}KB -> ${after}KB"
}

main() {
    local dir
    log INFO "Log cleanup started (dry run: $DRY_RUN)"
    for dir in $LOG_CLEAN_DIRS; do
        clean_dir "$dir"
    done
    log INFO "Log cleanup finished"
}

main "$@"
