#!/usr/bin/env bash
set -euo pipefail
umask 077
[ "$(id -u)" = 0 ] || { echo 'Запускайте от root'; exit 1; }
[ -L /var/www/sovdelo/current ] && [ -f /var/www/sovdelo/.managed-sovdelo ] || { echo 'Сначала установить СовДело'; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
read -r -p 'Вставьте ОТКРЫТЫЙ ключ ssh-ed25519 из sovdelo_actions.pub: ' key
if [[ ! $key =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ .*)?$ ]]; then echo 'Нужен открытый Ed25519 ключ'; exit 1; fi
printf '%s\n' "$key" | ssh-keygen -lf - >/dev/null
install -d -o root -g root -m 0755 /usr/local/lib/sovdelo
for file in ssh-deploy.sh update-release.sh receive-release.py validate-release.py; do install -o root -g root -m 0755 "$here/$file" "/usr/local/lib/sovdelo/$file"; done
install -d -o root -g root -m 0700 /var/lib/sovdelo-deploy /var/lib/sovdelo-deploy/incoming /var/backups/sovdelo
# Add only an application maintenance guard to this site's managed configuration.
python3 - <<'PY'
from pathlib import Path
p=Path('/etc/nginx/sites-available/sovdelo');s=p.read_text()
if '# Managed by SovDelo' not in s or 'root /var/www/sovdelo/current/public;' not in s:raise SystemExit('Неизвестная конфигурация Nginx')
if '# SovDelo deploy guard' not in s:
 old='location / { try_files $uri $uri/ /index.php?$query_string; }'
 new='''# SovDelo deploy guard
 location = /up { try_files $uri /index.php?$query_string; }
 location / { if (-f /var/www/sovdelo/deploying) { return 503; } try_files $uri $uri/ /index.php?$query_string; }'''
 if s.count(old)!=1:raise SystemExit('Не найден ожидаемый блок приложения')
 Path('/etc/nginx/sites-available/sovdelo.before-actions').write_text(s)
 p.write_text(s.replace(old,new))
PY
if ! nginx -t; then
 if [ -f /etc/nginx/sites-available/sovdelo.before-actions ]; then cp /etc/nginx/sites-available/sovdelo.before-actions /etc/nginx/sites-available/sovdelo; fi
 exit 1
fi
systemctl reload nginx
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
fields=$(printf '%s\n' "$key" | awk '{print $1" "$2}')
line="restrict,command=\"/usr/local/lib/sovdelo/ssh-deploy.sh\" $fields sovdelo-actions"
if grep -Fq "$fields" /root/.ssh/authorized_keys; then
 grep -Fxq "$line" /root/.ssh/authorized_keys || { echo 'Этот ключ уже используется для другой цели. Создайте отдельный ключ СовДела.'; exit 1; }
else
 printf '\n%s\n' "$line" >> /root/.ssh/authorized_keys
fi
printf '\nДля секрета SOVDELO_KNOWN_HOSTS:\n'
awk '{print "31.31.207.196 "$1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub
printf '\nГотово. Ключи rrsync не изменялись.\n'
