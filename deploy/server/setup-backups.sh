#!/usr/bin/env bash
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || exit 1
here=$(cd "$(dirname "$0")" && pwd)
[ -x /usr/bin/rrsync ] || { echo 'Не найден /usr/bin/rrsync'; exit 1; }
grep -q '# SovDelo deploy guard' /etc/nginx/sites-available/sovdelo || { echo 'Сначала установить обработчик Actions (патч 16)'; exit 1; }
read -r -p 'Вставьте ОТКРЫТЫЙ ключ из sovdelo_backup.pub: ' key
[[ $key =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]] || { echo 'Нужен открытый Ed25519 ключ'; exit 1; }
printf '%s\n' "$key" | ssh-keygen -lf - >/dev/null
install -d -o root -g root -m 0755 /usr/local/lib/sovdelo
install -d -o root -g root -m 0700 /var/backups/sovdelo
for file in backup-now.sh verify-restore.sh; do install -o root -g root -m 0755 "$here/$file" "/usr/local/lib/sovdelo/$file"; done
install -o root -g root -m 0755 "$here/../local/verify-backups.py" /usr/local/lib/sovdelo/verify-backups.py
for unit in sovdelo-backup.service sovdelo-backup.timer; do install -m 0644 "$here/$unit" "/etc/systemd/system/$unit"; done
fields=$(printf '%s\n' "$key" | awk '{print $1" "$2}')
line="restrict,command=\"/usr/bin/rrsync -ro /var/backups/sovdelo\" $fields sovdelo-backup"
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
if grep -Fq "$fields" /root/.ssh/authorized_keys; then
 grep -Fxq "$line" /root/.ssh/authorized_keys || { echo 'Ключ уже используется для другой цели; создайте отдельный'; exit 1; }
else printf '\n%s\n' "$line" >> /root/.ssh/authorized_keys;fi
systemctl daemon-reload
systemctl start sovdelo-backup.service
bash /usr/local/lib/sovdelo/verify-restore.sh
systemctl enable --now sovdelo-backup.timer
systemctl list-timers sovdelo-backup.timer --no-pager
printf '\nСерверная копия создана, пробное восстановление выполнено. Настройте локальное скачивание.\n'
