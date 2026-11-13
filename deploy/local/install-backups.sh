#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" != 0 ] || { echo 'Запускайте локально от roman, не root'; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
command -v rsync >/dev/null
[ -f "$HOME/.ssh/sovdelo_backup" ] || { echo 'Сначала создать отдельный ключ sovdelo_backup'; exit 1; }
install -d -m 0700 "$HOME/.local/lib/sovdelo-backup" "$HOME/.config/systemd/user" "$HOME/Backups/sovdelo"
for file in pull-backups.sh ssh-readonly.sh verify-backups.py; do install -m 0700 "$here/$file" "$HOME/.local/lib/sovdelo-backup/$file"; done
cat > "$HOME/.config/systemd/user/sovdelo-backup-pull.service" <<'UNIT'
[Unit]
Description=Download and verify SovDelo backups
[Service]
Type=oneshot
UMask=0077
ExecStart=%h/.local/lib/sovdelo-backup/pull-backups.sh
TimeoutStartSec=30min
UNIT
cat > "$HOME/.config/systemd/user/sovdelo-backup-pull.timer" <<'UNIT'
[Unit]
Description=Download SovDelo backups on login and hourly
[Timer]
OnStartupSec=2min
OnCalendar=hourly
Persistent=true
Unit=sovdelo-backup-pull.service
[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user start sovdelo-backup-pull.service
systemctl --user enable --now sovdelo-backup-pull.timer
systemctl --user list-timers sovdelo-backup-pull.timer --no-pager
printf '\nКопии: %s/Backups/sovdelo\n' "$HOME"
