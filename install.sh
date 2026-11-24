#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# install.sh - install LinuxOps to /opt/linuxops and schedule its jobs.
# Usage: sudo ./install.sh            install or update
#        sudo ./install.sh --uninstall remove scripts and schedules (keeps config and logs)
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/common.sh
source lib/common.sh
load_config
setup_error_trap
require_root

INSTALL_DIR="/opt/linuxops"
CONF_DIR="/etc/linuxops"
UNIT_DIR="/etc/systemd/system"

install_toolkit() {
    log INFO "Installing LinuxOps to $INSTALL_DIR"

    getent group "$ADMIN_GROUP" > /dev/null || groupadd "$ADMIN_GROUP"

    # Scripts: owned by root, readable and runnable by everyone, writable only by root
    install -d -m 755 "$INSTALL_DIR"
    rm -rf "${INSTALL_DIR:?}/lib" "${INSTALL_DIR:?}/scripts" "${INSTALL_DIR:?}/config"
    cp -r lib scripts config README.md "$INSTALL_DIR/"    # config/ holds the default settings
    chown -R root:root "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"/scripts/*.sh
    chmod 644 "$INSTALL_DIR"/lib/*.sh

    # Configuration: keep an existing one so local changes are not overwritten
    install -d -m 750 -o root -g "$ADMIN_GROUP" "$CONF_DIR"
    if [[ -f "$CONF_DIR/linuxops.conf" ]]; then
        log INFO "Keeping existing $CONF_DIR/linuxops.conf"
    else
        install -m 640 -o root -g "$ADMIN_GROUP" config/linuxops.conf "$CONF_DIR/linuxops.conf"
        log INFO "Installed $CONF_DIR/linuxops.conf"
    fi

    install -d -m 750 -o root -g "$ADMIN_GROUP" "$LOG_DIR"

    # Schedules: cron for disk monitoring and log cleanup
    install -m 644 -o root -g root cron/linuxops /etc/cron.d/linuxops
    log INFO "Installed cron jobs in /etc/cron.d/linuxops"

    # Schedules: a systemd timer for the health check
    install -m 644 systemd/linuxops-health.service systemd/linuxops-health.timer "$UNIT_DIR/"
    systemctl daemon-reload
    systemctl enable --now linuxops-health.timer > /dev/null
    log INFO "Enabled systemd timer linuxops-health.timer"

    log INFO "Installation complete. Next runs:"
    systemctl list-timers linuxops-health.timer --no-pager
}

uninstall_toolkit() {
    log INFO "Uninstalling LinuxOps"
    systemctl disable --now linuxops-health.timer > /dev/null 2>&1 || true
    rm -f "$UNIT_DIR/linuxops-health.service" "$UNIT_DIR/linuxops-health.timer" /etc/cron.d/linuxops
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    log INFO "Removed scripts and schedules. Kept $CONF_DIR and $LOG_DIR"
}

case "${1:-}" in
    --uninstall) uninstall_toolkit ;;
    "") install_toolkit ;;
    *) die "Unknown option: $1 (use --uninstall or no option)" ;;
esac
