#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# setup_server.sh - prepare and harden a fresh Ubuntu server for LinuxOps.
# Safe to run more than once (idempotent).
# Usage: sudo ./scripts/setup_server.sh
set -euo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"
load_config
setup_error_trap
require_root

PACKAGES="openssh-server ufw cron git curl"
SSH_DROPIN="/etc/ssh/sshd_config.d/01-linuxops-hardening.conf"

install_packages() {
    log INFO "Installing packages: $PACKAGES"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y -qq $PACKAGES > /dev/null
    log INFO "Packages installed"
}

create_admin_group() {
    if getent group "$ADMIN_GROUP" > /dev/null; then
        log INFO "Group $ADMIN_GROUP already exists"
    else
        groupadd "$ADMIN_GROUP"
        log INFO "Created group $ADMIN_GROUP"
    fi
}

prepare_directories() {
    install -d -m 750 -o root -g "$ADMIN_GROUP" "$LOG_DIR"
    install -d -m 700 -o root -g root "$BACKUP_DIR"
    log INFO "Log folder $LOG_DIR (750) and backup folder $BACKUP_DIR (700) ready"
}

harden_ssh() {
    local password_auth="yes"
    [[ "$SSH_DISABLE_PASSWORD_LOGIN" == "yes" ]] && password_auth="no"

    cat > "$SSH_DROPIN" << EOF
# Managed by LinuxOps setup_server.sh
PermitRootLogin no
PasswordAuthentication $password_auth
KbdInteractiveAuthentication no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
    chmod 600 "$SSH_DROPIN"

    # Never reload SSH with a broken config: test it first
    if sshd -t; then
        systemctl reload ssh 2> /dev/null || systemctl reload sshd
        log INFO "SSH hardened (root login off, password login: $password_auth)"
    else
        rm -f "$SSH_DROPIN"
        die "SSH config test failed; hardening file removed, SSH unchanged"
    fi
}

configure_firewall() {
    local port
    ufw default deny incoming > /dev/null
    ufw default allow outgoing > /dev/null
    for port in $FIREWALL_ALLOWED_PORTS; do
        ufw allow "$port" > /dev/null
        log INFO "Firewall: allowed $port"
    done
    ufw --force enable > /dev/null
    log INFO "Firewall enabled: deny incoming by default"
}

enable_services() {
    systemctl enable --now cron > /dev/null 2>&1
    systemctl enable --now ssh > /dev/null 2>&1 || true
    log INFO "cron and ssh services enabled"
}

main() {
    log INFO "===== Server setup started ====="
    install_packages
    create_admin_group
    prepare_directories
    harden_ssh
    configure_firewall
    enable_services
    log INFO "===== Server setup finished ====="
    ufw status verbose
}

main "$@"
