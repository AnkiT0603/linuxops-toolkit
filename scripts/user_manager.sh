#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# user_manager.sh - create, lock, unlock, remove and list user accounts.
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
load_config
setup_error_trap

usage() {
    cat << EOF
Usage: sudo $0 <command> [arguments]

Commands:
  add <username> [group]   Create a user (optionally in a group) with a temporary password
  bulk <file.csv>          Create users from a CSV file: username,group
  lock <username>          Lock an account (e.g. someone is on leave)
  unlock <username>        Unlock an account
  remove <username>        Archive the home folder, then delete the user
  list                     List regular (human) user accounts
EOF
    exit 1
}

valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# Refuse to touch root or system accounts (UID below 1000)
assert_regular_user() {
    local user="$1" uid
    id "$user" > /dev/null 2>&1 || die "User $user does not exist"
    uid="$(id -u "$user")"
    [[ "$uid" -ge 1000 && "$user" != "root" ]] || die "Refusing to modify system account $user (UID $uid)"
}

add_user() {
    local user="$1" group="${2:-}" password
    valid_username "$user" || die "Invalid username: $user"
    if id "$user" > /dev/null 2>&1; then
        log WARN "User $user already exists, skipping"
        return 0
    fi
    if [[ -n "$group" ]] && ! getent group "$group" > /dev/null; then
        groupadd "$group"
        log INFO "Created group $group"
    fi

    useradd --create-home --shell /bin/bash ${group:+--groups "$group"} "$user"
    password="$(openssl rand -base64 12)"
    echo "$user:$password" | chpasswd
    chage --lastday 0 "$user"        # must choose a new password at first login
    chmod 750 "/home/$user"

    log INFO "Created user $user${group:+ in group $group}"
    # The password is shown once on screen and never written to the log
    echo "  Temporary password for $user: $password  (must be changed at first login)"
}

bulk_add() {
    local file="$1" user group count=0
    [[ -r "$file" ]] || die "Cannot read file: $file"
    while IFS=, read -r user group; do
        [[ -z "$user" || "$user" == "username" || "$user" == \#* ]] && continue
        add_user "$user" "$group"
        count=$((count + 1))
    done < "$file"
    log INFO "Bulk add finished: $count entries processed from $file"
}

lock_user() {
    assert_regular_user "$1"
    usermod --lock --expiredate 1 "$1"
    log INFO "Locked user $1"
}

unlock_user() {
    assert_regular_user "$1"
    usermod --unlock --expiredate "" "$1"
    log INFO "Unlocked user $1"
}

remove_user() {
    local user="$1" archive
    assert_regular_user "$user"
    install -d -m 700 "$BACKUP_DIR"
    archive="$BACKUP_DIR/home-$user-$(date +%F-%H%M%S).tar.gz"
    if [[ -d "/home/$user" ]]; then
        tar -czf "$archive" -C /home "$user"
        log INFO "Archived /home/$user to $archive"
    fi
    pkill -KILL -u "$user" 2> /dev/null || true
    userdel --remove "$user" 2> /dev/null || die "Could not delete user $user"
    log INFO "Removed user $user"
}

list_users() {
    printf "%-15s %-8s %-10s %s\n" "USER" "UID" "STATUS" "GROUPS"
    getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1, $3}' |
        while read -r user uid; do
            local status="active"
            [[ "$(passwd -S "$user" 2> /dev/null | awk '{print $2}')" == "L" ]] && status="locked"
            printf "%-15s %-8s %-10s %s\n" "$user" "$uid" "$status" "$(id -nG "$user")"
        done
}

main() {
    [[ $# -ge 1 ]] || usage
    local command="$1"
    shift
    case "$command" in
        list) list_users ;;
        add) require_root; [[ $# -ge 1 ]] || usage; add_user "$@" ;;
        bulk) require_root; [[ $# -eq 1 ]] || usage; bulk_add "$1" ;;
        lock) require_root; [[ $# -eq 1 ]] || usage; lock_user "$1" ;;
        unlock) require_root; [[ $# -eq 1 ]] || usage; unlock_user "$1" ;;
        remove) require_root; [[ $# -eq 1 ]] || usage; remove_user "$1" ;;
        *) usage ;;
    esac
}

main "$@"
