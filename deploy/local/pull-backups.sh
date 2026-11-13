#!/usr/bin/env bash
set -euo pipefail
umask 077
here=$(cd "$(dirname "$0")" && pwd)
host=${SOVDELO_BACKUP_HOST:-31.31.207.196}
destination=${SOVDELO_BACKUP_DIR:-$HOME/Backups/sovdelo}
[[ $host =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'Некорректный адрес сервера'; exit 1; }
[ -f "${SOVDELO_BACKUP_KEY:-$HOME/.ssh/sovdelo_backup}" ] || { echo 'Нет ключа sovdelo_backup'; exit 1; }
install -d -m 0700 "$HOME/.cache/sovdelo-backup" "$destination"
exec 9>"$HOME/.cache/sovdelo-backup/pull.lock"
flock -n 9 || { echo 'Скачивание уже запущено'; exit 0; }
rsync -rlt --safe-links --exclude='.verified.*' --exclude='.last-sync.json' --delay-updates --partial-dir=.rsync-partial \
 --chmod=Du=rwx,Dgo=,Fu=rw,Fgo= --rsh="$here/ssh-readonly.sh" \
 "root@$host:./" "$destination/"
python3 "$here/verify-backups.py" "$destination"
