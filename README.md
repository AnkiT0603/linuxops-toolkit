# LinuxOps: Server Setup & Automation Toolkit

A small, reusable toolkit that sets up and hardens an Ubuntu server and automates routine operations: user management, disk-space monitoring, log cleanup and health checks. Jobs are scheduled with cron and systemd, every script writes an execution log, and everything is tracked in Git.

## What's inside

| Path | Purpose |
| --- | --- |
| `config/linuxops.conf` | All settings in one place (thresholds, folders, services, ports) |
| `lib/common.sh` | Shared functions: config loading, logging, error handling, locking |
| `scripts/setup_server.sh` | Installs packages, creates the admin group, hardens SSH, enables the firewall |
| `scripts/user_manager.sh` | Add, bulk-add, lock, unlock, remove and list users |
| `scripts/disk_monitor.sh` | Warns when filesystems pass the warning or critical threshold |
| `scripts/log_cleanup.sh` | Compresses old logs and deletes very old ones (`--dry-run` supported) |
| `scripts/health_check.sh` | CPU, memory, disk, services and process report |
| `cron/linuxops` | Cron schedule for disk monitoring and log cleanup |
| `systemd/linuxops-health.*` | systemd service and timer for the health check |
| `install.sh` | Installs the toolkit to `/opt/linuxops` and enables the schedules |
| `tests/check.sh` | Automated checks: syntax, permissions, ShellCheck, smoke tests |
| `data/users.csv` | Example input for bulk user creation |

## Requirements

- Ubuntu 22.04 or 24.04 (a VM is ideal)
- A user with `sudo` rights
- Internet access for package installation

## Quick start

```bash
git clone https://github.com/<your-username>/linuxops-toolkit.git
cd linuxops-toolkit
./tests/check.sh                     # 1. verify the toolkit
sudo ./scripts/setup_server.sh       # 2. set up and harden the server
sudo ./install.sh                    # 3. install and schedule the jobs
```

## Usage

```bash
sudo /opt/linuxops/scripts/user_manager.sh add alice developers
sudo /opt/linuxops/scripts/user_manager.sh bulk data/users.csv
sudo /opt/linuxops/scripts/user_manager.sh lock alice
sudo /opt/linuxops/scripts/user_manager.sh list
sudo /opt/linuxops/scripts/disk_monitor.sh       # or pass a test threshold: disk_monitor.sh 5
sudo /opt/linuxops/scripts/log_cleanup.sh --dry-run
sudo /opt/linuxops/scripts/health_check.sh
```

## Schedules

| Job | Scheduler | When |
| --- | --- | --- |
| Disk monitor | cron (`/etc/cron.d/linuxops`) | Every 15 minutes |
| Log cleanup | cron (`/etc/cron.d/linuxops`) | Daily at 02:30 |
| Health check | systemd timer (`linuxops-health.timer`) | Every 10 minutes |

## Logs and reports

| File | Contents |
| --- | --- |
| `/var/log/linuxops/<script>.log` | Timestamped execution log for each script |
| `/var/log/linuxops/health-report.txt` | The most recent health report |
| `/var/log/linuxops/cron.log` | Anything printed by cron jobs |
| `/var/backups/linuxops/` | Archived home folders of removed users |

## Configuration

Edit `/etc/linuxops/linuxops.conf` after installation (or `config/linuxops.conf` before). Re-running `install.sh` never overwrites an existing configuration.

## Security notes

- Root login over SSH is disabled; password login is disabled once `SSH_DISABLE_PASSWORD_LOGIN="yes"`.
- The firewall denies all incoming traffic except the ports in `FIREWALL_ALLOWED_PORTS`.
- Temporary user passwords are shown once on screen, never written to logs, and must be changed at first login.
- Scripts refuse to modify `root` or system accounts.

## Uninstall

```bash
sudo ./install.sh --uninstall     # removes scripts and schedules; keeps config and logs
```
